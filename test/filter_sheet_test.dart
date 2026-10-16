import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/home/filter_sheet.dart';
import 'package:open_timeline/ui/home/filters.dart';

void main() {
  testWidgets('sheet lists the filters and clears them', (tester) async {
    final filter = EntryFilter();
    late JournalStore store;
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_filter_'),
      );
      await store.load();
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showFilterSheet(context, filter),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Any date'), findsOneWidget);
    expect(find.text('Any tag'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);

    filter.tag = 'walk';
    await tester.pumpAndSettle();
    expect(find.text('#walk'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(filter.tag, isNull);
    expect(find.text('Any tag'), findsOneWidget);
  });
}
