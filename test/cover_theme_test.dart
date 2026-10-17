import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/countries.dart';
import 'package:open_timeline/ui/booklet/cover_theme.dart';

double _luma(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

void main() {
  test('every themed country is a real country with a stripe band', () {
    expect(coverThemeCount, greaterThan(40));
    for (final code in kCountries.keys.where(hasCoverTheme)) {
      final t = coverThemeFor(code);
      expect(t.band, isNotEmpty, reason: code);
      expect(t.band.length, lessThanOrEqualTo(4), reason: code);
    }
    for (final code in ['JP', 'TW', 'DE', 'SG', 'US', 'GB', 'FR']) {
      expect(hasCoverTheme(code), isTrue, reason: code);
    }
  });

  test('the title is readable on the cover paper', () {
    for (final code in kCountries.keys.where(hasCoverTheme)) {
      final t = coverThemeFor(code);
      expect(
        (_luma(t.ink) - _luma(t.paper)).abs(),
        greaterThan(0.35),
        reason: code,
      );
    }
    final plain = coverThemeFor(null);
    expect((_luma(plain.ink) - _luma(plain.paper)).abs(), greaterThan(0.25));
  });

  test('a country without a theme gets the same plain paper every time', () {
    final a = coverThemeFor('AD');
    final b = coverThemeFor('AD');
    expect(a.paper, b.paper);
    expect(a.band, [const Color(0xFF55585A)]);
    expect(coverThemeFor(null).paper, const Color(0xFFC79F73));
  });

  test('Japan is red paper with white lettering', () {
    final t = coverThemeFor('JP');
    expect(t.paper, const Color(0xFF7A1423));
    expect(t.ink, const Color(0xFFF4EFE6));
  });
}
