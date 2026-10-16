import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/models/entry_format.dart';
import 'package:open_timeline/store/journal_store.dart';

Entry entry({
  String id = '20261016-143205-k3f9',
  String text = 'Hello',
  DateTime? time,
  List<String> tags = const [],
  List<String> media = const [],
  String author = 'a@gmail.com',
  double? lat,
  double? lon,
  String? place,
  bool conflict = false,
}) {
  return Entry(
    id: id,
    author: author,
    time: time ?? DateTime.utc(2026, 10, 16, 12, 32, 5),
    utcOffsetMinutes: 120,
    lat: lat,
    lon: lon,
    place: place,
    text: text,
    tags: tags,
    media: media,
    updated: DateTime.utc(2000),
    conflict: conflict,
  );
}

void main() {
  late Directory dir;
  late JournalStore store;

  Future<JournalStore> open() async {
    final s = JournalStore(dir);
    await s.load();
    return s;
  }

  File postFile(String id) => File('${dir.path}/${id.substring(0, 4)}/$id.md');

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('open_timeline_test_');
    store = await open();
  });

  tearDown(() {
    store.dispose();
    dir.deleteSync(recursive: true);
  });

  group('save and load', () {
    test('a saved post is visible to a new store instance', () async {
      final e = entry(
        text: 'Walked along the beach…\n\nSecond paragraph.',
        tags: ['beach'],
        media: ['20261016-143205-k3f9_x7q2.jpg'],
        lat: 52.3702,
        lon: 4.8952,
        place: 'Scheveningen beach',
      );
      await store.save(e);
      expect(postFile(e.id).existsSync(), isTrue);

      final other = await open();
      final back = other.byId(e.id)!;
      expect(back.text, 'Walked along the beach…\n\nSecond paragraph.');
      expect(back.media, ['20261016-143205-k3f9_x7q2.jpg']);
      expect(back.tags, ['beach']);
      expect(back.lat, 52.3702);
      expect(back.lon, 4.8952);
      expect(back.place, 'Scheveningen beach');
      expect(back.author, 'a@gmail.com');
      expect(back.time, e.time);
      expect(back.utcOffsetMinutes, 120);
      expect(other.entries.map((x) => x.id), [e.id]);
      other.dispose();
    });

    test('save stamps updated (UTC now) and clears conflict', () async {
      final before = DateTime.now().toUtc();
      await store.save(entry(conflict: true));
      final saved = store.byId('20261016-143205-k3f9')!;
      expect(saved.updated.isUtc, isTrue);
      expect(saved.updated.isBefore(before), isFalse);
      expect(saved.conflict, isFalse);
      final reloaded = await open();
      expect(reloaded.byId(saved.id)!.updated, saved.updated);
      expect(reloaded.byId(saved.id)!.conflict, isFalse);
      reloaded.dispose();
    });

    test('memory holds exactly what a reload would produce', () async {
      await store.save(entry(text: '\n\n  keep indent  \n\n  '));
      final inMemory = store.byId('20261016-143205-k3f9')!;
      expect(inMemory.text, '  keep indent');
      final reloaded = await open();
      expect(
        entryToMarkdown(reloaded.byId(inMemory.id)!),
        entryToMarkdown(inMemory),
      );
      reloaded.dispose();
    });

    test('saving again overwrites; no temp files are left behind', () async {
      await store.save(entry(text: 'one'));
      await store.save(entry(text: 'two'));
      expect(store.byId('20261016-143205-k3f9')!.text, 'two');
      expect(store.entries, hasLength(1));
      final leftovers = dir
          .listSync(recursive: true)
          .where((f) => f.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
      expect(
        postFile('20261016-143205-k3f9').readAsStringSync(),
        contains('two'),
      );
    });

    test('concurrent saves are applied in call order', () async {
      final futures = [
        for (var i = 0; i < 20; i++) store.save(entry(text: 'v$i')),
      ];
      await Future.wait(futures);
      expect(store.byId('20261016-143205-k3f9')!.text, 'v19');
      final reloaded = await open();
      expect(reloaded.byId('20261016-143205-k3f9')!.text, 'v19');
      reloaded.dispose();
    });

    test('entries are newest first, load is repeatable', () async {
      await store.save(
        entry(id: '20260101-100000-aaaa', time: DateTime.utc(2026, 1, 1, 10)),
      );
      await store.save(
        entry(id: '20261201-100000-bbbb', time: DateTime.utc(2026, 12, 1, 10)),
      );
      await store.save(
        entry(id: '20250601-100000-cccc', time: DateTime.utc(2025, 6, 1, 10)),
      );
      expect(store.entries.map((e) => e.id), [
        '20261201-100000-bbbb',
        '20260101-100000-aaaa',
        '20250601-100000-cccc',
      ]);
      await store.load();
      await store.load();
      expect(store.entries, hasLength(3));
      expect(Directory('${dir.path}/2025').existsSync(), isTrue);
      expect(Directory('${dir.path}/2026').existsSync(), isTrue);
    });

    test('notifies listeners', () async {
      var n = 0;
      store.addListener(() => n++);
      await store.save(entry());
      expect(n, 1);
      await store.delete('20261016-143205-k3f9');
      expect(n, 2);
    });

    test(
      'a post is stored under the folder of its id, not of its time',
      () async {
        await store.save(
          entry(id: '20261231-235959-zzzz', time: DateTime.utc(2027, 1, 1)),
        );
        expect(
          File('${dir.path}/2026/20261231-235959-zzzz.md').existsSync(),
          isTrue,
        );
      },
    );

    test(
      'an entry with an unsafe id is refused and nothing is written',
      () async {
        await expectLater(
          store.save(entry(id: '2026/../../evil')),
          throwsA(isA<FormatException>()),
        );
        expect(store.entries, isEmpty);
        expect(store.dirtyIds, isEmpty);
      },
    );
  });

  group('dirty', () {
    test('save marks dirty and it persists across reload', () async {
      expect(store.dirtyCount, 0);
      await store.save(entry());
      expect(store.dirtyIds, {'20261016-143205-k3f9'});
      expect(store.dirtyCount, 1);
      final reloaded = await open();
      expect(reloaded.dirtyIds, {'20261016-143205-k3f9'});
      await reloaded.clearDirty('20261016-143205-k3f9');
      expect(reloaded.dirtyCount, 0);
      final again = await open();
      expect(again.dirtyIds, isEmpty);
      reloaded.dispose();
      again.dispose();
    });

    test('dirtyIds is a snapshot', () async {
      await store.save(entry());
      final snapshot = store.dirtyIds;
      await store.clearDirty('20261016-143205-k3f9');
      expect(snapshot, hasLength(1));
      expect(store.dirtyIds, isEmpty);
    });

    test('a corrupt state file does not forget unsynced edits', () async {
      final synced = entry(id: '20261016-100000-aaaa', text: 'synced');
      final edited = entry(
        id: '20261016-110000-bbbb',
        text: 'edited after sync',
      );
      final fresh = entry(id: '20261016-120000-cccc', text: 'never synced');
      for (final e in [synced, edited, fresh]) {
        await store.save(e);
      }
      await store.setBase(store.byId(synced.id)!);
      await store.setBase(store.byId(edited.id)!.copyWith(text: 'old text'));
      File('${dir.path}/.state.json').writeAsStringSync('{ this is not json');

      final reloaded = await open();
      expect(reloaded.dirtyIds, {edited.id, fresh.id});
      expect(File('${dir.path}/.state.json.corrupt').existsSync(), isTrue);
      expect(reloaded.entries, hasLength(3));
      reloaded.dispose();
    });
  });

  group('tags', () {
    test(
      'rename, merge and delete touch every post and mark it dirty',
      () async {
        await store.save(
          entry(id: '20261016-100000-aaaa', tags: ['boulder', 'trip']),
        );
        await store.save(
          entry(id: '20261016-110000-bbbb', tags: ['Climbing', 'boulder']),
        );
        await store.save(entry(id: '20261016-120000-cccc', tags: ['trip']));
        await store.clearDirty('20261016-100000-aaaa');
        await store.clearDirty('20261016-110000-bbbb');
        await store.clearDirty('20261016-120000-cccc');
        expect(store.tagCounts, {'boulder': 2, 'trip': 2, 'Climbing': 1});

        expect(await store.changeTag('boulder', 'Climbing'), 2);
        expect(store.byId('20261016-100000-aaaa')!.tags, ['Climbing', 'trip']);
        expect(store.byId('20261016-110000-bbbb')!.tags, ['Climbing']);
        expect(store.dirtyIds, {
          '20261016-100000-aaaa',
          '20261016-110000-bbbb',
        });

        expect(await store.changeTag('trip', null), 2);
        expect(store.allTags, ['Climbing']);
        expect(store.byId('20261016-120000-cccc')!.tags, isEmpty);
        expect(await store.changeTag('missing', null), 0);
      },
    );

    test('changes survive a reload and keep a conflict flag', () async {
      await store.writeSynced(entry(tags: ['a'], conflict: true), dirty: false);
      await store.changeTag('a', 'b');
      final reloaded = JournalStore(dir);
      await reloaded.load();
      addTearDown(reloaded.dispose);
      final e = reloaded.byId('20261016-143205-k3f9')!;
      expect(e.tags, ['b']);
      expect(e.conflict, isTrue);
    });
  });

  group('delete', () {
    test('turns the post into a tombstone on disk and hides it', () async {
      final e = entry(
        text: 'secret',
        tags: ['t'],
        media: [
          '20261016-143205-k3f9_aaaa.jpg',
          '20261016-143205-k3f9_bbbb.mp4',
        ],
        lat: 1,
        lon: 2,
        place: 'P',
      );
      await store.save(e);
      final photo = store.mediaFile(e, e.media[0])..writeAsBytesSync([1, 2, 3]);
      final video = store.mediaFile(e, e.media[1])..writeAsBytesSync([4, 5]);
      final unrelated = File('${dir.path}/2026/20261016-999999-zzzz_aaaa.jpg')
        ..writeAsBytesSync([9]);
      await store.clearDirty(e.id);

      await store.delete(e.id);

      expect(store.byId(e.id), isNull);
      expect(store.entries, isEmpty);
      expect(photo.existsSync(), isFalse);
      expect(video.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
      expect(store.dirtyIds, {e.id});

      final tomb = store.anyById(e.id)!;
      expect(tomb.deleted, isTrue);
      expect(tomb.text, '');
      expect(tomb.media, isEmpty);
      expect(tomb.tags, ['t']);
      expect(tomb.hasLocation, isFalse);
      expect(tomb.place, isNull);
      expect(store.allEntries.map((x) => x.id), [e.id]);

      final raw = postFile(e.id).readAsStringSync();
      expect(raw, contains('deleted: true'));
      expect(raw, isNot(contains('secret')));
      expect(raw, contains('media: []'));

      final reloaded = await open();
      expect(reloaded.byId(e.id), isNull);
      expect(reloaded.anyById(e.id)!.deleted, isTrue);
      expect(reloaded.allEntries, hasLength(1));
      expect(reloaded.dirtyIds, {e.id});
      reloaded.dispose();
    });

    test('unknown id and double delete are no-ops', () async {
      await store.delete('20261016-000000-nope');
      expect(store.allEntries, isEmpty);
      await store.save(entry());
      await store.delete('20261016-143205-k3f9');
      final firstUpdated = store.anyById('20261016-143205-k3f9')!.updated;
      await store.delete('20261016-143205-k3f9');
      expect(store.anyById('20261016-143205-k3f9')!.updated, firstUpdated);
    });

    test('tags and authors ignore deleted posts', () async {
      await store.save(
        entry(
          id: '20261016-100000-aaaa',
          tags: ['Zebra', 'apple'],
          author: 'b@x.com',
        ),
      );
      await store.save(
        entry(
          id: '20261016-110000-bbbb',
          tags: ['mango', 'apple'],
          author: 'a@x.com',
        ),
      );
      await store.save(
        entry(id: '20261016-120000-cccc', tags: ['gone'], author: 'c@x.com'),
      );
      expect(store.allTags, ['apple', 'gone', 'mango', 'Zebra']);
      expect(store.authors, ['a@x.com', 'b@x.com', 'c@x.com']);
      await store.delete('20261016-120000-cccc');
      expect(store.allTags, ['apple', 'mango', 'Zebra']);
      expect(store.authors, ['a@x.com', 'b@x.com']);
    });

    test('a media name with path parts cannot delete files outside the year folder', () async {
      final outside = File('${dir.path}/precious.txt')
        ..writeAsStringSync('keep');
      final e = entry(media: ['../precious.txt']);
      await store.save(e);
      await store.delete(e.id);
      expect(outside.existsSync(), isTrue);
    });
  });

  group('media', () {
    test('importMedia copies into the year folder under a new name', () async {
      final e = entry(id: '20261016-143205-k3f9');
      final src = File('${dir.path}/picked.JPG')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final name = await store.importMedia(e, src);
      expect(name, matches(RegExp(r'^20261016-143205-k3f9_[a-z0-9]{4}\.jpg$')));
      final copy = File('${dir.path}/2026/$name');
      expect(copy.readAsBytesSync(), [1, 2, 3, 4]);
      expect(store.mediaFile(e, name).path, copy.path);
      expect(src.existsSync(), isTrue);
      expect(
        Directory('${dir.path}/2026')
            .listSync()
            .where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('importMedia names are unique and keep the extension; no extension becomes .bin', () async {
      final e = entry();
      final mp4 = File('${dir.path}/clip.mp4')..writeAsBytesSync([7]);
      final names = {
        for (var i = 0; i < 10; i++) await store.importMedia(e, mp4),
      };
      expect(names, hasLength(10));
      expect(names.every((n) => n.endsWith('.mp4')), isTrue);
      final bare = File('${dir.path}/noext')..writeAsBytesSync([7]);
      expect(await store.importMedia(e, bare), endsWith('.bin'));
    });

    test(
      'importMedia does not modify the entry or mark anything dirty',
      () async {
        final e = entry();
        await store.importMedia(
          e,
          File('${dir.path}/x.png')..writeAsBytesSync([1]),
        );
        expect(store.dirtyIds, isEmpty);
        expect(store.allEntries, isEmpty);
      },
    );

    test('mediaFile is <root>/<year>/<name>', () {
      final e = entry(id: '20261016-143205-k3f9');
      expect(store.mediaFile(e, 'x.jpg').path, '${dir.path}/2026/x.jpg');
      expect(store.mediaFile(e, '../../x.jpg').path, '${dir.path}/2026/x.jpg');
    });
  });

  group('settings', () {
    test('defaults', () {
      expect(store.settings.me, '');
      expect(store.settings.driveFolderId, isNull);
      expect(store.settings.downloadMedia, isTrue);
    });

    test('persist across reload', () async {
      await store.updateSettings(
        AppSettings(
          me: 'me@x.com',
          driveFolderId: 'folder123',
          downloadMedia: false,
        ),
      );
      expect(store.settings.me, 'me@x.com');
      final reloaded = await open();
      expect(reloaded.settings.me, 'me@x.com');
      expect(reloaded.settings.driveFolderId, 'folder123');
      expect(reloaded.settings.downloadMedia, isFalse);
      await reloaded.updateSettings(AppSettings(me: 'other@x.com'));
      final again = await open();
      expect(again.settings.me, 'other@x.com');
      expect(again.settings.driveFolderId, isNull);
      expect(again.settings.downloadMedia, isTrue);
      reloaded.dispose();
      again.dispose();
    });

    test('the update check is on by default and can be turned off', () async {
      expect(store.settings.checkForUpdates, isTrue);
      await store.updateSettings(
        store.settings.copyWith(me: 'me@x.com', checkForUpdates: false),
      );
      await store.updateSettings(store.settings.copyWith(me: 'new@x.com'));
      final reloaded = await open();
      expect(reloaded.settings.checkForUpdates, isFalse);
      reloaded.dispose();
    });

    test('my colour persists and survives copyWith', () async {
      await store.updateSettings(
        AppSettings(me: 'me@x.com', myColor: 0xFF9DBB9A),
      );
      await store.updateSettings(store.settings.copyWith(me: 'new@x.com'));
      final reloaded = await open();
      expect(reloaded.settings.me, 'new@x.com');
      expect(reloaded.settings.myColor, 0xFF9DBB9A);
      reloaded.dispose();
    });

    test('people colours come from each person\'s latest post', () async {
      await store.writeSynced(
        entry(
          id: '20261001-100000-aaaa',
          author: 'p@x.com',
        ).copyWith(color: 0xFF111111, updated: DateTime.utc(2026, 10, 1)),
        dirty: false,
      );
      await store.writeSynced(
        entry(
          id: '20261002-100000-bbbb',
          author: 'P@x.com',
        ).copyWith(color: 0xFF222222, updated: DateTime.utc(2026, 10, 2)),
        dirty: false,
      );
      await store.writeSynced(
        entry(id: '20261003-100000-cccc', author: 'q@x.com'),
        dirty: false,
      );
      expect(store.peopleColors, {'p@x.com': 0xFF222222});
    });

    test('choosing my colour also stamps my latest post for sync', () async {
      await store.updateSettings(AppSettings(me: 'a@gmail.com'));
      await store.writeSynced(entry(), dirty: false);
      await store.setMyColor(0xFF8FAEC9);
      expect(store.settings.myColor, 0xFF8FAEC9);
      expect(store.anyById(entry().id)!.color, 0xFF8FAEC9);
      expect(store.dirtyIds, contains(entry().id));
    });

    test('settings and dirty ids live side by side in .state.json', () async {
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      await store.save(entry());
      final json =
          jsonDecode(File('${dir.path}/.state.json').readAsStringSync()) as Map;
      expect((json['settings'] as Map)['me'], 'me@x.com');
      expect(json['dirty'], ['20261016-143205-k3f9']);
    });
  });

  group('sync API', () {
    test(
      'setBase / base round-trip, base is independent of the live post',
      () async {
        expect(store.base('20261016-143205-k3f9'), isNull);
        final e = entry(
          text: 'as synced',
          tags: ['x'],
          media: ['m.jpg'],
          lat: 1,
          lon: 2,
          place: 'P',
        );
        await store.setBase(e);
        expect(File('${dir.path}/.base/${e.id}.md').existsSync(), isTrue);
        final b = store.base(e.id)!;
        expect(b.text, 'as synced');
        expect(b.tags, ['x']);
        expect(b.media, ['m.jpg']);
        expect(b.lat, 1.0);
        expect(b.updated, e.updated);
        expect(store.anyById(e.id), isNull);
        expect(store.allEntries, isEmpty);
        expect(store.dirtyIds, isEmpty);

        await store.save(e.copyWith(text: 'edited'));
        expect(store.base(e.id)!.text, 'as synced');
        final reloaded = await open();
        expect(reloaded.base(e.id)!.text, 'as synced');
        reloaded.dispose();
      },
    );

    test('an unreadable base counts as no base', () async {
      Directory('${dir.path}/.base').createSync();
      File('${dir.path}/.base/20261016-143205-k3f9.md')
          .writeAsStringSync('garbage');
      expect(store.base('20261016-143205-k3f9'), isNull);
    });

    test('base files are not mistaken for posts on load', () async {
      await store.setBase(entry());
      final reloaded = await open();
      expect(reloaded.allEntries, isEmpty);
      reloaded.dispose();
    });

    test(
      'writeSynced keeps updated and conflict, and sets or clears dirty',
      () async {
        final incoming = entry(
          text: 'from remote',
          conflict: true,
        ).copyWith(updated: DateTime.utc(2026, 5, 5, 5, 5));
        var n = 0;
        store.addListener(() => n++);

        await store.writeSynced(incoming, dirty: false);
        var got = store.byId(incoming.id)!;
        expect(got.updated, DateTime.utc(2026, 5, 5, 5, 5));
        expect(got.conflict, isTrue);
        expect(got.text, 'from remote');
        expect(store.dirtyIds, isEmpty);
        expect(n, 1);

        await store.writeSynced(incoming.copyWith(text: 'merged'), dirty: true);
        got = store.byId(incoming.id)!;
        expect(got.updated, DateTime.utc(2026, 5, 5, 5, 5));
        expect(got.conflict, isTrue);
        expect(store.dirtyIds, {incoming.id});

        final reloaded = await open();
        expect(
          reloaded.byId(incoming.id)!.updated,
          DateTime.utc(2026, 5, 5, 5, 5),
        );
        expect(reloaded.byId(incoming.id)!.conflict, isTrue);
        expect(reloaded.byId(incoming.id)!.text, 'merged');
        expect(reloaded.dirtyIds, {incoming.id});

        await reloaded.writeSynced(
          incoming.copyWith(text: 'merged'),
          dirty: false,
        );
        expect(reloaded.dirtyIds, isEmpty);
        reloaded.dispose();
      },
    );

    test(
      'writeSynced can store a tombstone, which stays hidden but in allEntries',
      () async {
        final tomb = entry(text: '').copyWith(deleted: true);
        await store.writeSynced(tomb, dirty: false);
        expect(store.entries, isEmpty);
        expect(store.anyById(tomb.id)!.deleted, isTrue);
        expect(store.allEntries, hasLength(1));
      },
    );

    test('syncData persists through saveState', () async {
      store.syncData['driveFiles'] = {
        '20261016-143205-k3f9.md': {
          'id': 'abc',
          'modified': '2026-10-16T12:00:00.000Z',
        },
      };
      store.syncData['lastSync'] = 42;
      await store.saveState();
      final reloaded = await open();
      expect(reloaded.syncData['lastSync'], 42);
      expect(
        (reloaded.syncData['driveFiles'] as Map)['20261016-143205-k3f9.md'],
        {'id': 'abc', 'modified': '2026-10-16T12:00:00.000Z'},
      );
      await reloaded.save(entry());
      final again = await open();
      expect(again.syncData['lastSync'], 42);
      reloaded.dispose();
      again.dispose();
    });
  });

  group('robust loading', () {
    test('an unparsable file is skipped, not fatal', () async {
      await store.save(entry(id: '20261016-100000-good', text: 'good'));
      File('${dir.path}/2026/20261016-110000-bad0.md')
          .writeAsStringSync('no header here');
      File('${dir.path}/2026/20261016-120000-bad1.md')
          .writeAsBytesSync([0xff, 0xfe, 0xfd, 0x00]);
      File('${dir.path}/2026/20261016-130000-bad2.md').writeAsStringSync(
        '---\nid: "20261016-130000-other"\ntime: 2026-10-16\n---\nid does not match file name',
      );
      File('${dir.path}/2026/20261016-140000-bad3.md')
          .writeAsStringSync('---\nid: "2026\\u002f..x"\n---\n');
      File('${dir.path}/2026/notes.txt').writeAsStringSync('ignored');
      Directory('${dir.path}/misc').createSync();
      File(
        '${dir.path}/misc/20261016-150000-bad4.md',
      ).writeAsStringSync(entryToMarkdown(entry(id: '20261016-150000-bad4')));

      final reloaded = await open();
      expect(reloaded.entries.map((e) => e.id), ['20261016-100000-good']);
      expect(
        File('${dir.path}/2026/20261016-110000-bad0.md').readAsStringSync(),
        'no header here',
      );
      reloaded.dispose();
    });

    test('a post in the wrong year folder is skipped', () async {
      Directory('${dir.path}/2025').createSync();
      File('${dir.path}/2025/20261016-143205-k3f9.md')
          .writeAsStringSync(entryToMarkdown(entry()));
      final reloaded = await open();
      expect(reloaded.allEntries, isEmpty);
      reloaded.dispose();
    });

    test('a hand-written file dropped into the folder is loaded', () async {
      Directory('${dir.path}/2026').createSync();
      File('${dir.path}/2026/20261016-143205-k3f9.md').writeAsStringSync(
        '---\r\ntime: 2026-10-16T14:32:05+02:00\r\ntags: [a, b]\r\n---\r\n\r\nWritten in Obsidian.\r\n',
      );
      final reloaded = await open();
      final e = reloaded.byId('20261016-143205-k3f9')!;
      expect(e.text, 'Written in Obsidian.');
      expect(e.tags, ['a', 'b']);
      expect(e.utcOffsetMinutes, 120);
      reloaded.dispose();
    });

    test('load creates a missing root folder', () async {
      final nested = Directory('${dir.path}/does/not/exist');
      final s = JournalStore(nested);
      await s.load();
      expect(nested.existsSync(), isTrue);
      expect(s.entries, isEmpty);
      s.dispose();
    });

    test('load picks up changes made on disk by someone else', () async {
      await store.save(entry(text: 'old'));
      postFile('20261016-143205-k3f9')
          .writeAsStringSync(entryToMarkdown(entry(text: 'changed on disk')));
      await store.load();
      expect(store.byId('20261016-143205-k3f9')!.text, 'changed on disk');
    });
  });
}
