import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:open_timeline/ui/stamp/crop_page.dart';
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
  final picked = <bool>[];

  @override
  Future<File?> scan() async {
    if (error != null) throw error!;
    if (cancel) return null;
    final f = File('${dir.path}/scan-${scanned.length}.jpg')
      ..writeAsBytesSync(_png);
    scanned.add(f);
    return f;
  }

  @override
  Future<File?> pickPhoto({required bool camera}) async {
    picked.add(camera);
    final f = File('${dir.path}/photo-${picked.length}.jpg')
      ..writeAsBytesSync(_png);
    return f;
  }
}

void main() {
  late JournalStore store;
  late Directory scratch;

  setUp(mockPathProvider);

  Future<void> open(
    WidgetTester tester,
    FakeScanner Function(Directory) make, {
    bool settle = true,
  }) async {
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
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> settleReal(WidgetTester tester, {int rounds = 30}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> useCrop(WidgetTester tester) async {
    expect(find.text('Use crop'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Use crop')));
    await settleReal(tester);
  }

  Finder field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('a scan opens the stamp editor and saving files the stamp', (
    tester,
  ) async {
    late FakeScanner scanner;
    await open(tester, (d) => scanner = FakeScanner(d));
    expect(find.text('Crop the stamp'), findsOneWidget);
    await useCrop(tester);
    expect(find.text('New stamp'), findsOneWidget);
    expect(find.text('Photos & videos'), findsNothing);
    expect(field('Title (optional)'), findsNothing);
    expect(field('What happened?'), findsNothing);
    expect(field('Stamp name'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Series'),
      'JR West eki',
    );
    await tester.tap(find.byKey(const ValueKey('location-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-box')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search countries'),
      'jap',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-JP')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Japan'), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
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
    expect(saved.title, isEmpty);
    expect(saved.text, isEmpty);
    expect(saved.series, 'JR West eki');
    expect(saved.country, 'JP');
    expect(saved.media, hasLength(1));
    expect(store.mediaFile(saved, saved.media.first).existsSync(), isTrue);
    expect(store.dirtyIds, contains(saved.id));

    expect(find.text('Crop another stamp'), findsOneWidget);
    expect(
      find.text('1 stamp saved. Crop another, or tap Done.'),
      findsOneWidget,
    );
    await tester.runAsync(() => tester.tap(find.text('Done')));
    await settleReal(tester, rounds: 10);
    expect(find.byType(CropPage), findsNothing);
    expect(scanner.scanned.single.existsSync(), isFalse);
  });

  testWidgets('several stamps can be cropped from one scanned page', (
    tester,
  ) async {
    await open(tester, (d) => FakeScanner(d));
    for (var n = 1; n <= 2; n++) {
      await useCrop(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Series'),
        'series $n',
      );
      await tester.pump();
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
      );
      await settleReal(tester, rounds: 40);
    }
    expect(store.entries.map((e) => e.series).toSet(), {
      'series 1',
      'series 2',
    });
    expect(
      find.text('2 stamps saved. Crop another, or tap Done.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the crop files nothing and drops the scan', (
    tester,
  ) async {
    late FakeScanner scanner;
    await open(tester, (d) => scanner = FakeScanner(d));
    await tester.runAsync(() => tester.tap(find.text('Cancel')));
    await settleReal(tester, rounds: 10);
    expect(find.byType(CropPage), findsNothing);
    expect(store.entries, isEmpty);
    expect(scanner.scanned.single.existsSync(), isFalse);
  });

  testWidgets('discarding a new stamp removes its scanned image', (
    tester,
  ) async {
    await open(tester, (d) => FakeScanner(d));
    await useCrop(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Series'), 'x');
    await tester.pump();
    final year = Directory(store.root.path)
        .listSync()
        .whereType<Directory>()
        .single;
    expect(year.listSync().where((f) => f.path.endsWith('.png')), hasLength(1));

    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Discard')));
    await settleReal(tester, rounds: 10);
    expect(find.byType(PostPage), findsNothing);
    expect(year.listSync().where((f) => f.path.endsWith('.png')), isEmpty);
    expect(find.text('Crop the stamp'), findsOneWidget);
    expect(store.entries, isEmpty);
  });

  testWidgets('cancelling the scanner opens nothing', (tester) async {
    await open(tester, (d) => FakeScanner(d, cancel: true));
    expect(find.byType(PostPage), findsNothing);
  });

  testWidgets(
    'a scanner failure explains itself and can fall back to a photo',
    (tester) async {
      late FakeScanner scanner;
      await tester.runAsync(() async {});
      await open(
        tester,
        (d) => scanner = FakeScanner(
          d,
          error: PlatformException(code: 'scan', message: 'no module'),
        ),
        settle: false,
      );
      expect(find.text('The scanner could not start'), findsOneWidget);
      expect(find.textContaining('no module'), findsOneWidget);

      await tester.runAsync(() => tester.tap(find.text('Gallery')));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(scanner.picked, [false]);
      expect(find.text('Crop the stamp'), findsOneWidget);
      await useCrop(tester);
      expect(find.text('New stamp'), findsOneWidget);
    },
  );

  testWidgets('cancelling the fallback opens nothing', (tester) async {
    await open(
      tester,
      (d) => FakeScanner(d, error: PlatformException(code: 'scan')),
      settle: false,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
  });
}
