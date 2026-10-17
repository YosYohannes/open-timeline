import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:open_timeline/ui/stamp/stamp_scan.dart';

import 'map_test_support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class FakeScanner implements StampScanner {
  FakeScanner(this.dir, {this.cancel = false, this.error});

  final Directory dir;
  final bool cancel;
  final Object? error;
  final scanned = <File>[];

  @override
  Future<File?> scan() async {
    if (error != null) throw error!;
    if (cancel) return null;
    final f = File('${dir.path}/scan-${scanned.length}.jpg')
      ..writeAsBytesSync(_png);
    scanned.add(f);
    return f;
  }
}

void main() {
  late JournalStore store;
  late Directory scratch;

  setUp(mockPathProvider);

  Future<void> open(
    WidgetTester tester,
    FakeScanner Function(Directory) make,
  ) async {
    late FakeScanner scanner;
    await tester.runAsync(() async {
      scratch = Directory.systemTemp.createTempSync('scan_tmp_');
      store = JournalStore(Directory.systemTemp.createTempSync('scan_store_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      scanner = make(scratch);
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => newStamp(context, scanner: scanner),
                child: const Text('Scan'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('Scan')));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Finder field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('a scan opens the stamp editor and saving files the stamp', (
    tester,
  ) async {
    late FakeScanner scanner;
    await open(tester, (d) => scanner = FakeScanner(d));
    expect(find.text('New stamp'), findsOneWidget);
    expect(find.text('Photos & videos'), findsNothing);
    expect(scanner.scanned.single.existsSync(), isFalse);

    await tester.enterText(field('Stamp name'), '京都駅');
    await tester.enterText(
      find.widgetWithText(TextField, 'Series'),
      'JR West eki',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Country code'),
      'jp',
    );
    await tester.pump();

    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
    );
    for (
      var i = 0;
      i < 60 && find.byType(PostPage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final saved = store.entries.single;
    expect(saved.isStamp, isTrue);
    expect(saved.title, '京都駅');
    expect(saved.series, 'JR West eki');
    expect(saved.country, 'JP');
    expect(saved.media, hasLength(1));
    expect(store.mediaFile(saved, saved.media.first).existsSync(), isTrue);
    expect(store.dirtyIds, contains(saved.id));
  });

  testWidgets('discarding a new stamp removes its scanned image', (
    tester,
  ) async {
    await open(tester, (d) => FakeScanner(d));
    await tester.enterText(field('Stamp name'), 'x');
    await tester.pump();
    final year = Directory(store.root.path)
        .listSync()
        .whereType<Directory>()
        .single;
    expect(year.listSync().where((f) => f.path.endsWith('.jpg')), hasLength(1));

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Discard')));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
    expect(year.listSync().where((f) => f.path.endsWith('.jpg')), isEmpty);
    expect(store.entries, isEmpty);
  });

  testWidgets('cancelling the scanner opens nothing', (tester) async {
    await open(tester, (d) => FakeScanner(d, cancel: true));
    expect(find.byType(PostPage), findsNothing);
  });

  testWidgets('a scanner failure is shown instead of crashing', (tester) async {
    await open(
      tester,
      (d) => FakeScanner(
        d,
        error: PlatformException(code: 'scan', message: 'no module'),
      ),
    );
    expect(find.byType(PostPage), findsNothing);
    expect(find.textContaining('no module'), findsOneWidget);
  });
}
