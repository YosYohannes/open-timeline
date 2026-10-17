import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import 'collage_layout.dart';
import 'stamp_cutout.dart';

const kInkBrown = Color(0xFF6B624F);

class StampPrint extends StatelessWidget {
  const StampPrint({super.key, required this.entry, required this.placed});

  final Entry entry;
  final Placed placed;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final image = entry.media.where(isImage).firstOrNull;
    final file = image == null ? null : store.mediaFile(entry, image);
    final cut = entry.blend && file != null
        ? cachedCutout(file, entry.cutout)
        : null;

    Widget body;
    if (file == null) {
      body = const SizedBox.shrink();
    } else if (cut != null) {
      body = _CutOut(cutout: cut);
    } else {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(kMatSide),
          child: Image.file(
            file,
            width: placed.image.width,
            height: placed.image.height,
            fit: BoxFit.contain,
            cacheWidth: 700,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }

    return Positioned(
      key: ValueKey(entry.id),
      left: placed.rect.left,
      top: placed.rect.top,
      width: placed.rect.width,
      height: placed.rect.height,
      child: InkWell(
        key: ValueKey('print-${entry.id}'),
        onTap: () => openEntry(context, entry.id),
        child: body,
      ),
    );
  }
}

class _CutOut extends StatelessWidget {
  const _CutOut({required this.cutout});

  final Cutout cutout;

  @override
  Widget build(BuildContext context) {
    Widget picture({Color? tint}) => Image.file(
      cutout.file,
      fit: BoxFit.fill,
      cacheWidth: 700,
      gaplessPlayback: true,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.srcIn,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: const Offset(0, 1.5),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 1.3, sigmaY: 1.3),
            child: picture(tint: Colors.black.withValues(alpha: 0.3)),
          ),
        ),
        picture(),
      ],
    );
  }
}
