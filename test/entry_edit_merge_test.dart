import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/post/post_page.dart';

import 'map_test_support.dart';

const _id = '20261016-143205-k3f9';
const _mergedSnack = 'Merged with changes synced while you were editing';

Entry _post({
  String text = 'Original',
  List<String> tags = const ['walk'],
  List<String> media = const [],
  bool deleted = false,
}) {
  return Entry(
    id: _id,
    author: 'partner@example.com',
    time: DateTime.utc(2026, 10, 16, 12, 32, 5),
    utcOffsetMinutes: 120,
    text: text,
    tags: tags,
    media: media,
    updated: DateTime.utc(2026, 10, 16, 13),
    deleted: deleted,
  );
}

void main() {
  late JournalStore store;

  setUp(mockPathProvider);

  Future<void> openEditor(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_edit_'),
      );
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@example.com'));
      await store.writeSynced(_post(), dirty: false);
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostPage(entry: store.byId(_id)!),
                    ),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
  }

  Future<void> typeText(WidgetTester tester, String text) async {
    await tester.enterText(find.widgetWithText(TextField, 'Original'), text);
    await tester.pump();
  }

  Future<void> syncPull(WidgetTester tester, Entry partner) async {
    await tester.runAsync(() => store.writeSynced(partner, dirty: false));
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() => tester.tap(find.text('Save')));
    for (
      var i = 0;
      i < 100 && find.byType(PostPage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
  }

  testWidgets('partner tag and photo synced while editing are kept', (
    tester,
  ) async {
    await openEditor(tester);
    await typeText(tester, 'Original, and my new words');
    await syncPull(
      tester,
      _post(tags: ['walk', 'partner-tag'], media: ['${_id}_ab12.jpg']),
    );

    await save(tester);

    final stored = store.byId(_id)!;
    expect(stored.text, 'Original, and my new words');
    expect(stored.tags, containsAll(['walk', 'partner-tag']));
    expect(stored.media, ['${_id}_ab12.jpg']);
    expect(stored.conflict, isFalse);
    expect(store.dirtyIds, contains(_id));
    expect(find.text(_mergedSnack), findsOneWidget);
  });

  testWidgets('both edited the text: both kept and the post is flagged', (
    tester,
  ) async {
    await openEditor(tester);
    await typeText(tester, 'My version');
    await syncPull(tester, _post(text: 'Partner version'));

    await save(tester);

    final stored = store.byId(_id)!;
    expect(stored.text, contains('Partner version'));
    expect(stored.text, contains('My version'));
    expect(stored.conflict, isTrue);
    expect(find.text(_mergedSnack), findsOneWidget);
  });

  testWidgets('partner deleted the post while I edited: my edit wins', (
    tester,
  ) async {
    await openEditor(tester);
    await typeText(tester, 'Still mine');
    await syncPull(tester, _post(text: '', deleted: true));
    expect(store.byId(_id), isNull);

    await save(tester);

    final stored = store.byId(_id);
    expect(stored, isNotNull);
    expect(stored!.text, 'Still mine');
    expect(stored.deleted, isFalse);
    expect(find.text(_mergedSnack), findsOneWidget);
  });

  testWidgets('without a concurrent change the edit is saved silently', (
    tester,
  ) async {
    await openEditor(tester);
    await typeText(tester, 'Just my edit');

    await save(tester);

    expect(store.byId(_id)!.text, 'Just my edit');
    expect(find.text(_mergedSnack), findsNothing);
  });
}
