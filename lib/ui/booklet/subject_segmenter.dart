import 'dart:io';

import 'package:flutter/services.dart';

abstract class SubjectSegmenter {
  /// The image with everything but the main subject made transparent, saved as
  /// a PNG, or null when the phone could not find a subject.
  Future<File?> segment(File image);

  /// Why the last call found nothing, when the phone said so.
  String? get lastError;
}

class PlatformSubjectSegmenter implements SubjectSegmenter {
  static const _channel = MethodChannel('open_timeline/scan');

  @override
  String? lastError;

  @override
  Future<File?> segment(File image) async {
    lastError = null;
    try {
      final path = await _channel.invokeMethod<String>('segment', image.path);
      if (path == null) lastError = 'No item was found in the picture';
      return path == null ? null : File(path);
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
      return null;
    } on MissingPluginException {
      lastError = 'Not available on this device';
      return null;
    }
  }
}

SubjectSegmenter subjectSegmenter = PlatformSubjectSegmenter();
