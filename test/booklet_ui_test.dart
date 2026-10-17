import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/booklet/collection_page.dart';
import 'package:open_timeline/ui/booklet/stamp_print.dart';

import 'pump_support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late JournalStore store;

  Future<void> open(
    WidgetTester tester, {
    int japan = 5,
    bool taiwan = true,
  }) async {
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('book_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      var n = 0;
      Future<void> add(
        String country,
        String series, {
        String size = sizeMedium,
        bool blend = false,
      }) async {
        n++;
        final id =
            '202610${(10 + n).toString().padLeft(2, '0')}-100000-a${n.toString().padLeft(3, '0')}';
        final e = Entry(
          id: id,
          kind: kindStamp,
          author: 'me@x.com',
          time: DateTime.utc(2026, 10, 10 + n),
          utcOffsetMinutes: 0,
          country: country,
          series: series,
          size: size,
          blend: blend,
          place: 'Place $n',
          media: ['${id}_aaaa.png'],
          updated: DateTime.utc(2026, 10, 10 + n),
        );
        await store.writeSynced(e, dirty: false);
        final f = store.mediaFile(e, e.media.first);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(_png);
      }

      for (var i = 0; i < japan; i++) {
        await add(
          'JP',
          i < 3 ? 'JR West' : 'Metro',
          size: i == 0 ? sizeLarge : sizeMedium,
        );
      }
      if (taiwan) await add('TW', 'Rail');
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(home: Scaffold(body: CollectionPage())),
      ),
    );
    await tester.pump();
  }

  testWidgets('the menu has one booklet per country with its count', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Japan'), findsOneWidget);
    expect(find.text('Taiwan'), findsOneWidget);
    expect(find.text('5 stamps'), findsOneWidget);
    expect(find.text('1 stamp'), findsOneWidget);
    expect(find.text('2 series'), findsOneWidget);
  });

  testWidgets('without stamps the menu invites a first scan', (tester) async {
    await open(tester, japan: 0, taiwan: false);
    expect(find.text('No stamps yet'), findsOneWidget);
  });

  testWidgets('a booklet opens on its cover, and bookmarks jump to a series', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-JP')));
    await tester.pumpAndSettle();
    expect(find.text('🇯🇵 Japan'), findsOneWidget);
    expect(find.text('Swipe to turn the page'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await pumpUntil(tester, () => find.text('METRO').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('METRO'), findsOneWidget);
    expect(find.byType(StampPrint), findsNWidgets(2));
    expect(find.text('Swipe to turn the page'), findsNothing);
  });

  testWidgets(
    'swiping turns the page and the first series page shows its stamps',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('booklet-JP')));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(StampPrint).evaluate().isEmpty
            ? find.text('Swipe to turn the page')
            : find.byType(StampPrint).first,
        const Offset(-300, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('JR WEST'), findsOneWidget);
      expect(find.byType(StampPrint), findsNWidgets(3));

      await tester.fling(find.text('JR WEST'), const Offset(300, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('Swipe to turn the page'), findsOneWidget);
    },
  );

  testWidgets('tapping a stamp on a page opens it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-TW')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await pumpUntil(
      tester,
      () => find.byType(StampPrint).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byType(StampPrint), findsOneWidget);
    expect(find.textContaining('Place 6'), findsOneWidget);
  });
}
