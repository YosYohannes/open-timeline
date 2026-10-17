import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/ui/stamp/paper_picker.dart';

import 'pump_support.dart';

void main() {
  test('a sampled colour is the average of the pixels around the tap', () {
    final rgba = Uint8List(8 * 8 * 4);
    for (var i = 0; i < 64; i++) {
      rgba[i * 4] = 200;
      rgba[i * 4 + 1] = 100;
      rgba[i * 4 + 2] = 50;
      rgba[i * 4 + 3] = 255;
    }
    final c = sampleColor(rgba, 8, 8, 0, 0);
    expect(hexOf(c), '#C86432');
    expect(hexOf(sampleColor(rgba, 8, 8, 7, 7)), '#C86432');
  });

  test('hexOf pads and upper-cases', () {
    expect(hexOf(const Color(0xFF0A0B0C)), '#0A0B0C');
    expect(hexOf(const Color(0xFFFFFFFF)), '#FFFFFF');
  });

  testWidgets('tapping the picture picks that colour', (tester) async {
    late File file;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 200, 200),
        Paint()..color = const Color(0xFFF1E6C8),
      );
      final img = await rec.endRecording().toImage(200, 200);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      file = File('${Directory.systemTemp.createTempSync('paper_').path}/p.png')
        ..writeAsBytesSync(data!.buffer.asUint8List());
    });
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context)
                .push<String>(
                  MaterialPageRoute(
                    builder: (_) => PaperPickerPage(file: file),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('paper-area')).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('paper-use')))
          .onPressed,
      isNull,
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('paper-area'))),
    );
    await tester.pump();
    expect(find.text('Paper colour #F1E6C8'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-use')));
    await tester.pumpAndSettle();
    expect(result, '#F1E6C8');
  });

  testWidgets('Automatic gives an empty string', (tester) async {
    late File file;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 50, 50),
        Paint()..color = Colors.white,
      );
      final img = await rec.endRecording().toImage(50, 50);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      file = File('${Directory.systemTemp.createTempSync('paper_').path}/p.png')
        ..writeAsBytesSync(data!.buffer.asUint8List());
    });
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context)
                .push<String>(
                  MaterialPageRoute(
                    builder: (_) => PaperPickerPage(file: file),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('paper-auto')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(result, '');
  });
}
