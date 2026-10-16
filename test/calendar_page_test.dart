import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/home/calendar_page.dart';
import 'package:open_timeline/ui/home/filters.dart';

void main() {
  late JournalStore store;
  late EntryFilter filter;
  final now = DateTime.now();
  final otherDay = now.day == 1 ? 2 : 1;

  Entry post(DateTime at, String text, String author) =>
      Entry.create(author: author, now: at).copyWith(text: text);

  setUp(() => filter = EntryFilter());

  Future<void> openCalendar(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_cal_'),
      );
      await store.load();
      final today = DateTime(now.year, now.month, now.day, 10);
      final other = DateTime(now.year, now.month, otherDay, 9);
      await store.writeSynced(
        post(today, 'Today note', 'a@x.com'),
        dirty: false,
      );
      await store.writeSynced(
        post(other, 'Other note', 'b@x.com'),
        dirty: false,
      );
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(body: CalendarPage(filter: filter)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current month and the posts of today', (tester) async {
    await openCalendar(tester);
    expect(find.text(DateFormat('MMMM yyyy').format(now)), findsOneWidget);
    expect(find.text('Today note'), findsOneWidget);
    expect(find.text('Other note'), findsNothing);
  });

  testWidgets('tapping a day shows that day\'s posts', (tester) async {
    await openCalendar(tester);
    await tester.tap(find.text('$otherDay'));
    await tester.pumpAndSettle();
    expect(find.text('Other note'), findsOneWidget);
    expect(find.text('Today note'), findsNothing);
  });

  testWidgets('month arrows move the month and keep the day number', (
    tester,
  ) async {
    await openCalendar(tester);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final next = DateTime(now.year, now.month + 1);
    expect(find.text(DateFormat('MMMM yyyy').format(next)), findsOneWidget);
    expect(find.text('Today note'), findsNothing);
    expect(find.textContaining('no posts'), findsOneWidget);

    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('MMMM yyyy').format(now)), findsOneWidget);
    expect(find.text('Today note'), findsOneWidget);
  });

  testWidgets('follows the shared filter', (tester) async {
    await openCalendar(tester);
    filter.author = 'b@x.com';
    await tester.pumpAndSettle();
    expect(find.text('Today note'), findsNothing);
    expect(find.textContaining('no posts'), findsOneWidget);
  });
}
