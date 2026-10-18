import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/models/entry_format.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/drive_client.dart';
import 'package:open_timeline/sync/sync_engine.dart';

import 'fake_drive.dart';

/// One phone: its own journal folder and its own view of the shared Drive.
class Phone {
  Phone._(this.email, this.dir, this.store, this.drive);

  static Future<Phone> create(
    FakeDrive fake,
    String email, {
    bool downloadMedia = true,
  }) async {
    final dir = Directory.systemTemp.createTempSync('open_timeline_sync_');
    final store = JournalStore(dir);
    await store.load();
    await store.updateSettings(
      AppSettings(
        me: email,
        driveFolderId: fake.rootId,
        downloadMedia: downloadMedia,
      ),
    );
    return Phone._(email, dir, store, fake.as(email));
  }

  final String email;
  final Directory dir;
  final JournalStore store;
  final FakeDriveClient drive;

  Future<SyncResult> sync() => SyncEngine(store, drive).run();

  Future<void> setDownloadMedia(bool value) => store.updateSettings(
    AppSettings(
      me: email,
      driveFolderId: store.settings.driveFolderId,
      downloadMedia: value,
    ),
  );

  Future<void> dispose() async {
    store.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  Entry post(String id) => store.anyById(id)!;

  /// Creates and saves a post, optionally with photos made of [photos] byte lists.
  Future<Entry> newPost(
    String text, {
    List<List<int>> photos = const [],
  }) async {
    var e = Entry.create(author: email);
    final media = <String>[];
    for (final bytes in photos) {
      media.add(await _importPhoto(e, bytes));
    }
    e = e.copyWith(text: text, media: media);
    await store.save(e);
    return store.anyById(e.id)!;
  }

  Future<String> addPhoto(String id, List<int> bytes) async {
    final e = post(id);
    final name = await _importPhoto(e, bytes);
    await store.save(e.copyWith(media: [...e.media, name]));
    return name;
  }

  Future<void> edit(String id, Entry Function(Entry e) change) =>
      store.save(change(post(id)));

  Future<String> _importPhoto(Entry e, List<int> bytes) async {
    final src = File(
      '${dir.path}/pick_${bytes.length}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    src.writeAsBytesSync(bytes);
    final name = await store.importMedia(e, src);
    src.deleteSync();
    return name;
  }

  List<int>? mediaBytes(String id, String name) {
    final f = store.mediaFile(post(id), name);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  bool hasMediaFile(String id, String name) =>
      store.mediaFile(post(id), name).existsSync();
}

Uint8List bytes(int seed, [int length = 2000]) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

String dump(Phone p) {
  final list = p.store.allEntries.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return list.map(entryToMarkdown).join('\n=====\n');
}

/// Every post (tombstones included) is byte-identical on both phones, nothing is
/// left to push, and every media file a post lists exists identically on both
/// (unless [mediaOnA] / [mediaOnB] says that phone does not download).
void expectConverged(Phone a, Phone b, {bool compareMedia = true}) {
  expect(dump(a), dump(b), reason: 'phones disagree on posts');
  expect(a.store.dirtyIds, isEmpty, reason: 'A still has unsynced posts');
  expect(b.store.dirtyIds, isEmpty, reason: 'B still has unsynced posts');
  if (!compareMedia) return;
  for (final e in a.store.entries) {
    for (final m in e.media) {
      expect(a.mediaBytes(e.id, m), isNotNull, reason: 'A misses $m');
      expect(
        b.mediaBytes(e.id, m),
        a.mediaBytes(e.id, m),
        reason: 'B differs on $m',
      );
    }
  }
}

void expectNoErrors(SyncResult r) =>
    expect(r.errors, isEmpty, reason: r.errors.join('\n'));

void main() {
  late FakeDrive fake;
  late Phone a;
  late Phone b;

  setUp(() async {
    fake = FakeDrive(ownerOfRoot: 'a@x');
    a = await Phone.create(fake, 'a@x');
    b = await Phone.create(fake, 'b@x');
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  Entry onDrive(String id) => entryFromMarkdown(fake.textOf('$id.md'));

  group('basic round trip', () {
    test(
      'A creates posts with media, A syncs, B syncs: identical posts and media',
      () async {
        final p1 = await a.newPost('first', photos: [bytes(1), bytes(2)]);
        final p2 = await a.newPost(
          'second',
          photos: [bytes(3, 1500000)],
        ); // big enough to matter
        final p3 = await a.newPost('third, text only');

        final ra = await a.sync();
        expectNoErrors(ra);
        expect(ra.uploaded, 3 + 3);
        expect(ra.downloaded, 0);
        expect(a.store.dirtyIds, isEmpty);

        final rb = await b.sync();
        expectNoErrors(rb);
        expect(rb.downloaded, 3 + 3);
        expect(rb.uploaded, 0);

        expect(b.store.entries.map((e) => e.id).toSet(), {p1.id, p2.id, p3.id});
        expectConverged(a, b);
        for (final e in [p1, p2]) {
          for (final m in e.media) {
            expect(b.mediaBytes(e.id, m), a.mediaBytes(e.id, m));
          }
        }
        // B had nothing to push, so a second round changes nothing.
        expectNoErrors(await a.sync());
        expectConverged(a, b);
      },
    );

    test('Drive layout: README, one year folder, files inside it', () async {
      final p = await a.newPost('hello', photos: [bytes(1)]);
      expectNoErrors(await a.sync());

      expect(fake.yearFolderNames(), ['2026']);
      expect(
        fake.fileNames(),
        unorderedEquals(['README.md', '${p.id}.md', p.media.single]),
      );
      expect(fake.textOf('README.md'), contains('Open Timeline'));
      final yearFolder = (await a.drive.listYearFolders(fake.rootId)).single.id;
      expect(fake.parentOf(fake.idsNamed('${p.id}.md').single), yearFolder);
      expect(fake.parentOf(fake.idsNamed(p.media.single).single), yearFolder);
      expect(fake.parentOf(fake.idsNamed('README.md').single), fake.rootId);
      // The file on Drive is exactly what a local file looks like.
      expect(fake.textOf('${p.id}.md'), entryToMarkdown(a.post(p.id)));
    });

    test('first sync on an empty folder creates README only; the second phone reuses folder and README', () async {
      expectNoErrors(await a.sync());
      expect(fake.fileNames(), ['README.md']);
      expect(fake.yearFolderNames(), isEmpty);

      await b.newPost('from B');
      expectNoErrors(await b.sync());
      await a.newPost('from A');
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expectNoErrors(await a.sync());

      expect(fake.idsNamed('README.md'), hasLength(1));
      expect(fake.yearFolderNames(), ['2026']);
      expectConverged(a, b);
      expect(a.store.entries, hasLength(2));
    });

    test('a second phone that joins later pulls the full history', () async {
      final p = await a.newPost('old', photos: [bytes(9)]);
      expectNoErrors(await a.sync());
      fake.advance(const Duration(days: 40));
      await a.newPost('newer');
      expectNoErrors(await a.sync());

      final c = await Phone.create(fake, 'c@x');
      addTearDown(c.dispose);
      expectNoErrors(await c.sync());
      expect(c.store.entries, hasLength(2));
      expect(c.mediaBytes(p.id, p.media.single), bytes(9));
    });

    test('unchanged second sync uploads and downloads nothing', () async {
      await a.newPost('one', photos: [bytes(1)]);
      await b.newPost('two', photos: [bytes(2)]);
      await a.sync();
      await b.sync();
      await a.sync();
      await b.sync();

      for (final p in [a, b]) {
        fake.resetCalls();
        final r = await p.sync();
        expectNoErrors(r);
        expect([r.uploaded, r.downloaded, r.conflicts], [0, 0, 0]);
        for (final op in [
          'createFile',
          'updateFile',
          'download',
          'downloadToFile',
          'deleteFile',
          'createFolder',
        ]) {
          expect(
            fake.count(op),
            0,
            reason: '$op after an unchanged sync on ${p.email}',
          );
        }
      }
      expectConverged(a, b);
    });

    test('watermark is the newest modifiedTime seen minus 10 minutes, and relisted files are no-ops', () async {
      await a.newPost('x');
      await a.sync();
      await b.sync();
      final newest = fake.now;
      final wm = DateTime.parse(b.store.syncData['watermark'] as String);
      expect(wm.isAfter(newest.subtract(const Duration(minutes: 11))), isTrue);
      expect(wm.isBefore(newest.subtract(const Duration(minutes: 9))), isTrue);

      // Inside the overlap the file is listed again but nothing is downloaded.
      fake.resetCalls();
      final r = await b.sync();
      expect(r.downloaded, 0);
      expect(fake.count('download'), 0);

      // The watermark never moves backwards.
      expect(
        DateTime.parse(b.store.syncData['watermark'] as String).isBefore(wm),
        isFalse,
      );
    });

    test(
      'a file the listing did not show yet is still found next time (overlap)',
      () async {
        final p1 = await a.newPost('one');
        await a.sync();
        final p2 = await a.newPost('two');
        await a.sync();
        final p3 = await a.newPost('three');
        await a.sync();

        // Drive's index lags: B's listing misses P2 although the newer P3 is already there.
        fake.hidden = {...fake.idsNamed('${p2.id}.md')};
        expectNoErrors(await b.sync());
        expect(b.store.anyById(p2.id), isNull);
        expect(b.store.anyById(p1.id), isNotNull);
        expect(b.store.anyById(p3.id), isNotNull);

        fake.hidden = {};
        expectNoErrors(await b.sync());
        expect(b.post(p2.id).text, 'two');
      },
    );
  });

  group('concurrent edits', () {
    for (final aFirst in [true, false]) {
      test(
        'A edits text, B adds a photo offline: both converge (${aFirst ? 'A' : 'B'} syncs first)',
        () async {
          final p = await a.newPost('v1');
          await a.sync();
          await b.sync();

          await a.edit(p.id, (e) => e.copyWith(text: 'v2 by A'));
          final photoName = await b.addPhoto(p.id, bytes(7));

          final first = aFirst ? a : b;
          final second = aFirst ? b : a;
          expectNoErrors(await first.sync());
          expectNoErrors(await second.sync());
          expectNoErrors(await first.sync());
          expectNoErrors(await second.sync());

          expectConverged(a, b);
          for (final ph in [a, b]) {
            final e = ph.post(p.id);
            expect(e.text, 'v2 by A');
            expect(e.media, [photoName]);
            expect(e.conflict, isFalse);
            expect(ph.mediaBytes(p.id, photoName), bytes(7));
          }
          expect(onDrive(p.id).media, [photoName]);
          expect(fake.idsNamed(photoName), hasLength(1));
        },
      );
    }

    test(
      'both edit the text differently: conflict block on both phones, counted',
      () async {
        final p = await a.newPost('v1');
        await a.sync();
        await b.sync();

        await a.edit(p.id, (e) => e.copyWith(text: 'text by A'));
        await b.edit(p.id, (e) => e.copyWith(text: 'text by B'));

        final ra = await a.sync();
        expectNoErrors(ra);
        expect(ra.conflicts, 0);
        final rb = await b.sync();
        expectNoErrors(rb);
        expect(rb.conflicts, 1);
        final ra2 = await a.sync();
        expectNoErrors(ra2);
        expect(ra2.conflicts, 1); // A now shows the conflict block too

        expectConverged(a, b);
        for (final ph in [a, b]) {
          final e = ph.post(p.id);
          expect(e.conflict, isTrue);
          expect(e.text, contains('text by A'));
          expect(e.text, contains('text by B'));
          expect(e.text, contains('conflicting edit by b@x'));
        }

        // Cleaning up the text and saving clears the flag everywhere.
        await b.edit(p.id, (e) => e.copyWith(text: 'resolved'));
        expectNoErrors(await b.sync());
        expectNoErrors(await a.sync());
        expectConverged(a, b);
        expect(a.post(p.id).conflict, isFalse);
        expect(a.post(p.id).text, 'resolved');
      },
    );

    test(
      'partner writes between our pull and our push: nothing is lost',
      () async {
        final p = await a.newPost('v1');
        await a.sync();
        await b.sync();
        await a.edit(p.id, (e) => e.copyWith(text: 'v2 by A'));

        var listed = false;
        var fired = false;
        fake.before = (op, user) async {
          if (op == 'listFiles') listed = true;
          // First metadata check after the pull finished: B writes right now.
          if (listed && !fired && op == 'getFile' && user == 'a@x') {
            fired = true;
            final id = fake.idsNamed('${p.id}.md').single;
            final theirs = onDrive(p.id).copyWith(tags: ['from-b'], title: 'T');
            await fake
                .as('b@x')
                .updateFile(id, utf8.encode(entryToMarkdown(theirs)));
          }
        };
        final ra = await a.sync();
        fake.before = null;
        expectNoErrors(ra);
        expect(fired, isTrue);

        final live = onDrive(p.id);
        expect(live.text, 'v2 by A');
        expect(live.tags, ['from-b']);
        expect(live.title, 'T');

        expectNoErrors(await b.sync());
        expectConverged(a, b);
        expect(b.post(p.id).text, 'v2 by A');
        expect(b.post(p.id).tags, ['from-b']);
      },
    );

    test('partner writes the same text field between pull and push: both versions kept', () async {
      final p = await a.newPost('v1');
      await a.sync();
      await b.sync();
      await a.edit(p.id, (e) => e.copyWith(text: 'A says'));

      var fired = false;
      fake.before = (op, user) async {
        if (!fired &&
            op == 'getFile' &&
            user == 'a@x' &&
            fake.count('listFiles') > 0) {
          fired = true;
          final id = fake.idsNamed('${p.id}.md').single;
          await fake
              .as('b@x')
              .updateFile(
                id,
                utf8.encode(
                  entryToMarkdown(onDrive(p.id).copyWith(text: 'B says')),
                ),
              );
        }
      };
      final ra = await a.sync();
      fake.before = null;
      expectNoErrors(ra);
      expect(onDrive(p.id).text, allOf(contains('A says'), contains('B says')));
      expect(onDrive(p.id).conflict, isTrue);
      await b.sync();
      expectConverged(a, b);
    });

    test('a post edited while it is being uploaded stays dirty and goes out in the next pass', () async {
      final p = await a.newPost('v1');
      await a.sync();
      await a.edit(p.id, (e) => e.copyWith(text: 'v2'));

      var done = false;
      fake.before = (op, user) async {
        if (!done && op == 'updateFile') {
          done = true;
          await a.edit(p.id, (e) => e.copyWith(text: 'v3 typed during sync'));
        }
      };
      final r = await a.sync();
      fake.before = null;
      expectNoErrors(r);
      expect(onDrive(p.id).text, 'v3 typed during sync');
      expect(a.store.dirtyIds, isEmpty);
      expect(r.uploaded, 2);
    });

    test('the md was deleted on Drive while we have unsynced edits: it is created again', () async {
      final p = await a.newPost('v1');
      await a.sync();
      await a.edit(p.id, (e) => e.copyWith(text: 'v2'));
      fake.trashById(fake.idsNamed('${p.id}.md').single);

      expectNoErrors(await a.sync());
      expect(fake.idsNamed('${p.id}.md'), hasLength(1));
      expect(onDrive(p.id).text, 'v2');
      expectNoErrors(await b.sync());
      expect(b.post(p.id).text, 'v2');
    });
  });

  group('deletes', () {
    test('A deletes a post that carries B\'s photo: gone on both, each side removes its own files', () async {
      final p = await a.newPost('keep?', photos: [bytes(1)]);
      final photoA = p.media.single;
      await a.sync();
      await b.sync();
      final photoB = await b.addPhoto(p.id, bytes(2));
      await b.sync();
      await a.sync(); // A downloads B's photo
      expect(a.mediaBytes(p.id, photoB), bytes(2));

      await a.store.delete(p.id);
      fake.resetCalls();
      final ra = await a.sync();
      expectNoErrors(ra);
      // A removed its own photo from Drive, and left B's alone (it may not delete it).
      expect(fake.count('deleteFile'), 1);
      expect(fake.idsNamed(photoA), isEmpty);
      expect(fake.idsNamed(photoB), hasLength(1));
      expect(onDrive(p.id).deleted, isTrue);
      expect(a.store.byId(p.id), isNull);
      expect(a.hasMediaFile(p.id, photoA), isFalse);
      expect(a.hasMediaFile(p.id, photoB), isFalse);

      final rb = await b.sync();
      expectNoErrors(rb);
      expect(b.store.byId(p.id), isNull);
      expect(b.store.anyById(p.id)!.deleted, isTrue);
      expect(b.hasMediaFile(p.id, photoA), isFalse);
      expect(b.hasMediaFile(p.id, photoB), isFalse);
      // B's phone removed its own photo from Drive.
      expect(fake.idsNamed(photoB), isEmpty);
      expect(fake.fileNames(), unorderedEquals(['README.md', '${p.id}.md']));

      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expectConverged(a, b, compareMedia: false);
    });

    test(
      'deleting on the phone that does not own the files works too',
      () async {
        final p = await a.newPost('x', photos: [bytes(1)]);
        await a.sync();
        await b.sync();
        await b.store.delete(p.id);
        final rb = await b.sync();
        expectNoErrors(rb); // A's photo is not B's to delete: no 403 attempted
        expect(fake.idsNamed(p.media.single), hasLength(1));
        final ra = await a.sync();
        expectNoErrors(ra);
        expect(fake.idsNamed(p.media.single), isEmpty);
        expect(a.hasMediaFile(p.id, p.media.single), isFalse);
        expectConverged(a, b, compareMedia: false);
      },
    );

    for (final deleterFirst in [true, false]) {
      test(
        'edit vs delete: the edit wins on both phones (${deleterFirst ? 'delete' : 'edit'} synced first)',
        () async {
          final p = await a.newPost('v1', photos: [bytes(5)]);
          final photo = p.media.single;
          await a.sync();
          await b.sync();

          await a.store.delete(p.id);
          await b.edit(p.id, (e) => e.copyWith(text: 'edited by B'));

          if (deleterFirst) {
            expectNoErrors(await a.sync());
            expectNoErrors(await b.sync());
            expectNoErrors(await a.sync());
          } else {
            expectNoErrors(await b.sync());
            expectNoErrors(await a.sync());
            expectNoErrors(await b.sync());
          }
          expectNoErrors(await a.sync());
          expectNoErrors(await b.sync());

          expectConverged(a, b);
          for (final ph in [a, b]) {
            final e = ph.post(p.id);
            expect(e.deleted, isFalse);
            expect(e.text, 'edited by B');
            expect(e.media, [photo]);
            expect(
              ph.mediaBytes(p.id, photo),
              bytes(5),
              reason: '${ph.email} lost the photo',
            );
          }
          expect(onDrive(p.id).deleted, isFalse);
          expect(fake.idsNamed(photo), hasLength(1));
        },
      );
    }

    test('only media named after the post is deleted with it; a hand-placed shared file stays', () async {
      final p = await a.newPost('x', photos: [bytes(1)]);
      File('${a.dir.path}/${p.year}/cover.jpg').writeAsBytesSync(bytes(9));
      await a.edit(p.id, (e) => e.copyWith(media: [...e.media, 'cover.jpg']));
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expect(b.mediaBytes(p.id, 'cover.jpg'), bytes(9));

      await a.store.delete(p.id);
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expect(fake.idsNamed(p.media.first), isEmpty);
      expect(fake.idsNamed('cover.jpg'), hasLength(1));
      expect(File('${b.dir.path}/${p.year}/cover.jpg').existsSync(), isTrue);
      expectConverged(a, b, compareMedia: false);
    });

    test('a tombstone for a post this phone never saw is accepted', () async {
      final p = await a.newPost('short-lived');
      await a.store.delete(p.id);
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expect(b.store.byId(p.id), isNull);
      expect(b.store.anyById(p.id)!.deleted, isTrue);
      expectConverged(a, b);
    });
  });

  group('media download setting', () {
    test('downloadMedia = false: posts sync, media files stay on Drive; switching it on fetches them', () async {
      final p = await a.newPost('with photos', photos: [bytes(1), bytes(2)]);
      await a.sync();
      await b.setDownloadMedia(false);

      fake.resetCalls();
      final r = await b.sync();
      expectNoErrors(r);
      expect(fake.count('downloadToFile'), 0);
      expect(r.downloaded, 1); // the post only
      expect(b.post(p.id).media, p.media);
      for (final m in p.media) {
        expect(b.hasMediaFile(p.id, m), isFalse);
      }

      // B edits the text without having the photos: the photo list survives.
      await b.edit(p.id, (e) => e.copyWith(text: 'B was here'));
      expectNoErrors(await b.sync());
      expect(onDrive(p.id).media, p.media);
      expect(onDrive(p.id).text, 'B was here');
      expectNoErrors(await a.sync());
      expect(a.post(p.id).media, p.media);
      expect(a.mediaBytes(p.id, p.media.first), bytes(1));

      await b.setDownloadMedia(true);
      final r2 = await b.sync();
      expectNoErrors(r2);
      expect(r2.downloaded, 2);
      expectConverged(a, b);
    });

    test(
      'a media file the listing does not show is still found by name',
      () async {
        final p = await a.newPost('p', photos: [bytes(4)]);
        await a.sync();
        fake.hidden = {fake.idsNamed(p.media.single).single};
        fake.resetCalls();
        expectNoErrors(await b.sync());
        expect(fake.count('findByName'), greaterThan(0));
        expect(b.mediaBytes(p.id, p.media.single), bytes(4));
      },
    );
  });

  group('interruptions', () {
    // 3 photos + 2 posts = 5 createFile calls (README is made beforehand); lose each one in turn.
    for (var k = 1; k <= 5; k++) {
      test(
        'connection fails before the ${k}th upload: rerun completes, nothing duplicated',
        () async {
          await a.sync(); // README
          fake.resetCalls();
          final p1 = await a.newPost('one', photos: [bytes(1), bytes(2)]);
          final p2 = await a.newPost('two', photos: [bytes(3)]);

          fake.before = (op, user) {
            if (op == 'createFile' && fake.count('createFile') == k) {
              throw const SocketException('connection lost');
            }
          };
          final r1 = await a.sync();
          fake.before = null;
          expect(r1.errors, isNotEmpty);

          final r2 = await a.sync();
          expectNoErrors(r2);
          expect(a.store.dirtyIds, isEmpty);

          final names = fake.fileNames();
          expect(
            names.toSet().length,
            names.length,
            reason: 'duplicates on Drive: $names',
          );
          expect(
            names,
            unorderedEquals([
              'README.md',
              '${p1.id}.md',
              '${p2.id}.md',
              ...p1.media,
              ...p2.media,
            ]),
          );
          expect(fake.yearFolderNames(), ['2026']);

          expectNoErrors(await b.sync());
          expectConverged(a, b);
        },
      );

      test(
        'upload #$k reached Drive but the answer was lost: rerun adopts it, nothing duplicated',
        () async {
          await a.sync();
          fake.resetCalls();
          final p1 = await a.newPost('one', photos: [bytes(1), bytes(2)]);
          final p2 = await a.newPost('two', photos: [bytes(3)]);

          fake.after = (op, user) {
            if (op == 'createFile' && fake.count('createFile') == k) {
              throw const SocketException('answer lost');
            }
          };
          final r1 = await a.sync();
          fake.after = null;
          expect(r1.errors, isNotEmpty);

          final r2 = await a.sync();
          expectNoErrors(r2);
          expect(a.store.dirtyIds, isEmpty);

          final names = fake.fileNames();
          expect(
            names.toSet().length,
            names.length,
            reason: 'duplicates on Drive: $names',
          );
          expect(
            names,
            unorderedEquals([
              'README.md',
              '${p1.id}.md',
              '${p2.id}.md',
              ...p1.media,
              ...p2.media,
            ]),
          );
          expect(fake.yearFolderNames(), ['2026']);

          expectNoErrors(await b.sync());
          expectConverged(a, b);
          expectNoErrors(await a.sync());
          expectConverged(a, b);
        },
      );
    }

    for (final lostUpload in [1, 2]) {
      test(
        'upload #$lostUpload lost its answer and the listing lags: found by name, not uploaded twice',
        () async {
          await a.sync();
          fake.resetCalls();
          final p = await a.newPost(
            'one',
            photos: [bytes(1)],
          ); // upload 1 = photo, 2 = post
          fake.after = (op, user) {
            if (op == 'createFile' && fake.count('createFile') == lostUpload) {
              throw const SocketException('lost');
            }
          };
          expect((await a.sync()).errors, isNotEmpty);
          fake.after = null;

          // Drive's index does not list the files yet, so only a lookup by name can find them.
          fake.hidden = {
            ...fake.idsNamed('${p.id}.md'),
            ...fake.idsNamed(p.media.single),
          };
          final r = await a.sync();
          expectNoErrors(r);
          expect(
            fake.count('createFile'),
            2,
            reason: 'nothing may be uploaded twice',
          );
          expect(fake.idsNamed(p.media.single), hasLength(1));
          expect(fake.idsNamed('${p.id}.md'), hasLength(1));
          expect(a.store.dirtyIds, isEmpty);

          fake.hidden = {};
          expectNoErrors(await b.sync());
          expectConverged(a, b);
        },
      );
    }

    test('a failed photo upload keeps the post off Drive (no dangling photo links), then recovers', () async {
      await a.sync();
      fake.resetCalls();
      final p = await a.newPost('with photo', photos: [bytes(1)]);
      fake.before = (op, user) {
        if (op == 'createFile') throw DriveException(500, 'backend error');
      };
      final r = await a.sync();
      fake.before = null;
      expect(r.errors, isNotEmpty);
      expect(fake.idsNamed('${p.id}.md'), isEmpty);
      expect(a.store.dirtyIds, contains(p.id));
      expect(a.post(p.id).text, 'with photo'); // local data untouched

      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expectConverged(a, b);
    });

    test('a post that could not be read is retried even when newer files move the watermark past it', () async {
      final p1 = await a.newPost('one');
      await a.sync();
      fake.advance(const Duration(hours: 2));
      final p2 = await a.newPost('two');
      await a.sync();

      fake.resetCalls();
      fake.before = (op, user) {
        if (op == 'download' && user == 'b@x' && fake.count('download') == 1) {
          throw const SocketException('flaky');
        }
      };
      final r1 = await b.sync();
      fake.before = null;
      expect(r1.errors, hasLength(1));
      expect(b.store.anyById(p1.id), isNull);
      expect(b.post(p2.id).text, 'two');

      expectNoErrors(await b.sync());
      expect(b.post(p1.id).text, 'one');
    });

    test('files, state and posts survive a restart of the app in the middle of the story', () async {
      final p = await a.newPost('v1', photos: [bytes(8)]);
      await a.sync();
      await b.sync();

      // B restarts: new store object over the same folder.
      final reopened = JournalStore(b.dir);
      await reopened.load();
      final b2 = Phone._('b@x', b.dir, reopened, fake.as('b@x'));
      fake.resetCalls();
      final r = await b2.sync();
      expectNoErrors(r);
      expect(fake.count('download'), 0); // records survived
      expect(b2.post(p.id).text, 'v1');
      await b2.edit(p.id, (e) => e.copyWith(text: 'v2'));
      expectNoErrors(await b2.sync());
      expectNoErrors(await a.sync());
      expect(a.post(p.id).text, 'v2');
      reopened.dispose();
    });
  });

  group('folders and odd files', () {
    test('two year folders with the same name are both read; new files go to the oldest', () async {
      await b.newPost('from B');
      await b.sync();
      final oldest = (await b.drive.listYearFolders(fake.rootId)).single.id;
      // A's phone created its own "2026" at the same time.
      final twin = await a.drive.createFolder(fake.rootId, '2026');
      final inTwin = Entry.create(
        author: 'a@x',
        now: DateTime(2026, 10, 15, 8),
      ).copyWith(text: 'in the twin');
      await a.drive.createFile(
        twin.id,
        inTwin.fileName,
        utf8.encode(entryToMarkdown(inTwin)),
      );

      final mine = await a.newPost('from A', photos: [bytes(1)]);
      final ra = await a.sync();
      expectNoErrors(ra);
      expect(a.store.anyById(inTwin.id)?.text, 'in the twin');
      expect(a.store.entries, hasLength(3));
      expect(fake.parentOf(fake.idsNamed('${mine.id}.md').single), oldest);
      expect(fake.parentOf(fake.idsNamed(mine.media.single).single), oldest);

      expectNoErrors(await b.sync());
      expect(b.store.entries, hasLength(3));
      expectConverged(a, b);
    });

    test('an unreadable post file is skipped and reported once; fixing it brings it in', () async {
      await a.newPost('good');
      await a.sync();
      final folder = (await a.drive.listYearFolders(fake.rootId)).single.id;
      final broken = await b.drive.createFile(
        folder,
        '20260101-000000-zzzz.md',
        utf8.encode('no header here'),
      );

      final r1 = await a.sync();
      expect(r1.errors, hasLength(1));
      expect(r1.errors.single, contains('20260101-000000-zzzz.md'));
      expect(a.store.entries, hasLength(1));

      final r2 = await a.sync();
      expectNoErrors(r2); // known bad version: not reported again

      final fixed = Entry(
        id: '20260101-000000-zzzz',
        author: 'b@x',
        time: DateTime.utc(2026, 1, 1),
        utcOffsetMinutes: 0,
        text: 'repaired',
        updated: DateTime.utc(2026, 1, 1),
      );
      fake.writeAs('b@x', broken.id, utf8.encode(entryToMarkdown(fixed)));
      expectNoErrors(await a.sync());
      expect(a.post('20260101-000000-zzzz').text, 'repaired');
    });

    test(
      'a post file whose id does not match its name is reported, not imported',
      () async {
        await a.sync();
        await a.newPost('x');
        await a.sync();
        final folder = (await a.drive.listYearFolders(fake.rootId)).single.id;
        final e = Entry.create(author: 'b@x');
        await b.drive.createFile(
          folder,
          '20260202-020202-nope.md',
          utf8.encode(entryToMarkdown(e)),
        );
        final r = await a.sync();
        expect(r.errors.single, contains('does not match'));
        expect(a.store.anyById(e.id), isNull);
      },
    );

    test('a wrong or inaccessible folder id gives one clear error and touches nothing', () async {
      await a.newPost('x');
      await a.store.updateSettings(
        AppSettings(me: 'a@x', driveFolderId: 'does-not-exist'),
      );
      final r = await a.sync();
      expect(r.errors, hasLength(1));
      expect(r.errors.single, contains('not found'));
      expect(a.store.dirtyIds, isNotEmpty);

      await a.store.updateSettings(AppSettings(me: 'a@x'));
      final r2 = await a.sync();
      expect(r2.errors.single, contains('No Drive folder'));
    });

    test(
      'lost sync bookkeeping: nothing is duplicated and nothing is lost',
      () async {
        final p = await a.newPost('v1', photos: [bytes(1)]);
        await a.sync();
        await b.sync();
        await b.edit(p.id, (e) => e.copyWith(text: 'v2 by B'));
        await b.sync();

        // A's phone forgets everything about Drive (state file reset), then edits.
        a.store.syncData.clear();
        await a.store.saveState();
        await a.edit(p.id, (e) => e.copyWith(title: 'T'));

        fake.resetCalls();
        final r = await a.sync();
        expectNoErrors(r);
        expect(
          fake.count('createFile'),
          0,
          reason: 'must adopt existing files, not duplicate them',
        );
        expectNoErrors(await b.sync());
        expectNoErrors(await a.sync());

        expectConverged(a, b);
        expect(a.post(p.id).text, 'v2 by B');
        expect(a.post(p.id).title, 'T');
        final names = fake.fileNames();
        expect(names.toSet().length, names.length);
      },
    );

    test('a local post Drive has never seen is uploaded even if it was not marked dirty', () async {
      final p = await a.newPost('hand placed');
      await a.store.clearDirty(p.id);
      expectNoErrors(await a.sync());
      expect(onDrive(p.id).text, 'hand placed');
    });
  });

  group('after an app update', () {
    test('a stamp an older app read as a post becomes a stamp again', () async {
      final stamp = Entry.create(author: 'a@x', kind: kindStamp).copyWith(
        series: 'JR West eki',
        country: 'JP',
        size: sizeLarge,
        blend: true,
        text: 'Osaka',
      );
      await a.store.save(stamp);
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());
      expect(b.post(stamp.id).isStamp, isTrue);

      // What an older app leaves behind: the same file, minus the new fields,
      // recorded as already synced and without a schema in the sync state.
      final plain = Entry(
        id: stamp.id,
        author: stamp.author,
        time: stamp.time,
        utcOffsetMinutes: stamp.utcOffsetMinutes,
        text: stamp.text,
        updated: stamp.updated,
      );
      await b.store.writeSynced(plain, dirty: false);
      await b.store.setBase(plain);
      b.store.syncData.remove('schema');
      await b.store.saveState();
      expect(b.post(stamp.id).isStamp, isFalse);

      expectNoErrors(await b.sync());
      final back = b.post(stamp.id);
      expect(back.isStamp, isTrue);
      expect(back.series, 'JR West eki');
      expect(back.country, 'JP');
      expect(back.size, sizeLarge);
      expect(back.blend, isTrue);
      expect(onDrive(stamp.id).isStamp, isTrue);
      expect(b.store.dirtyIds, isEmpty);
    });

    test('unsynced edits survive the refresh', () async {
      final stamp = Entry.create(
        author: 'a@x',
        kind: kindStamp,
      ).copyWith(series: 'Kintetsu', country: 'JP', text: 'one');
      await a.store.save(stamp);
      expectNoErrors(await a.sync());
      expectNoErrors(await b.sync());

      final plain = Entry(
        id: stamp.id,
        author: stamp.author,
        time: stamp.time,
        utcOffsetMinutes: stamp.utcOffsetMinutes,
        text: stamp.text,
        updated: stamp.updated,
      );
      await b.store.writeSynced(plain, dirty: false);
      await b.store.setBase(plain);
      b.store.syncData.remove('schema');
      await b.edit(stamp.id, (e) => e.copyWith(text: 'two'));

      expectNoErrors(await b.sync());
      final back = b.post(stamp.id);
      expect(back.isStamp, isTrue);
      expect(back.series, 'Kintetsu');
      expect(back.text, 'two');
      expect(onDrive(stamp.id).text, 'two');
      expect(onDrive(stamp.id).isStamp, isTrue);
    });
  });
}
