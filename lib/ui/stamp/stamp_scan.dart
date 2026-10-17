import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/entry.dart';
import '../app/store_scope.dart';
import '../post/post_page.dart';
import '../widgets/snack.dart';

abstract class StampScanner {
  Future<File?> scan();
}

class PlatformStampScanner implements StampScanner {
  static const _channel = MethodChannel('open_timeline/scan');

  @override
  Future<File?> scan() async {
    final path = await _channel.invokeMethod<String>('scan');
    return path == null ? null : File(path);
  }
}

Future<File?> scanWithMessage(
  BuildContext context,
  StampScanner scanner,
) async {
  try {
    return await scanner.scan();
  } on PlatformException catch (e) {
    if (context.mounted) {
      showSnack(context, "Couldn't open the scanner: ${e.message ?? e.code}");
    }
  } on MissingPluginException {
    if (context.mounted) showSnack(context, 'Scanning is not available here');
  }
  return null;
}

Future<void> newStamp(BuildContext context, {StampScanner? scanner}) async {
  final store = StoreScope.read(context);
  final me = store.settings.me.trim();
  if (me.isEmpty) {
    showSnack(context, 'Set "Your email" in Settings first');
    return;
  }
  final navigator = Navigator.of(context);
  final file = await scanWithMessage(
    context,
    scanner ?? PlatformStampScanner(),
  );
  if (file == null) return;
  final base = Entry.create(
    author: me,
    kind: kindStamp,
  ).copyWith(color: store.settings.myColor);
  final String name;
  try {
    name = await store.importMedia(base, file);
  } finally {
    try {
      await file.delete();
    } catch (_) {}
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PostPage(
        entry: base.copyWith(media: [name]),
        isNew: true,
        scanner: scanner,
      ),
      fullscreenDialog: true,
    ),
  );
}
