import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/entry.dart';
import '../app/store_scope.dart';
import '../booklet/stamp_image.dart';
import '../post/post_page.dart';
import '../widgets/snack.dart';
import 'crop_page.dart';

abstract class StampScanner {
  Future<File?> scan();

  Future<File?> pickPhoto({required bool camera});
}

class PlatformStampScanner implements StampScanner {
  static const _channel = MethodChannel('open_timeline/scan');

  @override
  Future<File?> scan() async {
    final path = await _channel.invokeMethod<String>('scan');
    return path == null ? null : File(path);
  }

  @override
  Future<File?> pickPhoto({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
    );
    return x == null ? null : File(x.path);
  }
}

Future<File?> scanWithMessage(
  BuildContext context,
  StampScanner scanner,
) async {
  String reason;
  try {
    return await scanner.scan();
  } on PlatformException catch (e) {
    reason = e.message ?? e.code;
  } on MissingPluginException {
    reason = 'not available on this device';
  }
  if (!context.mounted) return null;
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('The scanner could not start'),
      content: SingleChildScrollView(
        child: Text(
          'You can still add the stamp from a photo, but it will not be '
          'flattened automatically.\n\nReason: $reason',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Gallery'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Camera'),
        ),
      ],
    ),
  );
  if (choice == null) return null;
  try {
    return await scanner.pickPhoto(camera: choice);
  } on PlatformException catch (e) {
    if (context.mounted) {
      showSnack(context, "Couldn't open that: ${e.message ?? e.code}");
    }
    return null;
  }
}

Future<File?> cropFromPage(
  NavigatorState navigator,
  File page, {
  int saved = 0,
}) async {
  final bytes = await navigator.push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => CropPage(file: page, saved: saved),
    ),
  );
  if (bytes == null) return null;
  final out = File(
    '${page.parent.path}/crop-${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await out.writeAsBytes(bytes);
  return out;
}

Future<void> _discard(File file) async {
  try {
    await file.delete();
  } catch (_) {}
}

Future<void> newStamp(BuildContext context, {StampScanner? scanner}) async {
  final store = StoreScope.read(context);
  final me = store.settings.me.trim();
  if (me.isEmpty) {
    showSnack(context, 'Set "Your email" in Settings first');
    return;
  }
  final navigator = Navigator.of(context);
  final page = await scanWithMessage(
    context,
    scanner ?? PlatformStampScanner(),
  );
  if (page == null) return;
  try {
    var saved = 0;
    while (true) {
      final crop = await cropFromPage(navigator, page, saved: saved);
      if (crop == null) break;
      final base = Entry.create(
        author: me,
        kind: kindStamp,
      ).copyWith(color: store.settings.myColor);
      final String name;
      try {
        name = await store.importMedia(base, crop);
      } finally {
        await _discard(crop);
      }
      final paper = await paperColorOf(store.mediaFile(base, name));
      final filed = await navigator.push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PostPage(
            entry: base.copyWith(
              media: [name],
              blend: paper != null && isLightPaper(paper),
            ),
            isNew: true,
            scanner: scanner,
          ),
          fullscreenDialog: true,
        ),
      );
      if (filed == true) saved++;
    }
  } finally {
    await _discard(page);
  }
}
