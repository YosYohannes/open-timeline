import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/ui/stamp/crop_page.dart';

void main() {
  const image = ui.Size(1000, 2000);

  test('a crop stays inside the image', () {
    expect(
      clampCrop(const ui.Rect.fromLTRB(-50, -20, 1200, 2500), image),
      const ui.Rect.fromLTRB(0, 0, 1000, 2000),
    );
  });

  test('a crop cannot shrink below a usable size or flip over', () {
    final r = clampCrop(const ui.Rect.fromLTRB(500, 500, 400, 480), image);
    expect(r.width, greaterThanOrEqualTo(24));
    expect(r.height, greaterThanOrEqualTo(24));
    expect(r.left, lessThan(r.right));
    expect(r.top, lessThan(r.bottom));
  });

  test('a crop inside the image is left alone', () {
    const r = Rect.fromLTRB(100, 200, 600, 900);
    expect(clampCrop(r, image), r);
  });

  test('tiny images still get a valid crop', () {
    final r = clampCrop(
      const ui.Rect.fromLTRB(0, 0, 1, 1),
      const ui.Size(1, 1),
    );
    expect(r, const ui.Rect.fromLTRB(0, 0, 1, 1));
  });

  test('makeSquare keeps the shorter side, centred, inside the image', () {
    final r = makeSquare(const ui.Rect.fromLTRB(100, 100, 700, 400), image);
    expect(r.width, 300);
    expect(r.height, 300);
    expect(r.center, const Offset(400, 250));
    final edge = makeSquare(const ui.Rect.fromLTRB(0, 0, 900, 200), image);
    expect(edge, const ui.Rect.fromLTWH(350, 0, 200, 200));
  });

  test('a square dragged from a corner stays square and inside the image', () {
    final r = squareFromCorner(
      anchor: const Offset(500, 500),
      moved: const Offset(100, 380),
      image: image,
    );
    expect(r.width, r.height);
    expect(r.right, 500);
    expect(r.bottom, 500);
    expect(r.width, 400);

    final clipped = squareFromCorner(
      anchor: const Offset(800, 100),
      moved: const Offset(1500, 900),
      image: image,
    );
    expect(clipped.width, clipped.height);
    expect(clipped.right, lessThanOrEqualTo(1000));
    expect(clipped.width, 200);

    final tiny = squareFromCorner(
      anchor: const Offset(500, 500),
      moved: const Offset(499, 501),
      image: image,
    );
    expect(tiny.width, 24);
    expect(tiny.height, 24);
  });

  group('crop screen', () {
    Future<File> makeImage(WidgetTester tester, int w, int h) async {
      late File file;
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.green,
        );
        final img = await rec.endRecording().toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        file = File(
          '${Directory.systemTemp.createTempSync('crop_').path}/page.png',
        )..writeAsBytesSync(data!.buffer.asUint8List());
      });
      return file;
    }

    Future<Uint8List?> run(
      WidgetTester tester,
      File file,
      Future<void> Function() act,
    ) async {
      Uint8List? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context)
                  .push<Uint8List>(
                    MaterialPageRoute(builder: (_) => CropPage(file: file)),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 20 && find.text('Use crop').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await act();
      await tester.runAsync(() => tester.tap(find.text('Use crop')));
      for (var i = 0; i < 30 && result == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      return result;
    }

    Future<ui.Size> sizeOf(WidgetTester tester, Uint8List png) async {
      late ui.Size s;
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        final f = await codec.getNextFrame();
        s = ui.Size(f.image.width.toDouble(), f.image.height.toDouble());
      });
      return s;
    }

    testWidgets('the default crop is the middle 80 percent', (tester) async {
      final file = await makeImage(tester, 500, 500);
      final bytes = await run(tester, file, () async {});
      expect(await sizeOf(tester, bytes!), const ui.Size(400, 400));
    });

    testWidgets('dragging a corner makes the crop smaller', (tester) async {
      final file = await makeImage(tester, 500, 500);
      final bytes = await run(tester, file, () async {
        final box = tester.getRect(find.byKey(const ValueKey('crop-area')));
        final side = math.min(box.width, box.height) - 32;
        final left = box.center.dx - side / 2 + side * 0.1;
        final top = box.center.dy - side / 2 + side * 0.1;
        await tester.dragFrom(Offset(left, top), const Offset(60, 60));
        await tester.pump();
      });
      final size = await sizeOf(tester, bytes!);
      expect(size.width, lessThan(400));
      expect(size.height, lessThan(400));
    });

    testWidgets('Square makes the crop 1:1 and corners keep it square', (
      tester,
    ) async {
      final file = await makeImage(tester, 600, 400);
      final bytes = await run(tester, file, () async {
        await tester.tap(find.byKey(const ValueKey('square')));
        await tester.pump();
        final box = tester.getRect(find.byKey(const ValueKey('crop-area')));
        final fit = math.min((box.width - 32) / 600, (box.height - 32) / 400);
        final imageW = 600 * fit;
        final imageH = 400 * fit;
        final side = 320 * fit;
        final left = box.center.dx - side / 2;
        final top = box.center.dy - imageH / 2 + (imageH - side) / 2;
        expect(imageW, greaterThan(0));
        await tester.dragFrom(Offset(left, top), const Offset(40, 15));
        await tester.pump();
      });
      final size = await sizeOf(tester, bytes!);
      expect(size.width, size.height);
      expect(size.width, lessThan(320));
    });

    testWidgets('Whole page with Square uses the shorter side', (tester) async {
      final file = await makeImage(tester, 300, 200);
      final bytes = await run(tester, file, () async {
        await tester.tap(find.byKey(const ValueKey('square')));
        await tester.pump();
        await tester.tap(find.text('Whole page'));
        await tester.pump();
      });
      expect(await sizeOf(tester, bytes!), const ui.Size(200, 200));
    });

    testWidgets('Whole page returns the full image', (tester) async {
      final file = await makeImage(tester, 300, 200);
      final bytes = await run(tester, file, () async {
        await tester.tap(find.text('Whole page'));
        await tester.pump();
      });
      expect(await sizeOf(tester, bytes!), const ui.Size(300, 200));
    });
  });
}
