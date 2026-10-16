import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/navigation.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/widgets/media_tile.dart';

import 'map_test_support.dart';

const _id = '20261016-143205-k3f9';
const _photo = '${_id}_ab12.jpg';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Entry _post({
  bool conflict = false,
  List<String> media = const [],
  double? lat,
  double? lon,
}) {
  return Entry(
    id: _id,
    author: 'partner@example.com',
    time: DateTime.utc(2026, 10, 16, 12, 32, 5),
    utcOffsetMinutes: 120,
    text: 'Original',
    tags: const ['walk'],
    media: media,
    lat: lat,
    lon: lon,
    updated: DateTime.utc(2026, 10, 16, 13),
    conflict: conflict,
  );
}

void main() {
  late JournalStore store;

  setUp(mockPathProvider);

  Future<void> openPost(WidgetTester tester, {Entry? existing}) async {
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_post_'),
      );
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@example.com'));
      if (existing != null) {
        await store.writeSynced(existing, dirty: false);
        for (final m in existing.media) {
          final f = store.mediaFile(existing, m);
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(_png);
        }
      }
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => existing != null
                      ? openEntry(context, _id)
                      : newEntry(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
  }

  Finder saveButton() => find.widgetWithText(FilledButton, 'Save');
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton()).onPressed != null;

  Future<void> typeText(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(saveButton());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('an existing post opens editable, without keyboard or changes', (
    tester,
  ) async {
    await openPost(tester, existing: _post());

    expect(find.text('Post'), findsOneWidget);
    expect(find.text('partner@example.com'), findsOneWidget);
    expect(find.text('Fri 16 Oct 2026'), findsOneWidget);
    expect(find.text('14:32'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'no keyboard');
    expect(
      FocusManager.instance.primaryFocus?.context?.widget is EditableText,
      isFalse,
    );
    expect(saveEnabled(tester), isFalse);
    expect(find.text('Merge conflict'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('Save lights up on a change and leaving then asks to discard', (
    tester,
  ) async {
    await openPost(tester, existing: _post());

    await typeText(tester, 'Changed');
    expect(saveEnabled(tester), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);

    await typeText(tester, 'Original');
    expect(saveEnabled(tester), isFalse);

    await typeText(tester, 'Changed again');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
    expect(store.byId(_id)!.text, 'Original');
  });

  testWidgets('star toggles and enables Save', (tester) async {
    await openPost(tester, existing: _post());
    await tester.tap(find.byTooltip('Star this post'));
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
    await tester.tap(find.byTooltip('Remove star'));
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('a conflicted post shows the warning; saving clears the flag', (
    tester,
  ) async {
    await openPost(tester, existing: _post(conflict: true));
    expect(
      find.textContaining('Two edits of this post clashed'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await typeText(tester, 'Tidied up');
    await tapSave(tester);
    expect(find.byType(PostPage), findsNothing);
    expect(store.byId(_id)!.conflict, isFalse);
    expect(store.byId(_id)!.text, 'Tidied up');
  });

  testWidgets('tapping the inline map sets the location', (tester) async {
    await openPost(tester, existing: _post());
    expect(find.text('Tap the map to set the location'), findsOneWidget);

    await tester.ensureVisible(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FlutterMap));
    await tester.pump(
      const Duration(milliseconds: 400),
    ); // flutter_map waits out a double tap
    await tester.pumpAndSettle();

    expect(find.text('Tap the map to set the location'), findsNothing);
    expect(saveEnabled(tester), isTrue);

    await tapSave(tester);
    final stored = store.byId(_id)!;
    expect(stored.hasLocation, isTrue);
    expect(stored.lat, closeTo(30, 60));
  });

  testWidgets('Clear removes a location again', (tester) async {
    await openPost(tester, existing: _post(lat: 52.37, lon: 4.89));
    expect(find.text('Tap the map to set the location'), findsNothing);
    expect(saveEnabled(tester), isFalse);

    await tester.ensureVisible(find.text('Clear'));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to set the location'), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('a photo opens in a full-screen viewer overlay', (tester) async {
    await openPost(tester, existing: _post(media: [_photo]));

    await tester.ensureVisible(find.byType(MediaTile));
    await tester.tap(find.byType(MediaTile));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.byType(PostPage),
      findsOneWidget,
      reason: 'an overlay, not a new page',
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(PostPage), findsOneWidget);
  });

  testWidgets('Delete in the menu asks, then removes the post', (tester) async {
    await openPost(tester, existing: _post());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this post?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
    expect(store.byId(_id), isNotNull);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    for (
      var i = 0;
      i < 40 && find.byType(PostPage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byType(PostPage), findsNothing);
    expect(store.byId(_id), isNull);
  });

  testWidgets(
    'a new post starts clean, has no delete menu, saves once filled',
    (tester) async {
      await openPost(tester);
      expect(find.text('New post'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('me@example.com'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField).first, 'Hello');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);
      expect(find.byType(PostPage), findsNothing);
      expect(store.entries.single.text, 'Hello');
      expect(store.entries.single.author, 'me@example.com');
    },
  );
}
