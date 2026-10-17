import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/booklet/book_pager.dart';
import 'package:open_timeline/ui/booklet/collection_page.dart';
import 'package:open_timeline/ui/booklet/stamp_print.dart';

import 'pump_support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late JournalStore store;

  Future<void> phoneScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester, {
    int japan = 5,
    bool taiwan = true,
  }) async {
    await phoneScreen(tester);
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
    expect(find.text('JAPAN'), findsOneWidget);
    expect(find.text('TAIWAN'), findsOneWidget);
    expect(find.text('5 stamps'), findsOneWidget);
    expect(find.text('1 stamp'), findsOneWidget);
    expect(find.text('2 series'), findsOneWidget);
  });

  testWidgets('without stamps the menu invites a first scan', (tester) async {
    await open(tester, japan: 0, taiwan: false);
    expect(find.text('No stamps yet'), findsOneWidget);
  });

  Future<void> turn(WidgetTester tester, {bool forward = true}) async {
    await tester.flingFrom(
      tester.getCenter(find.byType(BookPager)),
      Offset(forward ? -300 : 300, 0),
      1200,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a booklet opens on its cover, then a contents page', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-JP')));
    await tester.pumpAndSettle();
    expect(find.text('🇯🇵 Japan'), findsOneWidget);
    expect(find.text('Swipe to turn the page'), findsOneWidget);

    await turn(tester);
    expect(find.text('CONTENTS'), findsOneWidget);
    expect(find.byKey(const ValueKey('contents-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('contents-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('contents-2')), findsNothing);
    expect(find.text('JR West'), findsOneWidget);
    expect(find.text('3 stamps'), findsOneWidget);
    expect(find.text('Metro'), findsOneWidget);
    expect(find.text('2 stamps'), findsOneWidget);
  });

  testWidgets(
    'a contents line jumps to its series and the page number comes back',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('booklet-JP')));
      await tester.pumpAndSettle();
      await turn(tester);

      await tester.tap(find.byKey(const ValueKey('contents-1')));
      await pumpUntil(tester, () => find.text('METRO').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('METRO'), findsOneWidget);
      expect(find.byType(StampPrint), findsNWidgets(2));

      final number = find.descendant(
        of: find.byType(InkWell),
        matching: find.textContaining(RegExp(r'^\d+$')),
      );
      await tester.tap(number.last);
      await pumpUntil(
        tester,
        () => find.text('CONTENTS').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('CONTENTS'), findsOneWidget);
    },
  );

  testWidgets('swiping turns past the contents to the first series', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-JP')));
    await tester.pumpAndSettle();
    await turn(tester);
    await turn(tester);
    expect(find.text('JR WEST'), findsOneWidget);
    final onPage = find.byType(StampPrint).evaluate().length;
    expect(onPage, inInclusiveRange(1, 3));

    await turn(tester, forward: false);
    expect(find.text('CONTENTS'), findsOneWidget);
  });

  testWidgets('tapping a stamp on a page opens it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-TW')));
    await tester.pumpAndSettle();
    await turn(tester);
    await tester.tap(find.byKey(const ValueKey('contents-0')));
    await pumpUntil(
      tester,
      () => find.byType(StampPrint).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byType(StampPrint), findsOneWidget);
    expect(find.textContaining('Place 6'), findsOneWidget);
  });

  testWidgets('one swipe turns one page, however long or fast', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-JP')));
    await tester.pumpAndSettle();
    await tester.flingFrom(
      tester.getCenter(find.byType(BookPager)),
      const Offset(-900, 0),
      5000,
    );
    await tester.pumpAndSettle();
    expect(find.text('CONTENTS'), findsOneWidget);
  });

  testWidgets('a page bends while it turns, then lies flat again', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booklet-JP')));
    await tester.pumpAndSettle();
    final cover = tester.getCenter(find.byType(BookPager));
    final turning = await tester.startGesture(cover);
    await turning.moveBy(const Offset(-60, 0));
    await turning.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(find.text('Swipe to turn the page'), findsAtLeastNWidgets(2));
    expect(find.text('CONTENTS'), findsOneWidget);
    await turning.up();
    await tester.pumpAndSettle();
    expect(find.text('Swipe to turn the page'), findsOneWidget);
    expect(find.text('CONTENTS'), findsNothing);
  });
}
