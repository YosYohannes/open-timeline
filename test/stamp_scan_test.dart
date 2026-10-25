import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/booklet/subject_segmenter.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:open_timeline/ui/stamp/crop_page.dart';
import 'package:open_timeline/ui/stamp/detected_page.dart';
import 'package:open_timeline/ui/stamp/stamp_scan.dart';

import 'map_test_support.dart';
import 'pump_support.dart';

class FakePhotos implements StampPhotos {
  FakePhotos(this.dir, this.image, {this.cancel = false});

  final Directory dir;
  final Uint8List image;
  final bool cancel;
  final taken = <File>[];
  final asked = <bool>[];

  @override
  Future<File?> pick({required bool camera}) async {
    asked.add(camera);
    if (cancel) return null;
    final f = File('${dir.path}/photo-${taken.length}.jpg')
      ..writeAsBytesSync(image);
    taken.add(f);
    return f;
  }
}

class FakeFinder implements SubjectSegmenter {
  FakeFinder(this.answers, {this.error});

  final List<List<Rect>?> answers;
  final String? error;
  var calls = 0;

  @override
  String? get lastError => error;

  @override
  Future<List<Rect>?> detect(File image) async {
    final i = calls < answers.length ? calls : answers.length - 1;
    calls++;
    return answers[i];
  }

  @override
  Future<File?> segment(File image) async => null;
}

const _left = Rect.fromLTWH(0.05, 0.1, 0.3, 0.3);
const _middle = Rect.fromLTWH(0.35, 0.35, 0.3, 0.3);
const _right = Rect.fromLTWH(0.65, 0.6, 0.3, 0.3);

