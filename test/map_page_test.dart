import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/home/filters.dart';
import 'package:open_timeline/ui/home/map_page.dart';

import 'map_test_support.dart';

void main() {
  setUp(mockPathProvider);

  testWidgets('the map has a my-location button and survives a failed lookup', (
    tester,
  ) async {
    late JournalStore store;
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('map_page_'));
      await store.load();
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(body: MapPage(filter: EntryFilter(), active: true)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('My location'), findsOneWidget);
    expect(find.byTooltip('Fit to posts'), findsOneWidget);

    await tester.tap(find.byTooltip('My location'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
