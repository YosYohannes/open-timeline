import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:open_timeline/ui/stamp/crop_page.dart';
import 'package:open_timeline/ui/stamp/stamp_scan.dart';

import 'map_test_support.dart';
import 'pump_support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class FakeScanner implements StampScanner {
  FakeScanner(this.dir, {this.cancel = false, this.error, this.image});

  final Directory dir;
  final bool cancel;
  final Object? error;
  final Uint8List? image;
  final scanned = <File>[];
  final picked = <bool>[];

  @override
  Future<File?> scan() async {
    if (error != null) throw error!;
    if (cancel) return null;
    final f = File('${dir.path}/scan-${scanned.length}.jpg')
      ..writeAsBytesSync(image ?? _png);
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
    await pumpUntil(
      tester,
      () => cropReady(tester) || find.byType(AlertDialog).evaluate().isNotEmpty,
      maxRounds: settle ? 400 : 20,
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> settleReal(
    WidgetTester tester, {
    int rounds = 400,
    bool Function()? until,
  }) async {
    await pumpUntil(tester, until ?? () => false, maxRounds: rounds);
    await tester.pump(const Duration(seconds: 1));
  }

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  Future<void> useCrop(WidgetTester tester) async {
    await pumpUntil(tester, () => cropReady(tester));
    expect(find.text('Use crop'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Use crop')));
    await settleReal(tester, until: () => shows('New stamp'));
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
    await tester.ensureVisible(find.byKey(const ValueKey('location-row')));
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
    await settleReal(tester, until: () => shows('Crop another stamp'));

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
    await settleReal(
      tester,
      until: () => find.byType(CropPage).evaluate().isEmpty,
    );
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
      await settleReal(tester, until: () => shows('Crop another stamp'));
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
    await settleReal(
      tester,
      until: () => find.byType(CropPage).evaluate().isEmpty,
    );
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
    await settleReal(tester, until: () => shows('Crop the stamp'));
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
      await settleReal(tester, until: () => shows('Crop the stamp'));
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

  Future<Uint8List> solidPng(WidgetTester tester, Color color) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec)
          .drawRect(const Rect.fromLTWH(0, 0, 24, 24), Paint()..color = color);
      final img = await rec.endRecording().toImage(24, 24);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
    });
    return bytes;
  }

  bool blendOn(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.byKey(const ValueKey('blend-switch')))
      .value;

  testWidgets(
    'a scan on light paper starts with blend on, dark paper with it off',
    (tester) async {
      final cream = await solidPng(tester, const Color(0xFFF1E6C8));
      await open(tester, (d) => FakeScanner(d, image: cream));
      await useCrop(tester);
      expect(blendOn(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('blend-switch')));
      await tester.pump();
      expect(blendOn(tester), isFalse);
    },
  );

  testWidgets('dark paper does not blend by default', (tester) async {
    final green = await solidPng(tester, const Color(0xFF1F3D2B));
    await open(tester, (d) => FakeScanner(d, image: green));
    await useCrop(tester);
    expect(blendOn(tester), isFalse);
  });

  testWidgets('size and blend are saved with the stamp', (tester) async {
    final white = await solidPng(tester, const Color(0xFFFFFFFF));
    await open(tester, (d) => FakeScanner(d, image: white));
    await useCrop(tester);
    expect(blendOn(tester), isTrue);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('size-choice')),
        matching: find.text('Large'),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
    );
    await settleReal(tester, until: () => shows('Crop another stamp'));
    final saved = store.entries.single;
    expect(saved.blend, isTrue);
    expect(saved.size, sizeLarge);
  });
}