void main() {
  late JournalStore store;
  late Directory scratch;
  late SubjectSegmenter before;

  setUp(() {
    mockPathProvider();
    before = subjectSegmenter;
  });
  tearDown(() => subjectSegmenter = before);

  Future<Uint8List> samplePng(WidgetTester tester) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 400, 300),
        Paint()..color = Colors.green,
      );
      final img = await rec.endRecording().toImage(400, 300);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
    });
    return bytes;
  }

  Future<FakePhotos> open(
    WidgetTester tester,
    List<List<Rect>?> found, {
    bool cancel = false,
    String? error,
    List<Entry> existing = const [],
  }) async {
    final png = await samplePng(tester);
    late FakePhotos photos;
    await tester.runAsync(() async {
      scratch = Directory.systemTemp.createTempSync('photo_tmp_');
      store = JournalStore(Directory.systemTemp.createTempSync('photo_store_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      for (final e in existing) {
        await store.writeSynced(e, dirty: false);
      }
      photos = FakePhotos(scratch, png, cancel: cancel);
    });
    subjectSegmenter = FakeFinder(found, error: error);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => newStamp(context, photos: photos),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    return photos;
  }

  Future<void> takePhoto(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('source-camera'))),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(DetectedStampsPage).evaluate().isNotEmpty ||
          find.byType(CropPage).evaluate().isNotEmpty,
    );
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

  Future<void> useFound(WidgetTester tester) async {
    await pumpUntil(
      tester,
      () =>
          find.byKey(const ValueKey('use-found')).evaluate().isNotEmpty &&
          tester
                  .widget<FilledButton>(find.byKey(const ValueKey('use-found')))
                  .onPressed !=
              null,
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('use-found'))),
    );
    await settleReal(tester, until: () => shows('New stamp'));
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Save')),
    );
  }

  String seriesText(WidgetTester tester) => tester
      .widget<TextField>(find.widgetWithText(TextField, 'Series'))
      .controller!
      .text;

  Future<void> nextEditor(WidgetTester tester, int saved) async {
    await settleReal(tester, until: () => store.entries.length == saved);
    await tester.pump(const Duration(seconds: 2));
    await pumpUntil(tester, () => find.byType(PostPage).evaluate().length == 1);
  }

  testWidgets('the photo can come from the camera or the gallery', (
    tester,
  ) async {
    final photos = await open(tester, [
      [_middle],
    ]);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('source-gallery'))),
    );
    await settleReal(
      tester,
      until: () => find.byType(DetectedStampsPage).evaluate().isNotEmpty,
    );
    expect(photos.asked, [false]);
  });

  testWidgets('every stamp the phone finds is filed with the same event', (
    tester,
  ) async {
    final photos = await open(tester, [
      [_left, _right],
    ]);
    await takePhoto(tester);
    expect(find.text('Found 2 stamps'), findsOneWidget);
    expect(find.text('Use 2 stamps'), findsOneWidget);
    await useFound(tester);

    expect(find.text('New stamp'), findsOneWidget);
    expect(find.text('Photos & videos'), findsNothing);
    expect(seriesText(tester), isEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, 'Series'),
      'JR West eki',
    );
    await tester.pump();
    await save(tester);

    await nextEditor(tester, 1);
    expect(seriesText(tester), 'JR West eki');
    await save(tester);
    await settleReal(tester, until: () => shows('2 stamps saved'));

    expect(find.text('Add another photo with the same details?'), findsOne);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('batch-done'))),
    );
    await tester.pumpAndSettle();

    expect(store.entries, hasLength(2));
    expect(store.entries.every((e) => e.isStamp && e.blend), isTrue);
    expect(store.entries.map((e) => e.series).toSet(), {'JR West eki'});
    expect(store.entries.map((e) => e.time).toSet(), hasLength(1));
    for (final e in store.entries) {
      expect(e.media, hasLength(1));
      expect(store.mediaFile(e, e.media.first).existsSync(), isTrue);
    }
    expect(photos.taken.single.existsSync(), isFalse);
  });

  testWidgets('a box can be left out', (tester) async {
    await open(tester, [
      [_middle, _right],
    ]);
    await takePhoto(tester);
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('detected-area')).evaluate().isNotEmpty,
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detected-area'))),
    );
    await tester.pump();
    expect(find.text('Use 1 stamp'), findsOneWidget);
    await useFound(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Series'), 'one');
    await tester.pump();
    await save(tester);
    await settleReal(tester, until: () => shows('1 stamp saved'));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('batch-done'))),
    );
    await tester.pumpAndSettle();
    expect(store.entries.single.series, 'one');
  });

  testWidgets('when nothing is found the stamps are cropped by hand', (
    tester,
  ) async {
    await open(tester, [[]]);
    await takePhoto(tester);
    expect(find.byType(DetectedStampsPage), findsNothing);
    expect(
      find.text("Couldn't find any stamps, crop them by hand"),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Crop the stamp'), findsOneWidget);
    await pumpUntil(tester, () => cropReady(tester));
    await tester.runAsync(() => tester.tap(find.text('Use crop')));
    await settleReal(tester, until: () => shows('New stamp'));
    await tester.enterText(find.widgetWithText(TextField, 'Series'), 'hand');
    await tester.pump();
    await save(tester);
    await settleReal(tester, until: () => shows('Crop another stamp'));
    expect(store.entries.single.series, 'hand');
    await tester.runAsync(() => tester.tap(find.text('Done')));
    await settleReal(
      tester,
      until: () => find.byType(CropPage).evaluate().isEmpty,
    );
    expect(find.byType(CropPage), findsNothing);
  });

  testWidgets('a phone that cannot look says why and offers the crop', (
    tester,
  ) async {
    await open(tester, [null], error: 'still downloading');
    await takePhoto(tester);
    expect(
      find.textContaining('still downloading'),
      findsOneWidget,
      reason: 'the reason is shown',
    );
    expect(find.text('Crop the stamp'), findsOneWidget);
  });

  testWidgets('Crop by hand leaves the found boxes and opens the crop', (
    tester,
  ) async {
    await open(tester, [
      [_left],
    ]);
    await takePhoto(tester);
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('by-hand')).evaluate().isNotEmpty,
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('by-hand'))),
    );
    await pumpUntil(tester, () => find.byType(CropPage).evaluate().isNotEmpty);
    expect(find.text('Crop the stamp'), findsOneWidget);
    expect(store.entries, isEmpty);
  });

  testWidgets('another photo keeps the event, and every photo is tidied up', (
    tester,
  ) async {
    final photos = await open(tester, [
      [_middle],
      [_left],
    ]);
    await takePhoto(tester);
    await useFound(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Series'),
      'JR West eki',
    );
    await tester.pump();
    await save(tester);
    await settleReal(tester, until: () => shows('1 stamp saved'));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('batch-another'))),
    );
    await settleReal(
      tester,
      until: () =>
          find.byKey(const ValueKey('source-camera')).evaluate().isNotEmpty,
    );
    await takePhoto(tester);
    await useFound(tester);
    expect(seriesText(tester), 'JR West eki');
    await save(tester);
    await settleReal(tester, until: () => shows('2 stamps saved'));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('batch-done'))),
    );
    await tester.pumpAndSettle();

    expect(photos.taken, hasLength(2));
    expect(photos.taken.every((f) => !f.existsSync()), isTrue);
    expect(store.entries, hasLength(2));
    expect(store.entries.map((e) => e.time).toSet(), hasLength(1));
  });

  testWidgets('cancelling the photo opens nothing', (tester) async {
    await open(tester, [
      [_middle],
    ], cancel: true);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('source-camera'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsNothing);
    expect(find.byType(DetectedStampsPage), findsNothing);
    expect(store.entries, isEmpty);
  });

  testWidgets('discarding a new stamp removes its image', (tester) async {
    await open(tester, [
      [_middle],
    ]);
    await takePhoto(tester);
    await useFound(tester);
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
    await settleReal(
      tester,
      until: () => find.byType(PostPage).evaluate().isEmpty,
    );
    expect(year.listSync().where((f) => f.path.endsWith('.png')), isEmpty);
    expect(store.entries, isEmpty);
  });

  testWidgets('removing the background starts on, and size is saved', (
    tester,
  ) async {
    await open(tester, [
      [_middle],
    ]);
    await takePhoto(tester);
    await useFound(tester);
    final blend = find.byKey(const ValueKey('blend-switch'));
    expect(tester.widget<SwitchListTile>(blend).value, isTrue);
    expect(find.text('Paper colour'), findsNothing);
    final large = find.descendant(
      of: find.byKey(const ValueKey('size-choice')),
      matching: find.text('Large'),
    );
    await tester.ensureVisible(large);
    await tester.pump();
    await tester.tap(large);
    await tester.pump();
    await save(tester);
    await settleReal(tester, until: () => shows('1 stamp saved'));
    final saved = store.entries.single;
    expect(saved.blend, isTrue);
    expect(saved.size, sizeLarge);
  });

  testWidgets('the series field lists the recent series, newest first', (
    tester,
  ) async {
    Entry older(String id, String series, int day) => Entry(
      id: id,
      kind: kindStamp,
      author: 'me@x.com',
      time: DateTime.utc(2026, 10, day, 12),
      utcOffsetMinutes: 0,
      series: series,
      updated: DateTime.utc(2026, 10, day, 12),
    );
    await open(
      tester,
      [
        [_middle],
      ],
      existing: [
        older('20261001-120000-aaaa', 'Kintetsu', 1),
        older('20261012-120000-bbbb', 'JR West eki', 12),
        older('20261008-120000-cccc', '100 Castles', 8),
      ],
    );
    await takePhoto(tester);
    await useFound(tester);
    expect(find.byKey(const ValueKey('series-list')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('series-field')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('series-field')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final names = ['JR West eki', '100 Castles', 'Kintetsu'];
    final tops = [
      for (final n in names)
        tester.getTopLeft(find.byKey(ValueKey('series-$n'))).dy,
    ];
    expect(tops, [...tops]..sort(), reason: 'most recent at the top');
    expect(find.text('1 item · 12 Oct 2026'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('series-field')), 'cast');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('series-100 Castles')), findsOneWidget);
    expect(find.byKey(const ValueKey('series-Kintetsu')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('series-100 Castles')));
    await tester.pump();
    expect(seriesText(tester), '100 Castles');
    expect(find.byKey(const ValueKey('series-list')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('series-dropdown')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('series-dropdown')));
    await tester.pump();
    expect(find.byKey(const ValueKey('series-Kintetsu')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('with the keyboard up the page and the series list both scroll', (
    tester,
  ) async {
    Entry made(int i) => Entry(
      id: '202610${i.toString().padLeft(2, '0')}-120000-aa$i',
      kind: kindStamp,
      author: 'me@x.com',
      time: DateTime.utc(2026, 10, i, 12),
      utcOffsetMinutes: 0,
      series: 'Series $i',
      updated: DateTime.utc(2026, 10, i, 12),
    );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await open(
      tester,
      [
        [_middle],
      ],
      existing: [for (var i = 1; i <= 14; i++) made(i)],
    );
    await takePhoto(tester);
    await useFound(tester);

    final view = tester.view;
    final screen = view.physicalSize.height / view.devicePixelRatio;
    final keyboard = screen * 0.45;
    await tester.ensureVisible(find.byKey(const ValueKey('series-field')));
    await tester.pump();
    double below() =>
        tester.getTopLeft(find.text('Add location')).dy -
        tester.getTopLeft(find.byKey(const ValueKey('series-field'))).dy;
    final gap = below();
    await tester.tap(find.byKey(const ValueKey('series-field')));
    await tester.pump();
    view.viewInsets = FakeViewPadding(bottom: keyboard * view.devicePixelRatio);
    addTearDown(view.resetViewInsets);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final list = find.byKey(const ValueKey('series-list'));
    final visibleBottom = screen - keyboard;
    expect(tester.getTopLeft(list).dy, lessThan(visibleBottom));
    expect(find.byKey(const ValueKey('series-Series 1')), findsNothing);
    expect(
      below(),
      gap,
      reason: 'the list floats over the page, not pushes it',
    );

    final before = tester.getTopLeft(list).dy;
    await tester.drag(
      find.byKey(const ValueKey('series-Series 13')),
      const Offset(0, -900),
    );
    await tester.pump();
    expect(tester.getTopLeft(list).dy, before, reason: 'the list scrolled');
    expect(find.byKey(const ValueKey('series-Series 1')), findsOneWidget);

    await tester.dragFrom(
      Offset(8, tester.getTopLeft(list).dy - 20),
      const Offset(0, -120),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(list).dy, lessThan(before), reason: 'page moved');
    expect(find.byKey(const ValueKey('series-list')), findsOneWidget);
  });

  testWidgets('with the keyboard up the tag strip stays above it', (
    tester,
  ) async {
    Entry made(int i) => Entry(
      id: '202610${i.toString().padLeft(2, '0')}-120000-bb$i',
      kind: kindStamp,
      author: 'me@x.com',
      time: DateTime.utc(2026, 10, i, 12),
      utcOffsetMinutes: 0,
      series: 'Series $i',
      tags: ['t$i'],
      updated: DateTime.utc(2026, 10, i, 12),
    );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await open(
      tester,
      [
        [_middle],
      ],
      existing: [for (var i = 1; i <= 6; i++) made(i)],
    );
    await takePhoto(tester);
    await useFound(tester);

    final view = tester.view;
    final screen = view.physicalSize.height / view.devicePixelRatio;
    final keyboard = screen * 0.45;
    final field = find.widgetWithText(TextField, '+ tag');
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    view.viewInsets = FakeViewPadding(bottom: keyboard * view.devicePixelRatio);
    addTearDown(view.resetViewInsets);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final strip = find.byKey(const ValueKey('tag-strip'));
    expect(
      tester.getBottomLeft(strip).dy,
      lessThanOrEqualTo(screen - keyboard),
    );
    expect(tester.getTopLeft(field).dy, lessThan(tester.getTopLeft(strip).dy));
  });
}
