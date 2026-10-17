import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/countries.dart';
import 'package:open_timeline/ui/booklet/flag_spine.dart';

const _w = 60;
const _h = 400;

Future<Uint8List> render(WidgetTester tester, String? country) async {
  late Uint8List pixels;
  await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    paintFlagSpine(Canvas(rec), Size(_w.toDouble(), _h.toDouble()), country);
    final img = await rec.endRecording().toImage(_w, _h);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    pixels = data!.buffer.asUint8List();
  });
  return pixels;
}

int pixel(Uint8List p, int x, int y) {
  final i = (y * _w + x) * 4;
  return (p[i + 3] << 24) | (p[i] << 16) | (p[i + 1] << 8) | p[i + 2];
}

void main() {
  test('every drawn flag is a real country', () {
    expect(flagSpineCount, 11);
    for (final code in kCountries.keys.where(hasFlagSpine)) {
      expect(isKnownCountry(code), isTrue, reason: code);
    }
    for (final code in [
      'JP',
      'KR',
      'CN',
      'TW',
      'HK',
      'SG',
      'TH',
      'VN',
      'MY',
      'ID',
      'PH',
    ]) {
      expect(hasFlagSpine(code), isTrue, reason: code);
    }
  });

  testWidgets('every flag paints without error and covers the whole spine', (
    tester,
  ) async {
    for (final code in kCountries.keys.where(hasFlagSpine)) {
      final p = await render(tester, code);
      for (final y in [0, _h ~/ 2, _h - 1]) {
        for (final x in [0, _w ~/ 2, _w - 1]) {
          expect(p[(y * _w + x) * 4 + 3], 255, reason: '$code at $x,$y');
        }
      }
    }
  });

  testWidgets('Japan is a white spine with the red circle in the middle', (
    tester,
  ) async {
    final p = await render(tester, 'JP');
    expect(pixel(p, 3, 5), 0xFFFFFFFF);
    expect(pixel(p, 3, _h - 5), 0xFFFFFFFF);
    expect(pixel(p, _w ~/ 2, _h ~/ 2), 0xFFBC002D);
  });

  testWidgets('Thailand: red, white and the wide blue band, left to right', (
    tester,
  ) async {
    final p = await render(tester, 'TH');
    expect(pixel(p, 5, 200), 0xFFA51931);
    expect(pixel(p, 15, 200), 0xFFF4F5F8);
    expect(pixel(p, _w ~/ 2, 200), 0xFF2D2A4A);
    expect(pixel(p, _w - 5, 200), 0xFFA51931);
  });

  testWidgets('China: the stars sit together at the bottom of a red spine', (
    tester,
  ) async {
    final p = await render(tester, 'CN');
    expect(pixel(p, 3, 5), 0xFFDE2910);
    expect(pixel(p, _w - 3, _h ~/ 2), 0xFFDE2910);
    var starRows = 0;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        if (pixel(p, x, y) == 0xFFFFDE00) {
          starRows = y > starRows ? y : starRows;
          expect(y, greaterThan(_h - 5 * _w ~/ 2));
        }
      }
    }
    expect(starRows, greaterThan(0));
  });

  testWidgets('Singapore: red left, white right, crescent near the bottom', (
    tester,
  ) async {
    final p = await render(tester, 'SG');
    expect(pixel(p, 5, 10), 0xFFEF3340);
    expect(pixel(p, _w - 5, 10), 0xFFFFFFFF);
    var whiteInRedHalf = 0;
    for (var y = 0; y < _h; y++) {
      if (pixel(p, _w ~/ 4, y) == 0xFFFFFFFF) whiteInRedHalf++;
    }
    expect(whiteInRedHalf, greaterThan(0));
    for (var y = 0; y < _h ~/ 3; y++) {
      expect(
        pixel(p, 4, y),
        0xFFEF3340,
        reason: 'top third is plain red at y=$y',
      );
    }
  });

  testWidgets('Taiwan: the blue corner is at the bottom left', (tester) async {
    final p = await render(tester, 'TW');
    expect(pixel(p, 4, _h - 4), 0xFF000095);
    expect(pixel(p, 4, 10), 0xFFFE0000);
    expect(pixel(p, _w - 4, _h - 4), 0xFFFE0000);
  });

  testWidgets(
    'a country without a flag, and no country, get the plain grey band',
    (tester) async {
      expect(hasFlagSpine('AD'), isFalse);
      for (final country in ['AD', null]) {
        final p = await render(tester, country);
        expect(pixel(p, 10, 10), 0xFF55585A);
        expect(pixel(p, 30, 300), 0xFF55585A);
      }
    },
  );
}
