// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_timeline/sync/drive_client.dart';

/// Talks to GoogleDriveClient through a scripted HTTP client (no network).
class Script {
  final requests = <http.Request>[];
  final responses = <http.Response Function(http.Request)>[];

  late final GoogleDriveClient client = GoogleDriveClient(
    drive.DriveApi(
      MockClient((req) async {
        requests.add(req);
        if (responses.isEmpty) {
          throw StateError('unexpected request ${req.method} ${req.url}');
        }
        return responses.removeAt(0)(req);
      }),
    ),
    retryDelays: const [Duration.zero, Duration.zero],
  );

  void json(Object body, {int status = 200}) => responses.add(
    (_) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  );

  void error(int status, String message, {String reason = 'x'}) => json({
    'error': {
      'code': status,
      'message': message,
      'errors': [
        {'reason': reason, 'message': message},
      ],
    },
  }, status: status);
}

/// The base64 content part of a multipart upload body, decoded.
List<int> uploadedBytes(http.Request req) {
  final m = RegExp(r'base64\r\n\r\n([^\r]*)\r\n--').firstMatch(req.body);
  if (m == null) throw StateError('no base64 part in ${req.body}');
  return base64Decode(m.group(1)!);
}

Map<String, Object> file(
  String id,
  String name, {
  String time = '2026-10-16T12:00:00.123Z',
  bool owned = true,
}) => {
  'id': id,
  'name': name,
  'mimeType': 'text/markdown',
  'modifiedTime': time,
  'createdTime': '2026-10-16T11:00:00.000Z',
  'ownedByMe': owned,
  'parents': ['folder1'],
};

