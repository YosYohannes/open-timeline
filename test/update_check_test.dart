import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_timeline/update/update_check.dart';

const endpoint = 'https://example.com/releases/latest';

class FakePlatform implements AppPlatform {
  FakePlatform(this.version);

  final String? version;
  final opened = <String>[];

  @override
  Future<String?> installedVersion() async => version;

  @override
  Future<void> openUrl(String url) async => opened.add(url);
}

http.Client release(Object body, {int status = 200}) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

Map<String, Object> latest(String tag) => {
  'tag_name': tag,
  'html_url': 'https://github.com/x/y/releases/tag/$tag',
  'assets': [
    {'browser_download_url': 'https://example.com/notes.txt'},
    {'browser_download_url': 'https://example.com/open-timeline.apk'},
  ],
};

void main() {
  test('versions compare number by number', () {
    expect(isNewerVersion('v0.2.1', '0.2.0'), isTrue);
    expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
    expect(isNewerVersion('v1.0.0', '0.99.99'), isTrue);
    expect(isNewerVersion('v0.2.0', '0.2.0'), isFalse);
    expect(isNewerVersion('v0.1.9', '0.2.0'), isFalse);
    expect(isNewerVersion('nightly', '0.2.0'), isFalse);
    expect(isNewerVersion('v1.1.0', '1.1.0-beta.1'), isTrue);
    expect(isNewerVersion('v1.1.0-beta.2', '1.1.0-beta.1'), isFalse);
    expect(isNewerVersion('v1.0.0', '1.1.0-beta.1'), isFalse);
    expect(isNewerVersion('v1.1.1', '1.1.0-beta.1'), isTrue);
  });

  test('a newer release points at its APK', () async {
    final checker = UpdateChecker(
      endpoint: endpoint,
      platform: FakePlatform('0.2.0'),
      client: release(latest('v0.3.0')),
    );
    final info = await checker.check();
    expect(info!.version, '0.3.0');
    expect(info.url, 'https://example.com/open-timeline.apk');
  });

  test('without an APK the release page is used', () async {
    final body = latest('v0.3.0')..remove('assets');
    final info = await UpdateChecker(
      endpoint: endpoint,
      platform: FakePlatform('0.2.0'),
      client: release(body),
    ).check();
    expect(info!.url, 'https://github.com/x/y/releases/tag/v0.3.0');
  });

  test('same version, errors and junk all mean no update', () async {
    Future<UpdateInfo?> run(http.Client c, [String? v = '0.2.0']) =>
        UpdateChecker(
          endpoint: endpoint,
          platform: FakePlatform(v),
          client: c,
        ).check();
    expect(await run(release(latest('v0.2.0'))), isNull);
    expect(await run(release({}, status: 404)), isNull);
    expect(await run(release({'tag_name': 5})), isNull);
    expect(await run(release(latest('v9.0.0')), null), isNull);
    expect(
      await run(MockClient((_) async => throw http.ClientException('offline'))),
      isNull,
    );
  });
}
