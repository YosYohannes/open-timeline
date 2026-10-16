import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/settings/author_colors.dart';
import 'package:open_timeline/ui/widgets/author.dart';

void main() {
  late JournalStore store;

  Future<void> makeStore(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('colours_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
    });
  }

  testWidgets('default colours are stable, case-insensitive and gentle', (
    tester,
  ) async {
    await makeStore(tester);
    final c = defaultAuthorColor('A@x.com');
    expect(c, defaultAuthorColor('a@x.com'));
    expect(kAuthorPalette, contains(c));
    expect(
      authorColorFor(store, 'nobody@x.com'),
      defaultAuthorColor('nobody@x.com'),
    );
  });

  testWidgets('my colour is mine; the partner\'s comes from their posts', (
    tester,
  ) async {
    await makeStore(tester);
    await tester.runAsync(() async {
      await store.updateSettings(store.settings.copyWith(myColor: 0xFF123456));
      await store.writeSynced(
        Entry.create(author: 'partner@x.com').copyWith(color: 0xFF654321),
        dirty: false,
      );
    });
    expect(authorColorFor(store, 'ME@x.com'), const Color(0xFF123456));
    expect(authorColorFor(store, 'partner@x.com'), const Color(0xFF654321));
  });

  testWidgets('picker shows only my colour and tapping a swatch saves it', (
    tester,
  ) async {
    await makeStore(tester);
    await tester.runAsync(() async {
      await store.writeSynced(
        Entry.create(author: 'partner@x.com').copyWith(text: 'hi'),
        dirty: false,
      );
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(home: Scaffold(body: MyColorPicker())),
      ),
    );
    expect(find.text('partner@x.com'), findsNothing);

    final target = kAuthorPalette.firstWhere(
      (c) => c != defaultAuthorColor('me@x.com'),
    );
    final swatches = find.descendant(
      of: find.byType(MyColorPicker),
      matching: find.byType(InkWell),
    );
    await tester.runAsync(() async {
      await tester.tap(swatches.at(kAuthorPalette.indexOf(target)));
    });
    await tester.pump();
    expect(store.settings.myColor, target.toARGB32());
  });
}
