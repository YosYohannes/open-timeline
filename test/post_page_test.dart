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
import 'pump_support.dart';

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

  Future<void> openPost(
    WidgetTester tester, {
    Entry? existing,
    List<Entry> others = const [],
  }) async {
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_post_'),
      );
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@example.com'));
      for (final o in others) {
        await store.writeSynced(o, dirty: false);
      }
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

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  Future<void> typeText(WidgetTester tester, String text) async {
    await tester.enterText(fieldWithHint('What happened?'), text);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.runAsync(() => tester.tap(saveButton()));
    await pumpUntil(tester, () => find.byType(PostPage).evaluate().isEmpty);
    await tester.pumpAndSettle();
  }

  testWidgets('an existing post opens editable, without keyboard or changes', (
    tester,
  ) async {
    await openPost(tester, existing: _post());

    expect(find.text('Post'), findsOneWidget);
    expect(find.text('partner@example.com'), findsNothing);
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

  testWidgets('a title can be added and is saved', (tester) async {
    await openPost(tester, existing: _post());
    await tester.enterText(fieldWithHint('Title (optional)'), 'Canal walk');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);
    expect(store.byId(_id)!.title, 'Canal walk');
  });

  Entry stampOf(List<String> tags) => Entry(
    id: _id,
    kind: kindStamp,
    author: 'me@example.com',
    time: DateTime.utc(2026, 10, 16, 12),
    utcOffsetMinutes: 0,
    series: 'Old trip',
    country: 'JP',
    tags: tags,
    media: const [_photo],
    updated: DateTime.utc(2026, 10, 16, 13),
  );

  testWidgets('a post has no event field', (tester) async {
    await openPost(tester, existing: _post());
    expect(find.widgetWithText(TextField, 'Event'), findsNothing);
  });

  testWidgets('a stamp keeps its event among its tags, whatever it is', (
    tester,
  ) async {
    await openPost(tester, existing: stampOf(['Old trip', 'food']));
    expect(find.byKey(const ValueKey('event-tag')), findsOneWidget);
    expect(find.text('#food'), findsOneWidget);
    expect(saveEnabled(tester), isFalse, reason: 'already in its tags');

    final field = find.widgetWithText(TextField, 'Event');
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, 'Kyoto trip');
    await tester.pump();
    expect(find.text('#Kyoto trip'), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
    await tapSave(tester);
    expect(store.byId(_id)!.series, 'Kyoto trip');
    expect(store.byId(_id)!.tags, ['Kyoto trip', 'food']);
    expect(store.recentTags, containsAll(['Kyoto trip', 'food']));
  });

  testWidgets('an older stamp gets its event as a tag once it is saved', (
    tester,
  ) async {
    await openPost(tester, existing: stampOf(['food']));
    expect(saveEnabled(tester), isFalse);
    await tester.ensureVisible(find.text('Large'));
    await tester.pump();
    await tester.tap(find.text('Large'));
    await tester.pump();
    await tapSave(tester);
    expect(store.byId(_id)!.tags, ['Old trip', 'food']);
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
    expect(find.text('Add location'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('location-row')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to set the location'), findsOneWidget);

    await tester.tap(find.byType(FlutterMap));
    await tester.pump(
      const Duration(milliseconds: 400),
    ); // flutter_map waits out a double tap
    await tester.pumpAndSettle();

    expect(find.text('Tap the map to set the location'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Add location'), findsNothing);
    expect(saveEnabled(tester), isTrue);

    await tapSave(tester);
    final stored = store.byId(_id)!;
    expect(stored.hasLocation, isTrue);
    expect(stored.lat, closeTo(30, 60));
  });

  testWidgets('Clear removes a location again', (tester) async {
    await openPost(tester, existing: _post(lat: 52.37, lon: 4.89));
    expect(find.text('Add location'), findsNothing);
    expect(saveEnabled(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('location-row')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to set the location'), findsNothing);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to set the location'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Add location'), findsOneWidget);
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
      expect(find.text('me@example.com'), findsNothing);
      expect(saveEnabled(tester), isFalse);

      await typeText(tester, 'Hello');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);
      expect(find.byType(PostPage), findsNothing);
      expect(store.entries.single.text, 'Hello');
      expect(store.entries.single.author, 'me@example.com');
    },
  );

  testWidgets(
    'the editor has no section headers, and + offers Photo, Video, Gallery',
    (tester) async {
      await openPost(tester);
      for (final header in ['Location', 'Tags', 'Photos & videos']) {
        expect(find.text(header), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('add-media')));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    },
  );

  testWidgets('tags are added inline and suggestions only show while typing', (
    tester,
  ) async {
    await openPost(tester, existing: _post());
    expect(find.text('#walk'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '+ tag'), 'beach,');
    await tester.pump();
    expect(find.text('#beach'), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('every known tag sits in a scrollable strip, newest first', (
    tester,
  ) async {
    Entry tagged(String id, int day, List<String> tags) => Entry(
      id: id,
      author: 'partner@example.com',
      time: DateTime.utc(2026, 10, day, 12),
      utcOffsetMinutes: 0,
      text: id,
      tags: tags,
      updated: DateTime.utc(2026, 10, day, 12),
    );
    await openPost(
      tester,
      existing: _post(),
      others: [
        tagged('20261001-120000-aaaa', 1, ['beach']),
        tagged('20261012-120000-bbbb', 12, ['sea']),
        tagged('20261005-120000-cccc', 5, ['city']),
      ],
    );
    final chips = find.descendant(
      of: find.byKey(const ValueKey('tag-strip')),
      matching: find.byType(ActionChip),
    );
    expect(
      [
        for (final c in tester.widgetList<ActionChip>(chips))
          ((c.label as Text).data),
      ],
      ['#sea', '#city', '#beach'],
      reason: 'newest first, without the tag already on the post',
    );

    await tester.enterText(find.widgetWithText(TextField, '+ tag'), 'ci');
    await tester.pump();
    expect(find.text('#city'), findsOneWidget);
    expect(find.text('#sea'), findsNothing);
    await tester.ensureVisible(find.text('#city'));
    await tester.pump();
    await tester.tap(find.text('#city'));
    await tester.pump();
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(saveEnabled(tester), isTrue);
  });
}
