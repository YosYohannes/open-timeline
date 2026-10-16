import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/home/timeline_page.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    Entry Function(Entry) build,
  ) async {
    late JournalStore store;
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('card_'));
      await store.load();
    });
    final entry = build(Entry.create(author: 'a@x.com'));
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(body: EntryCard(entry: entry)),
        ),
      ),
    );
  }

  testWidgets('shows the title beside the time', (tester) async {
    await pumpCard(tester, (e) => e.copyWith(title: 'Canal walk', text: 'Hi'));
    expect(find.text('Canal walk'), findsOneWidget);
    expect(find.text('Hi'), findsOneWidget);
  });

  testWidgets('one photo has no counter, three photos show +2', (tester) async {
    await pumpCard(tester, (e) => e.copyWith(media: ['${e.id}_a.jpg']));
    expect(find.textContaining('+'), findsNothing);
    await pumpCard(
      tester,
      (e) => e.copyWith(
        media: ['${e.id}_a.jpg', '${e.id}_b.jpg', '${e.id}_c.mp4'],
      ),
    );
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('long text is cut with an ellipsis next to a photo', (
    tester,
  ) async {
    await pumpCard(
      tester,
      (e) => e.copyWith(text: 'word ' * 400, media: ['${e.id}_a.jpg']),
    );
    final text = tester.widget<Text>(find.textContaining('word'));
    expect(text.maxLines, 4);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