void main() {
  late Script s;
  setUp(() => s = Script());

  test('listYearFolders asks for non-trashed folders in the root and keeps only 4-digit names', () async {
    s.json({
      'files': [
        file('1', '2026'),
        file('2', 'notes'),
        file('3', '20260'),
        file('4', '2025'),
      ],
    });
    final folders = await s.client.listYearFolders('ROOT');
    expect(folders.map((f) => f.name), ['2026', '2025']);
    final q = s.requests.single.url.queryParameters['q']!;
    expect(q, contains("'ROOT' in parents"));
    expect(q, contains("mimeType = 'application/vnd.google-apps.folder'"));
    expect(q, contains('trashed = false'));
    expect(s.requests.single.url.queryParameters['supportsAllDrives'], 'true');
    expect(
      s.requests.single.url.queryParameters['includeItemsFromAllDrives'],
      'true',
    );
  });

  test('listFiles queries all folders, applies the watermark, pages and skips trashed', () async {
    s.json({
      'nextPageToken': 'page2',
      'files': [file('a', 'a.md')],
    });
    s.json({
      'files': [
        file('b', 'b.md', owned: false),
        {...file('c', 'c.md'), 'trashed': true},
      ],
    });
    final files = await s.client.listFiles([
      'f1',
      'f2',
    ], modifiedAfter: DateTime.utc(2026, 10, 16, 11, 50));
    expect(files.map((f) => f.name), ['a.md', 'b.md']);
    expect(files[0].ownedByMe, isTrue);
    expect(files[1].ownedByMe, isFalse);
    expect(files[0].modifiedTime, DateTime.utc(2026, 10, 16, 12, 0, 0, 123));
    expect(files[0].parents, ['folder1']);

    expect(s.requests, hasLength(2));
    final q = s.requests[0].url.queryParameters['q']!;
    expect(q, contains("('f1' in parents or 'f2' in parents)"));
    expect(q, contains("modifiedTime > '2026-10-16T11:50:00.000Z'"));
    expect(q, contains('trashed = false'));
    expect(q, contains("mimeType != 'application/vnd.google-apps.folder'"));
    expect(s.requests[0].url.queryParameters.containsKey('pageToken'), isFalse);
    expect(s.requests[1].url.queryParameters['pageToken'], 'page2');
    expect(
      s.requests[0].url.queryParameters['fields'],
      allOf(
        contains('ownedByMe'),
        contains('modifiedTime'),
        contains('parents'),
      ),
    );
  });

  test('listFiles without a watermark lists everything; no folders means no request', () async {
    s.json({'files': []});
    await s.client.listFiles(['f1']);
    expect(
      s.requests.single.url.queryParameters['q'],
      isNot(contains('modifiedTime')),
    );
    expect(await s.client.listFiles([]), isEmpty);
    expect(s.requests, hasLength(1));
  });

  test('findByName escapes quotes and backslashes', () async {
    s.json({'files': []});
    await s.client.findByName(['f1'], r"it's a\b.md");
    expect(
      s.requests.single.url.queryParameters['q'],
      contains(r"name = 'it\'s a\\b.md'"),
    );
  });

  test(
    'getFile maps 404 and trashed files to a not-found DriveException',
    () async {
      s.error(404, 'File not found: x', reason: 'notFound');
      await expectLater(
        s.client.getFile('x'),
        throwsA(
          isA<DriveException>().having((e) => e.notFound, 'notFound', isTrue),
        ),
      );
      s.json({...file('y', 'y.md'), 'trashed': true});
      await expectLater(
        s.client.getFile('y'),
        throwsA(isA<DriveException>().having((e) => e.status, 'status', 404)),
      );
      s.json(file('z', 'z.md'));
      expect((await s.client.getFile('z')).id, 'z');
    },
  );

  test('rate limits are retried, other errors are not', () async {
    s.error(429, 'slow down', reason: 'rateLimitExceeded');
    s.error(403, 'Rate Limit Exceeded', reason: 'userRateLimitExceeded');
    s.json(file('z', 'z.md'));
    expect((await s.client.getFile('z')).id, 'z');
    expect(s.requests, hasLength(3));

    s.requests.clear();
    s.error(
      403,
      'The user does not have sufficient permissions',
      reason: 'forbidden',
    );
    await expectLater(
      s.client.deleteFile('z'),
      throwsA(
        isA<DriveException>().having((e) => e.forbidden, 'forbidden', isTrue),
      ),
    );
    expect(s.requests, hasLength(1));
  });

  test(
    'a create is not retried on a 5xx (it might have happened), a read is',
    () async {
      s.error(500, 'backend error');
      await expectLater(
        s.client.createFile('f1', 'a.md', Uint8List.fromList(utf8.encode('x'))),
        throwsA(isA<DriveException>().having((e) => e.status, 'status', 500)),
      );
      expect(s.requests, hasLength(1));

      s.requests.clear();
      s.error(503, 'unavailable');
      s.json(file('z', 'z.md'));
      expect((await s.client.getFile('z')).id, 'z');
      expect(s.requests, hasLength(2));
    },
  );

  test('download returns the bytes of the file', () async {
    s.responses.add(
      (_) => http.Response.bytes(
        utf8.encode('héllo'),
        200,
        headers: {'content-type': 'application/octet-stream'},
      ),
    );
    final bytes = await s.client.download('abc');
    expect(utf8.decode(bytes), 'héllo');
    expect(s.requests.single.url.queryParameters['alt'], 'media');
    expect(s.requests.single.url.path, endsWith('/files/abc'));
  });

  test('downloadToFile streams into the target file', () async {
    final dir = Directory.systemTemp.createTempSync('open_timeline_dl_');
    addTearDown(() => dir.deleteSync(recursive: true));
    s.responses.add(
      (_) => http.Response.bytes(
        List.generate(5000, (i) => i & 0xff),
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
    );
    final target = File('${dir.path}/sub/x.bin');
    await s.client.downloadToFile('abc', target);
    expect(target.readAsBytesSync(), List.generate(5000, (i) => i & 0xff));
  });

  test(
    'createFile sends name, parent and content in one multipart upload',
    () async {
      s.json(file('new1', 'a.md'));
      final f = await s.client.createFile(
        'folder1',
        'a.md',
        Uint8List.fromList(utf8.encode('# hi')),
      );
      expect(f.id, 'new1');
      final req = s.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, contains('/upload/drive/v3/files'));
      expect(req.headers['content-type'], contains('multipart/related'));
      expect(req.body, contains('"name":"a.md"'));
      expect(req.body, contains('"parents":["folder1"]'));
      expect(utf8.decode(uploadedBytes(req)), '# hi');
      expect(req.body, contains('text/markdown'));
    },
  );

  test(
    'updateFile replaces the content of an existing file; deleteFile deletes',
    () async {
      s.json(file('id9', 'a.md', time: '2026-10-16T12:30:00.000Z'));
      final f = await s.client.updateFile(
        'id9',
        Uint8List.fromList(utf8.encode('new text')),
        mimeType: 'text/markdown',
      );
      expect(f.modifiedTime, DateTime.utc(2026, 10, 16, 12, 30));
      final req = s.requests.single;
      expect(req.method, 'PATCH');
      expect(req.url.path, contains('/upload/drive/v3/files/id9'));
      expect(utf8.decode(uploadedBytes(req)), 'new text');

      s.requests.clear();
      s.responses.add((_) => http.Response('', 204));
      await s.client.deleteFile('id9');
      expect(s.requests.single.method, 'DELETE');
      expect(s.requests.single.url.path, endsWith('/files/id9'));
    },
  );

  test('createFileFromFile streams a file from disk', () async {
    final dir = Directory.systemTemp.createTempSync('open_timeline_up_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final src = File('${dir.path}/p.jpg')
      ..writeAsBytesSync(List.generate(3000, (i) => 65 + i % 20));
    s.json(file('img1', 'p.jpg'));
    final f = await s.client.createFileFromFile('folder1', 'p.jpg', src);
    expect(f.id, 'img1');
    expect(
      uploadedBytes(s.requests.single),
      List.generate(3000, (i) => 65 + i % 20),
    );
    expect(s.requests.single.body, contains('image/jpeg'));
  });

  test('mimeTypeFor knows the media types the app writes', () {
    expect(mimeTypeFor('a.md'), 'text/markdown');
    expect(mimeTypeFor('a.JPG'), 'image/jpeg');
    expect(mimeTypeFor('a.mp4'), 'video/mp4');
    expect(mimeTypeFor('a.xyz'), 'application/octet-stream');
  });
}
