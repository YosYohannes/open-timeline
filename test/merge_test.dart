import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/sync/merge.dart';

final _now = DateTime(
  2026,
  10,
  16,
  14,
  30,
); // local wall clock -> "16 Oct 14:30"
const _stamp = '16 Oct 14:30';

Entry make({
  String text = 'base text',
  List<String> tags = const ['beach'],
  List<String> media = const ['a.jpg'],
  double? lat = 52.0,
  double? lon = 4.0,
  String? place = 'Beach',
  String author = 'a@x.com',
  String title = '',
  int? color,
  int offset = 120,
  DateTime? time,
  bool deleted = false,
  bool conflict = false,
}) {
  return Entry(
    id: '20261016-143205-k3f9',
    author: author,
    time: time ?? DateTime.utc(2026, 10, 16, 12, 32, 5),
    utcOffsetMinutes: offset,
    lat: lat,
    lon: lon,
    place: place,
    text: text,
    tags: tags,
    media: media,
    title: title,
    color: color,
    updated: DateTime.utc(2026, 10, 16, 12, 40),
    deleted: deleted,
    conflict: conflict,
  );
}

Entry merge(Entry? base, Entry local, Entry remote) => mergeEntry(
  base: base,
  local: local,
  remote: remote,
  localUser: 'me@x.com',
  now: _now,
);

