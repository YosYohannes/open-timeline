import 'package:flutter/services.dart';

abstract class KeepAlive {
  Future<void> start();
  Future<void> stop();
}

class NoKeepAlive implements KeepAlive {
  const NoKeepAlive();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class PlatformKeepAlive implements KeepAlive {
  static const _channel = MethodChannel('open_timeline/sync');

  @override
  Future<void> start() => _call('start');

  @override
  Future<void> stop() => _call('stop');

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
