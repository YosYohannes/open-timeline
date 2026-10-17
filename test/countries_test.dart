import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/countries.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/stamp/country_picker.dart';

void main() {
  test('every code is two capital letters and has a name', () {
    expect(kCountries.length, greaterThan(240));
    for (final e in kCountries.entries) {
      expect(RegExp(r'^[A-Z]{2}$').hasMatch(e.key), isTrue, reason: e.key);
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
    expect(kCountries.values.toSet().length, kCountries.length);
  });

  test('names, flags and labels', () {
    expect(countryName('JP'), 'Japan');
    expect(countryName('TW'), 'Taiwan');
    expect(countryName('ZZ'), 'ZZ');
    expect(countryFlag('JP'), '🇯🇵');
    expect(countryFlag('jp'), '');
    expect(countryLabel('GB'), '🇬🇧 United Kingdom');
    expect(isKnownCountry('JP'), isTrue);
    expect(isKnownCountry('UK'), isFalse);
    expect(isKnownCountry(null), isFalse);
  });

  test('usedCountries lists the most used first, posts included', () async {
    final dir = Directory.systemTemp.createTempSync('cty_');
    final store = JournalStore(dir);
    await store.load();
    Entry stamp(String id, String? c) => Entry(
      id: id,
      kind: kindStamp,
      author: 'a@x',
      time: DateTime.utc(2026, 10, 17),
      utcOffsetMinutes: 0,
      country: c,
      media: ['${id}_aaaa.png'],
      updated: DateTime.utc(2026, 10, 17),
    );
    await store.save(stamp('20261017-100000-aaaa', 'TW'));
    await store.save(stamp('20261017-110000-bbbb', 'JP'));
    await store.save(stamp('20261017-120000-cccc', 'JP'));
    await store.save(stamp('20261017-130000-dddd', null));
    for (final id in ['20261018-100000-eeee', '20261018-110000-ffff']) {
      await store.save(
        Entry(
          id: id,
          author: 'a@x',
          time: DateTime.utc(2026, 10, 18),
          utcOffsetMinutes: 0,
          text: 'hi',
          country: 'TW',
          updated: DateTime.utc(2026, 10, 18),
        ),
      );
    }
    expect(store.usedCountries, ['TW', 'JP']);
    store.dispose();
    dir.deleteSync(recursive: true);
  });

  group('picker', () {
    Future<({String? code})?> open(
      WidgetTester tester, {
      String? selected,
      List<String> used = const [],
    }) async {
      ({String? code})? result;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showCountryPicker(
                  context,
                  selected: selected,
                  used: used,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      return result;
    }

    testWidgets('search narrows by name or code and a tap returns the code', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('No country'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'korea');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-KR')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-KP')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-JP')), findsNothing);
      await tester.enterText(find.byType(TextField), 'tw');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-TW')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No country matches'), findsOneWidget);
    });

    testWidgets('countries used before are offered first', (tester) async {
      await open(tester, used: ['TW', 'JP']);
      expect(find.text('Used before'), findsOneWidget);
      expect(find.text('All countries'), findsOneWidget);
      expect(find.byKey(const ValueKey('country-TW')), findsOneWidget);
    });
  });
}
