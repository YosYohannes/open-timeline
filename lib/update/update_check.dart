import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const kLatestReleaseApi =
    'https://api.github.com/repos/YosYohannes/open-timeline/releases/latest';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.url});

  final String version;
  final String url;
}

({List<int> numbers, bool pre})? _parse(String version) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.]+)?')
      .firstMatch(version.trim());
  if (m == null) return null;
  return (
    numbers: [for (var i = 1; i <= 3; i++) int.parse(m[i]!)],
    pre: m[4] != null,
  );
}

bool isNewerVersion(String latest, String installed) {
  final a = _parse(latest);
  final b = _parse(installed);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a.numbers[i] != b.numbers[i]) return a.numbers[i] > b.numbers[i];
  }
  return b.pre && !a.pre;
}

abstract class AppPlatform {
  Future<String?> installedVersion();
  Future<void> openUrl(String url);
}

class PlatformApp implements AppPlatform {
  static const _channel = MethodChannel('open_timeline/app');

  @override
  Future<String?> installedVersion() async {
    try {
      return await _channel.invokeMethod<String>('version');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('open', url);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

class UpdateChecker {
  UpdateChecker({
    AppPlatform? platform,
    http.Client? client,
    this.endpoint = kLatestReleaseApi,
  }) : platform = platform ?? PlatformApp(),
       _client = client ?? http.Client();

  final AppPlatform platform;
  final http.Client _client;
  final String endpoint;

  Future<UpdateInfo?> check() async {
    try {
      final installed = await platform.installedVersion();
      if (installed == null) return null;
      final response = await _client
          .get(
            Uri.parse(endpoint),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map || json['tag_name'] is! String) return null;
      final tag = json['tag_name'] as String;
      if (!isNewerVersion(tag, installed)) return null;
      final assets = json['assets'];
      final apk = assets is List
          ? assets
                .whereType<Map>()
                .map((a) => a['browser_download_url'])
                .whereType<String>()
                .where((u) => u.endsWith('.apk'))
                .firstOrNull
          : null;
      final page = json['html_url'];
      final url = apk ?? (page is String ? page : null);
      if (url == null) return null;
      return UpdateInfo(version: tag.replaceFirst(RegExp(r'^v'), ''), url: url);
    } on Object {
      return null;
    }
  }
}
