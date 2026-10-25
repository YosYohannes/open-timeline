import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/entry.dart';
import '../app/store_scope.dart';
import '../booklet/subject_segmenter.dart';
import '../post/post_page.dart';
import '../widgets/snack.dart';
import 'crop_page.dart';
import 'detected_page.dart';

abstract class StampPhotos {
  Future<File?> pick({required bool camera});
}

class PlatformStampPhotos implements StampPhotos {
  @override
  Future<File?> pick({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 90,
    );
    return x == null ? null : File(x.path);
  }
}

Future<File?> askForPhoto(BuildContext context, StampPhotos photos) async {
  final camera = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('source-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            key: const ValueKey('source-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    ),
  );
  if (camera == null) return null;
  try {
    return await photos.pick(camera: camera);
  } on PlatformException catch (e) {
    if (context.mounted) {
      showSnack(context, "Couldn't open that: ${e.message ?? e.code}");
    }
    return null;
  }
}

/// Asks the phone for the stamps in [photo], with a spinner on screen.
Future<List<Rect>?> findStamps(BuildContext context, File photo) async {
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Looking for stamps…')),
          ],
        ),
      ),
    ),
  );
  try {
    return await subjectSegmenter.detect(photo);
  } finally {
    navigator.pop();
  }
}

typedef CropResult = ({File? crop, bool anotherPage});

Future<CropResult> cropFromPage(
  NavigatorState navigator,
  File page, {
  int saved = 0,
  String? notice,
}) async {
  final result = await navigator.push<Object>(
    MaterialPageRoute(
      builder: (_) => CropPage(file: page, saved: saved, notice: notice),
    ),
  );
  if (result is AnotherPage) return (crop: null, anotherPage: true);
  if (result is! Uint8List) return (crop: null, anotherPage: false);
  final out = File(
    '${page.parent.path}/crop-${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await out.writeAsBytes(result);
  return (crop: out, anotherPage: false);
}

/// One stamp from [photo]: taken automatically when the phone finds exactly
/// one, otherwise cropped by hand.
Future<File?> cropOneStamp(BuildContext context, File photo) async {
  final navigator = Navigator.of(context);
  final found = await findStamps(context, photo);
  if (found != null && found.length == 1 && context.mounted) {
    final out = await _cropBoxes(photo, found);
    if (out.isNotEmpty) return out.first;
  }
  if (!context.mounted) return null;
  return (await cropFromPage(navigator, photo)).crop;
}

Future<List<File>> _cropBoxes(File photo, List<Rect> boxes) async {
  final codec = await ui.instantiateImageCodec(await photo.readAsBytes());
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final out = <File>[];
  try {
    for (final b in boxes) {
      final area = _padded(b, size);
      final file = File(
        '${photo.parent.path}/crop-${DateTime.now().microsecondsSinceEpoch}-${out.length}.png',
      );
      await file.writeAsBytes(await cropToPng(image, area));
      out.add(file);
    }
  } finally {
    image.dispose();
  }
  return out;
}

Rect _padded(Rect fraction, Size image) {
  final box = Rect.fromLTWH(
    fraction.left * image.width,
    fraction.top * image.height,
    fraction.width * image.width,
    fraction.height * image.height,
  );
  final pad = box.shortestSide * 0.08 + 6;
  return box.inflate(pad).intersect(Offset.zero & image);
}

Future<void> _discard(File file) async {
  try {
    await file.delete();
  } catch (_) {}
}

Entry _sameEvent(Entry base, Entry from) => base.copyWith(
  time: from.time,
  utcOffsetMinutes: from.utcOffsetMinutes,
  lat: from.lat,
  lon: from.lon,
  place: from.place,
  country: from.country,
  series: from.series,
  tags: from.tags,
);

class _Batch {
  int saved = 0;
  Entry? previous;
}

Future<bool> _fileStamp(
  BuildContext context,
  NavigatorState navigator,
  _Batch batch,
  File crop,
  StampPhotos? photos,
) async {
  final store = StoreScope.read(context);
  var base = Entry.create(
    author: store.settings.me.trim(),
    kind: kindStamp,
  ).copyWith(color: store.settings.myColor);
  final previous = batch.previous;
  if (previous != null) base = _sameEvent(base, previous);
  final String name;
  try {
    name = await store.importMedia(base, crop);
  } finally {
    await _discard(crop);
  }
  final filed = await navigator.push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PostPage(
        entry: base.copyWith(media: [name], blend: true),
        isNew: true,
        photos: photos,
      ),
      fullscreenDialog: true,
    ),
  );
  if (filed == true) {
    batch.saved++;
    batch.previous = store.byId(base.id);
  }
  return filed == true;
}

/// Files the stamps found in or cropped from [photo]. Returns true when the
/// user asked for another photo.
Future<bool> _stampsFromPhoto(
  BuildContext context,
  NavigatorState navigator,
  _Batch batch,
  File photo,
  StampPhotos? photos,
) async {
  final found = await findStamps(context, photo);
  if (!context.mounted) return false;
  List<Rect>? chosen;
  String? notice;
  if (found != null && found.isNotEmpty) {
    final answer = await navigator.push<Object>(
      MaterialPageRoute(
        builder: (_) => DetectedStampsPage(file: photo, boxes: found),
      ),
    );
    if (answer == null) return false;
    if (answer is List<Rect>) chosen = answer;
  } else {
    final why = subjectSegmenter.lastError;
    notice = why == null
        ? "Couldn't find any stamps, crop them by hand"
        : "Couldn't find stamps ($why), crop them by hand";
  }

  if (chosen != null) {
    for (final crop in await _cropBoxes(photo, chosen)) {
      if (!context.mounted) return false;
      await _fileStamp(context, navigator, batch, crop, photos);
    }
    if (batch.saved == 0 || !context.mounted) return false;
    return _askAnother(context, batch.saved);
  }

  while (context.mounted) {
    final result = await cropFromPage(
      navigator,
      photo,
      saved: batch.saved,
      notice: notice,
    );
    notice = null;
    if (result.anotherPage) return true;
    final crop = result.crop;
    if (crop == null) return false;
    if (!context.mounted) return false;
    await _fileStamp(context, navigator, batch, crop, photos);
  }
  return false;
}

Future<bool> _askAnother(BuildContext context, int saved) async {
  final another = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(saved == 1 ? '1 stamp saved' : '$saved stamps saved'),
      content: const Text('Add another photo with the same details?'),
      actions: [
        TextButton(
          key: const ValueKey('batch-done'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Done'),
        ),
        FilledButton(
          key: const ValueKey('batch-another'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Another photo'),
        ),
      ],
    ),
  );
  return another == true;
}

Future<void> newStamp(BuildContext context, {StampPhotos? photos}) async {
  final store = StoreScope.read(context);
  if (store.settings.me.trim().isEmpty) {
    showSnack(context, 'Set "Your email" in Settings first');
    return;
  }
  final navigator = Navigator.of(context);
  final source = photos ?? PlatformStampPhotos();
  final batch = _Batch();
  var more = true;
  while (more) {
    if (!context.mounted) return;
    final photo = await askForPhoto(context, source);
    if (photo == null) return;
    try {
      if (!context.mounted) return;
      more = await _stampsFromPhoto(context, navigator, batch, photo, photos);
    } finally {
      await _discard(photo);
    }
  }
}
