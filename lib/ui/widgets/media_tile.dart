import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/entry.dart';

class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.file,
    required this.name,
    this.size = 84,
    this.radius = 8,
    this.onTap,
  });

  final File file;
  final String name;
  final double size;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
    );

    Widget child;
    if (!file.existsSync()) {
      child = placeholder(
        isVideo(name)
            ? Icons.videocam_off_outlined
            : Icons.image_not_supported_outlined,
      );
    } else if (isVideo(name)) {
      child = Container(
        color: Colors.blueGrey.shade800,
        alignment: Alignment.center,
        child: const Icon(
          Icons.play_circle_fill_rounded,
          color: Colors.white,
          size: 36,
        ),
      );
    } else if (isImage(name)) {
      child = Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 300,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
      );
    } else {
      child = placeholder(Icons.insert_drive_file_outlined);
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (onTap != null)
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: onTap),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