void main() {
  final base = make();

  group('text', () {
    test('only text on one side, only a photo on the other: both survive', () {
      final local = make(text: 'edited locally');
      final remote = make(media: ['a.jpg', 'b.jpg']);
      final r1 = merge(base, local, remote);
      expect(r1.text, 'edited locally');
      expect(r1.media, ['a.jpg', 'b.jpg']);
      expect(r1.conflict, isFalse);

      // Swapped roles: text edited on the remote, photo added locally.
      final r2 = merge(base, remote, local);
      expect(r2.text, 'edited locally');
      expect(r2.media, ['a.jpg', 'b.jpg']);
      expect(r2.conflict, isFalse);
    });

    test('both edited the text differently: both kept, conflict flagged', () {
      final r = merge(
        base,
        make(text: 'local words'),
        make(text: 'remote words'),
      );
      expect(
        r.text,
        'remote words\n\n──── conflicting edit by me@x.com · $_stamp ────\nlocal words',
      );
      expect(r.conflict, isTrue);
    });

    test('conflict stamp is d MMM HH:mm with zero-padded time only', () {
      final r = mergeEntry(
        base: base,
        local: make(text: 'L'),
        remote: make(text: 'R'),
        localUser: 'u',
        now: DateTime(2026, 3, 5, 9, 5),
      );
      expect(r.text, 'R\n\n──── conflicting edit by u · 5 Mar 09:05 ────\nL');
    });

    test('both changed to the same text: no conflict', () {
      final r = merge(base, make(text: 'same'), make(text: 'same'));
      expect(r.text, 'same');
      expect(r.conflict, isFalse);
    });

    test('neither changed the text', () {
      final r = merge(base, make(title: 'T'), make(tags: ['beach', 'x']));
      expect(r.text, 'base text');
      expect(r.conflict, isFalse);
    });

    test('only remote changed the text', () {
      final r = merge(base, make(title: 'T'), make(text: 'remote only'));
      expect(r.text, 'remote only');
      expect(r.title, 'T');
    });

    test('conflict flag is carried from the side the text came from', () {
      final r1 = merge(base, make(text: 'L', conflict: true), make(title: 'T'));
      expect(r1.conflict, isTrue);
      final r2 = merge(base, make(title: 'T', conflict: true), make(text: 'R'));
      expect(
        r2.conflict,
        isFalse,
      ); // text came from remote, whose flag is false
      final r3 = merge(base, make(title: 'T'), make(text: 'R', conflict: true));
      expect(r3.conflict, isTrue);
      final r4 = merge(
        base,
        make(text: 'L', conflict: true),
        make(text: 'R', conflict: true),
      );
      expect(r4.conflict, isTrue); // new conflict
      final r5 = merge(base, make(text: 'L', conflict: true), make(text: 'L'));
      expect(r5.conflict, isTrue); // same text, carried
      final r6 = merge(
        make(conflict: true),
        make(title: 'T'),
        make(tags: ['beach', 'x'], conflict: true),
      );
      expect(r6.conflict, isTrue); // text unchanged on both, flag kept
    });
  });

  group('tags and media', () {
    test(
      'tags added on both sides: union, remote order then local additions',
      () {
        final r = merge(
          base,
          make(tags: ['beach', 'local1', 'both']),
          make(tags: ['remote1', 'beach', 'both']),
        );
        expect(r.tags, ['remote1', 'beach', 'both', 'local1']);
      },
    );

    test(
      'tag removed on one side stays removed, additions on the other survive',
      () {
        final withTwo = make(tags: ['beach', 'family']);
        final r1 = merge(
          withTwo,
          make(tags: ['beach']),
          make(tags: ['beach', 'family', 'new']),
        );
        expect(r1.tags, ['beach', 'new']);
        final r2 = merge(
          withTwo,
          make(tags: ['beach', 'family', 'new']),
          make(tags: ['beach']),
        );
        expect(r2.tags, ['beach', 'new']);
      },
    );

    test('tag removed on both sides, tag added with the same name on both', () {
      final withTwo = make(tags: ['beach', 'family']);
      final r = merge(withTwo, make(tags: ['x']), make(tags: ['x', 'y']));
      expect(r.tags, ['x', 'y']);
    });

    test('duplicates collapse', () {
      final r = merge(
        base,
        make(tags: ['beach', 'a', 'a']),
        make(tags: ['beach', 'a']),
      );
      expect(r.tags, ['beach', 'a']);
    });

    test('photos added on both sides: both kept', () {
      final r = merge(
        base,
        make(media: ['a.jpg', 'l.jpg']),
        make(media: ['a.jpg', 'r.mp4']),
      );
      expect(r.media, ['a.jpg', 'r.mp4', 'l.jpg']);
    });

    test('photo removed on one side while another is added on the other', () {
      final r = merge(base, make(media: []), make(media: ['a.jpg', 'r.jpg']));
      expect(r.media, ['r.jpg']);
    });
  });

  group('scalar groups', () {
    test('location changed on both sides: remote wins (as a unit)', () {
      final r = merge(
        base,
        make(lat: 1, lon: 2, place: 'Local place'),
        make(lat: 3, lon: 4, place: 'Remote place'),
      );
      expect([r.lat, r.lon, r.place], [3.0, 4.0, 'Remote place']);
    });

    test('location changed on one side only: that side', () {
      final local = make(lat: 1, lon: 2, place: 'Local place');
      final r1 = merge(base, local, make(text: 'x'));
      expect([r1.lat, r1.lon, r1.place], [1.0, 2.0, 'Local place']);
      final r2 = merge(base, make(text: 'x'), local);
      expect([r2.lat, r2.lon, r2.place], [1.0, 2.0, 'Local place']);
    });

    test('place name changed locally, coordinates changed remotely: remote group wins whole', () {
      final r = merge(base, make(place: 'Renamed'), make(lat: 9, lon: 9));
      expect([r.lat, r.lon, r.place], [9.0, 9.0, 'Beach']);
    });

    test('location removed on one side counts as a change', () {
      final r = merge(
        base,
        make(lat: null, lon: null, place: null),
        make(text: 'x'),
      );
      expect(r.hasLocation, isFalse);
      expect(r.place, isNull);
    });

    test('time and offset travel together', () {
      final local = make(time: DateTime.utc(2026, 10, 15, 8), offset: -180);
      final r1 = merge(base, local, make(text: 'x'));
      expect(r1.time, DateTime.utc(2026, 10, 15, 8));
      expect(r1.utcOffsetMinutes, -180);
      final r2 = merge(
        base,
        local,
        make(time: DateTime.utc(2026, 10, 14, 8), offset: 330),
      );
      expect(r2.time, DateTime.utc(2026, 10, 14, 8));
      expect(r2.utcOffsetMinutes, 330);
      // Same instant, different offset is still a change of the group.
      final r3 = merge(base, make(offset: 60), make(text: 'x'));
      expect(r3.utcOffsetMinutes, 60);
    });

    test('color: one side wins, both changed -> remote', () {
      expect(
        merge(base, make(color: 0xFF112233), make(text: 'x')).color,
        0xFF112233,
      );
      expect(
        merge(base, make(text: 'x'), make(color: 0xFF445566)).color,
        0xFF445566,
      );
      expect(
        merge(base, make(color: 0xFF112233), make(color: 0xFF445566)).color,
        0xFF445566,
      );
    });

    test('author and title', () {
      final r1 = merge(
        base,
        make(author: 'b@x.com', title: 'T'),
        make(text: 'x'),
      );
      expect(r1.author, 'b@x.com');
      expect(r1.title, 'T');
      final r2 = merge(
        base,
        make(author: 'b@x.com', title: 'T'),
        make(author: 'c@x.com', title: ''),
      );
      expect(r2.author, 'c@x.com');
      expect(r2.title, 'T'); // only local changed it -> local wins
      final r3 = merge(
        make(title: 'T'),
        make(title: ''),
        make(title: 'T', text: 'x'),
      );
      expect(r3.title, '');
      final r4 = merge(make(title: 'T'), make(title: ''), make(title: ''));
      expect(r4.title, '');
    });
  });

  group('delete vs edit', () {
    final tombstone = make(
      text: '',
      media: [],
      deleted: true,
      lat: null,
      lon: null,
      place: null,
    );

    test('local deleted, remote edited: the edit wins', () {
      final remote = make(text: 'edited remotely');
      final r = merge(base, tombstone, remote);
      expect(r.deleted, isFalse);
      expect(r.text, 'edited remotely');
      expect(r.media, ['a.jpg']);
      expect(r.place, 'Beach');
    });

    test('remote deleted, local edited: the edit wins', () {
      final local = make(text: 'edited locally', media: ['a.jpg', 'new.jpg']);
      final r = merge(base, local, tombstone);
      expect(r.deleted, isFalse);
      expect(r.text, 'edited locally');
      expect(r.media, ['a.jpg', 'new.jpg']);
    });

    test('a tiny edit (star only) also beats a delete', () {
      expect(merge(base, tombstone, make(title: 'T')).deleted, isFalse);
      expect(
        merge(base, make(tags: ['beach', 'x']), tombstone).deleted,
        isFalse,
      );
    });

    test('delete vs unchanged: tombstone, both orders', () {
      final unchanged = make();
      final r1 = merge(base, tombstone, unchanged);
      expect(r1.deleted, isTrue);
      expect(r1.text, '');
      expect(r1.media, isEmpty);
      final r2 = merge(base, unchanged, tombstone);
      expect(r2.deleted, isTrue);
      expect(r2.text, '');
    });

    test('both deleted: tombstone', () {
      final r = merge(base, tombstone, tombstone);
      expect(r.deleted, isTrue);
      expect(r.text, '');
      expect(r.conflict, isFalse);
    });
  });

  group('bookkeeping', () {
    test('id kept, updated = now in UTC', () {
      final r = merge(base, make(text: 'L'), make(text: 'R'));
      expect(r.id, base.id);
      expect(r.updated, _now.toUtc());
      expect(r.updated.isUtc, isTrue);
    });

    test('now defaults to the current time', () {
      final before = DateTime.now().toUtc();
      final r = mergeEntry(
        base: base,
        local: make(text: 'L'),
        remote: make(text: 'R'),
        localUser: 'u',
      );
      expect(r.updated.isBefore(before), isFalse);
      expect(r.updated.isUtc, isTrue);
      expect(r.text, contains('conflicting edit by u ·'));
    });

    test('inputs are not mutated', () {
      final local = make(tags: ['x', 'y']);
      final remote = make(tags: ['z']);
      merge(base, local, remote);
      expect(local.tags, ['x', 'y']);
      expect(remote.tags, ['z']);
    });
  });

  group('base == null', () {
    test('everything differing is changed on both sides', () {
      final local = make(
        text: 'local text',
        tags: ['l', 'both'],
        media: ['l.jpg'],
        lat: 1,
        lon: 1,
        place: 'L',
        author: 'l@x.com',
        title: 'T',
        offset: 60,
        time: DateTime.utc(2026, 1, 1),
      );
      final remote = make(
        text: 'remote text',
        tags: ['both', 'r'],
        media: ['r.jpg'],
        lat: 2,
        lon: 2,
        place: 'R',
        author: 'r@x.com',
        title: '',
        offset: 330,
        time: DateTime.utc(2026, 2, 2),
      );
      final r = merge(null, local, remote);
      expect(
        r.text,
        'remote text\n\n──── conflicting edit by me@x.com · $_stamp ────\nlocal text',
      );
      expect(r.conflict, isTrue);
      expect(r.tags, ['both', 'r', 'l']);
      expect(r.media, ['r.jpg', 'l.jpg']);
      expect([r.lat, r.lon, r.place], [2.0, 2.0, 'R']);
      expect(r.author, 'r@x.com');
      expect(r.title, '');
      expect(r.time, DateTime.utc(2026, 2, 2));
      expect(r.utcOffsetMinutes, 330);
    });

    test('identical texts: no conflict', () {
      final r = merge(
        null,
        make(text: 'same'),
        make(text: 'same', tags: ['x']),
      );
      expect(r.text, 'same');
      expect(r.conflict, isFalse);
      expect(r.tags, ['x', 'beach']);
    });

    test('one side deleted: the edit wins', () {
      final tombstone = make(text: '', media: [], deleted: true);
      expect(merge(null, tombstone, make()).deleted, isFalse);
      expect(merge(null, make(), tombstone).deleted, isFalse);
      expect(merge(null, tombstone, tombstone).deleted, isTrue);
    });
  });
}
