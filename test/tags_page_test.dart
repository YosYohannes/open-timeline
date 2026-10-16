import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/settings/tags_page.dart';

void main() {
  late JournalStore store;

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('tags_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      for (final tags in [
        ['boulder'],
        ['boulder', 'trip'],
        ['climbing'],
      ]) {
        await store.save(
          Entry.create(author: 'me@x.com').copyWith(text: 'x', tags: tags),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(home: TagsPage()),
      ),
    );
  }

  testWidgets('lists tags with their post counts', (tester) async {
    await pumpPage(tester);
    expect(find.text('#boulder'), findsOneWidget);
    expect(find.text('2 posts'), findsOneWidget);
    expect(find.text('1 post'), findsNWidgets(2));
  });

  testWidgets('renaming into an existing tag offers a merge', (tester) async {
    await pumpPage(tester);
    await tester.runAsync(
      () => tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tag-boulder')),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'climbing');
    await tester.pump();
    expect(find.text('Merges into #climbing'), findsOneWidget);
    await tester.tap(find.text('Merge'));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(store.tagCounts, {'climbing': 3, 'trip': 1});
    expect(find.text('#boulder'), findsNothing);
  });

  testWidgets('deleting asks first and then removes the tag everywhere', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tag-boulder')),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2 posts'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.tagCounts['boulder'], 2);

    await tester.runAsync(
      () => tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tag-boulder')),
          matching: find.byIcon(Icons.delete_outline),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(store.tagCounts.containsKey('boulder'), isFalse);
    expect(find.text('#boulder'), findsNothing);
  });
}
