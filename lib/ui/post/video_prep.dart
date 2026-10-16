import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const kMaxVideoShortSide = 1080;
const kVideoBitrate = 6000000;
const kVideoWarnBytes = 50 * 1024 * 1024;

class VideoInfo {
  const VideoInfo(this.width, this.height);

  final int width;
  final int height;

  int get shortSide => math.min(width, height);
}

bool needsShrink(VideoInfo info) => info.shortSide > kMaxVideoShortSide;

String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) {
    return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

abstract class VideoTools {
  Future<VideoInfo?> info(String path);

  /// Returns the output path, or null when cancelled.
  Future<String?> shrink(
    String src,
    String dest, {
    void Function(double progress)? onProgress,
  });

  Future<void> cancel();
}

class PlatformVideoTools implements VideoTools {
  static const _channel = MethodChannel('open_timeline/video');

  @override
  Future<VideoInfo?> info(String path) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('info', {
        'path': path,
      });
      final w = (m?['width'] as num?)?.toInt() ?? 0;
      final h = (m?['height'] as num?)?.toInt() ?? 0;
      return w > 0 && h > 0 ? VideoInfo(w, h) : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> shrink(
    String src,
    String dest, {
    void Function(double progress)? onProgress,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        onProgress?.call((call.arguments as num).toDouble().clamp(0, 1));
      }
    });
    return _channel
        .invokeMethod<String>('shrink', {
          'src': src,
          'dest': dest,
          'shortSide': kMaxVideoShortSide,
          'bitrate': kVideoBitrate,
        })
        .whenComplete(() => _channel.setMethodCallHandler(null));
  }

  @override
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }
}

class PreparedVideo {
  const PreparedVideo(this.file, {required this.isTemp});

  final File file;
  final bool isTemp;
}

/// Shrinks a video above 1080p and asks before adding a large one. Null means the user cancelled.
Future<PreparedVideo?> prepareVideo(
  BuildContext context,
  File source, {
  VideoTools? tools,
  Directory? tempDir,
}) async {
  final t = tools ?? PlatformVideoTools();
  var file = source;
  var isTemp = false;

  final info = await t.info(source.path);
  if (info != null && needsShrink(info) && context.mounted) {
    final dir = tempDir ?? await getTemporaryDirectory();
    if (!context.mounted) return null;
    final dest =
        '${dir.path}/shrunk_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Shrinking video'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scaling down to ${kMaxVideoShortSide}p to save Drive space.',
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: p > 0 ? p : null),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: t.cancel, child: const Text('Cancel')),
          ],
        ),
      ).whenComplete(() => dialogOpen = false),
    );
    String? out;
    var failed = false;
    try {
      out = await t.shrink(
        source.path,
        dest,
        onProgress: (p) => progress.value = p,
      );
    } catch (_) {
      failed = true;
    }
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!failed && out == null) return null;
    if (failed && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not shrink the video; using the original'),
        ),
      );
    }
    if (out != null) {
      file = File(out);
      isTemp = true;
    }
  }

  final bytes = await file.length();
  if (bytes > kVideoWarnBytes && context.mounted) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Large video'),
        content: Text(
          'This video is ${formatBytes(bytes)}. It will use that much of your '
          'Google Drive and take a while to sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (isTemp) {
        await file.delete();
      }
      return null;
    }
  }
  return PreparedVideo(file, isTemp: isTemp);
}
