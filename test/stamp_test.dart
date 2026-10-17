import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/models/entry_format.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/merge.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/home/filters.dart';
import 'package:open_timeline/ui/home/timeline_page.dart';
import 'package:open_timeline/ui/stamp/stamp_widgets.dart';

Entry stamp({
  String id = '20261017-101500-ab12',
  String title = '京都駅',
  String series = 'JR West eki',
  String? country = 'JP',
  DateTime? time,
}) => Entry(
  id: id,
  kind: kindStamp,
  author: 'a@x.com',
  time: time ?? DateTime.utc(2026, 10, 17, 1, 15),
  utcOffsetMinutes: 540,
  lat: 34.985,
  lon: 135.758,
  title: title,
  series: series,
  country: country,
  media: ['${id}_x7q2.jpg'],
  updated: DateTime.utc(2026, 10, 17, 1, 16),
);

void main() {
  group('file format', () {
    test('a stamp keeps kind, series and country through the file', () {
      final e = stamp();
      final text = entryToMarkdown(e);
      expect(text, contains('kind: "stamp"'));
      expect(text, contains('series: "JR West eki"'));
      expect(text, contains('country: "JP"'));
      final back = entryFromMarkdown(text);
      expect(back.isStamp, isTrue);
      expect(back.series, 'JR West eki');
      expect(back.country, 'JP');
      expect(entryToMarkdown(back), text);
    });

    test('a normal post writes none of the stamp fields', () {
      final text = entryToMarkdown(
        Entry.create(author: 'a@x.com').copyWith(text: 'hi'),
      );
      expect(text, isNot(contains('kind:')));
      expect(text, isNot(contains('series:')));
      expect(text, isNot(contains('country:')));
      expect(entryFromMarkdown(text).isStamp, isFalse);
    });

    test('country codes are upper-cased when read', () {
      final text = entryToMarkdown(stamp()).replaceFirst('"JP"', '"jp"');
      expect(entryFromMarkdown(text).country, 'JP');
    });
  });

  group('merge', () {
    test('series and country follow the side that changed them', () {
      final base = stamp(series: '', country: null);
      final local = base.copyWith(series: 'Kintetsu', country: 'JP');
      final merged = mergeEntry(
        base: base,
        local: local,
        remote: base.copyWith(title: 'Kyoto'),
        localUser: 'a@x.com',
      );
      expect(merged.series, 'Kintetsu');
      expect(merged.country, 'JP');
      expect(merged.title, 'Kyoto');
      expect(merged.isStamp, isTrue);
    });
  });

  group('filter', () {
    test('Posts and Collection narrow the list and Clear resets it', () {
      final f = EntryFilter();
      final post = Entry.create(author: 'a@x.com').copyWith(text: 'hi');
      final item = stamp();
      expect(f.apply([post, item]), hasLength(2));
      f.show = ContentShow.posts;
      expect(f.apply([post, item]), [post]);
      f.show = ContentShow.collection;
      expect(f.apply([post, item]), [item]);
      f.clear();
      expect(f.show, ContentShow.all);
    });

    test('search finds a stamp by series or country', () {
      final f = EntryFilter()..query = 'west';
      expect(f.matches(stamp()), isTrue);
      f.query = 'jp';
      expect(f.matches(stamp()), isTrue);
      f.query = 'taiwan';
      expect(f.matches(stamp()), isFalse);
    });
  });

  group('store', () {
    late Directory dir;
    late JournalStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('stamps_');
      store = JournalStore(dir);
      await store.load();
    });

    tearDown(() {
      store.dispose();
      dir.deleteSync(recursive: true);
    });

    test('allSeries lists each series of the stamps once', () async {
      await store.save(stamp(id: '20261017-101500-aaaa'));
      await store.save(stamp(id: '20261017-111500-bbbb'));
      await store.save(
        stamp(id: '20261017-121500-cccc', series: '100 Castles'),
      );
      await store.save(
        Entry.create(author: 'a@x.com').copyWith(text: 'x', series: 'Ignored'),
      );
      expect(store.allSeries, ['100 Castles', 'JR West eki']);
    });

    test('deleting a stamp keeps it a stamp for the other phones', () async {
      await store.save(stamp());
      await store.delete('20261017-101500-ab12');
      expect(store.anyById('20261017-101500-ab12')!.kind, kindStamp);
    });
  });

  group('stamp tile', () {
    late JournalStore store;

    Future<void> show(WidgetTester tester, Entry e) async {
      await tester.runAsync(() async {
        store = JournalStore(Directory.systemTemp.createTempSync('stt_'));
        await store.load();
      });
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(body: StampTile(entry: e)),
          ),
        ),
      );
    }

    testWidgets('the heading falls back from name to place to series', (
      tester,
    ) async {
      await show(
        tester,
        stamp(
          title: '',
          series: 'JR West eki',
        ).copyWith(place: 'Kyoto Station'),
      );
      expect(find.text('Kyoto Station'), findsOneWidget);
      expect(find.text('JR West eki'), findsOneWidget);

      await show(
        tester,
        stamp(title: '', series: 'JR West eki').copyWith(place: null),
      );
      expect(find.text('JR West eki'), findsOneWidget);

      await show(tester, stamp(title: '', series: '').copyWith(place: null));
      expect(find.text('Stamp'), findsOneWidget);
    });
  });

  group('timeline', () {
    late JournalStore store;

    Future<void> pump(WidgetTester tester, EntryFilter filter) async {
      await tester.runAsync(() async {
        store = JournalStore(Directory.systemTemp.createTempSync('stl_'));
        await store.load();
        await store.updateSettings(AppSettings(me: 'a@x.com'));
        await store.save(
          Entry.create(
            author: 'a@x.com',
            now: DateTime(2026, 10, 17, 9),
          ).copyWith(text: 'A normal post'),
        );
        await store.save(stamp(id: '20261017-101500-aaaa'));
        await store.save(
          stamp(
            id: '20261017-111500-bbbb',
            title: '伏見稲荷',
            time: DateTime.utc(2026, 10, 17, 2, 15),
          ),
        );
      });
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(body: TimelinePage(filter: filter)),
          ),
        ),
      );
    }

    testWidgets('a day with stamps shows one strip next to its posts', (
      tester,
    ) async {
      await pump(tester, EntryFilter());
      expect(find.byType(StampStrip), findsOneWidget);
      expect(find.byType(StampTile), findsNothing);
      expect(find.textContaining('2 stamps'), findsOneWidget);
      expect(find.text('A normal post'), findsOneWidget);
    });

    testWidgets('the strip disappears when only posts are shown', (
      tester,
    ) async {
      final filter = EntryFilter();
      await pump(tester, filter);
      filter.show = ContentShow.posts;
      await tester.pump();
      expect(find.byType(StampStrip), findsNothing);
      expect(find.text('A normal post'), findsOneWidget);
    });
  });
}
