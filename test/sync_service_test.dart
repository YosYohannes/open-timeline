// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:http/http.dart' as http;
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/drive_client.dart';
import 'package:open_timeline/sync/google_auth.dart';
import 'package:open_timeline/sync/keep_alive.dart';
import 'package:open_timeline/sync/sync_service.dart';

import 'fake_drive.dart';

class FakeAuth extends AuthService {
  FakeAuth({this.isSignedIn = true, this.api = true})
    : super(webClientId: 'test-client-id');

  bool isSignedIn;
  bool api;
  String? fakeError;
  int invalidated = 0;
  int interactiveRequests = 0;

  @override
  bool get signedIn => isSignedIn;

  @override
  String? get error => fakeError;

  @override
  Future<DriveApi?> driveApi({bool interactive = false}) async {
    if (interactive) interactiveRequests++;
    return api ? DriveApi(http.Client()) : null;
  }

  @override
  Future<void> invalidateToken() async => invalidated++;
}

class FakeKeepAlive implements KeepAlive {
  final calls = <String>[];

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  late Directory dir;
  late JournalStore store;
  late FakeDrive fake;
  late FakeAuth auth;
  late SyncService service;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('open_timeline_svc_');
    store = JournalStore(dir);
    await store.load();
    fake = FakeDrive();
    await store.updateSettings(
      AppSettings(me: 'a@x', driveFolderId: fake.rootId),
    );
    auth = FakeAuth();
    service = SyncService(
      store,
      auth,
      clientFactory: (_) => fake.as('a@x'),
      webClientId: 'test-client-id',
    );
  });

  tearDown(() {
    service.dispose();
    store.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'the keep-alive runs for exactly the length of a sync, even when it fails',
    () async {
      final keepAlive = FakeKeepAlive();
      final failing = SyncService(
        store,
        FakeAuth(),
        clientFactory: (_) => fake.as('a@x'),
        webClientId: '',
        keepAlive: keepAlive,
      );
      addTearDown(failing.dispose);
      await failing.sync();
      expect(keepAlive.calls, ['start', 'stop']);
    },
  );

  test('a normal sync fills last, lastAt and tells listeners when it starts and ends', () async {
    await store.save(Entry.create(author: 'a@x').copyWith(text: 'hi'));
    var notifications = 0;
    final runningSeen = <bool>[];
    service.addListener(() {
      notifications++;
      runningSeen.add(service.running);
    });
    expect(service.running, isFalse);
    expect(service.last, isNull);
    expect(service.lastAt, isNull);

    final f = service.sync();
    expect(service.running, isTrue);
    final r = await f;
    expect(r.errors, isEmpty);
    expect(r.uploaded, 1);
    expect(service.running, isFalse);
    expect(service.last, same(r));
    expect(service.lastAt, isNotNull);
    expect(runningSeen, [true, false]);
    expect(notifications, 2);
    expect(auth.interactiveRequests, 1);

    // lastAt survives a restart
    final reopened = JournalStore(dir);
    await reopened.load();
    final again = SyncService(
      reopened,
      auth,
      clientFactory: (_) => fake.as('a@x'),
      webClientId: 'x',
    );
    expect(again.lastAt, isNotNull);
    again.dispose();
    reopened.dispose();
  });

  test('two sync() calls at once share one run', () async {
    final f1 = service.sync();
    final f2 = service.sync();
    expect(identical(f1, f2), isTrue);
    await f1;
    expect(auth.interactiveRequests, 1);
  });

  test('empty Web client ID is reported clearly', () async {
    service = SyncService(
      store,
      auth,
      clientFactory: (_) => fake.as('a@x'),
      webClientId: '',
    );
    final r = await service.sync();
    expect(r.errors.single, contains('kGoogleWebClientId'));
    expect(service.lastAt, isNull);
  });

  test('not signed in, no folder, no Drive permission: one clear error each, never an exception', () async {
    auth.isSignedIn = false;
    expect((await service.sync()).errors.single, contains('Not signed in'));

    auth.isSignedIn = true;
    await store.updateSettings(AppSettings(me: 'a@x'));
    expect((await service.sync()).errors.single, contains('No Drive folder'));

    await store.updateSettings(
      AppSettings(me: 'a@x', driveFolderId: fake.rootId),
    );
    auth.api = false;
    expect((await service.sync()).errors.single, contains('Drive access'));
    auth.fakeError = 'Google sign-in failed: boom';
    expect((await service.sync()).errors.single, contains('boom'));
  });

  test('an exception inside the engine or the client factory ends up in the result', () async {
    service = SyncService(
      store,
      auth,
      clientFactory: (_) => throw StateError('kaboom'),
      webClientId: 'x',
    );
    final r = await service.sync();
    expect(r.errors.single, contains('kaboom'));
    expect(service.running, isFalse);

    service = SyncService(
      store,
      auth,
      clientFactory: (_) => fake.as('a@x'),
      webClientId: 'x',
    );
    fake.before = (op, user) => throw const SocketException('offline');
    final r2 = await service.sync();
    expect(r2.errors, isNotEmpty);
    expect(r2.errors.join(), contains('offline'));
  });

  test(
    'a 401 invalidates the cached token and tells the user to retry',
    () async {
      fake.before = (op, user) =>
          throw DriveException(401, 'Invalid Credentials');
      final r = await service.sync();
      expect(auth.invalidated, 1);
      expect(r.errors.join('\n'), contains('Press Sync again'));
    },
  );

  group('parseDriveFolderId', () {
    test('accepts links and bare ids', () {
      const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz_-0123';
      expect(parseDriveFolderId(id), id);
      expect(parseDriveFolderId('  $id \n'), id);
      expect(
        parseDriveFolderId(
          'https://drive.google.com/drive/folders/$id?usp=sharing',
        ),
        id,
      );
      expect(
        parseDriveFolderId('https://drive.google.com/drive/u/1/folders/$id'),
        id,
      );
      expect(
        parseDriveFolderId('https://drive.google.com/open?id=$id&foo=1'),
        id,
      );
    });

    test('rejects everything else', () {
      expect(parseDriveFolderId(''), isNull);
      expect(parseDriveFolderId('hello world'), isNull);
      expect(parseDriveFolderId('https://example.com/'), isNull);
      expect(parseDriveFolderId('short'), isNull);
    });
  });
}
