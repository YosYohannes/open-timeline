// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as pi;
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/navigation.dart';
import 'package:open_timeline/ui/app/store_scope.dart';
import 'package:open_timeline/ui/post/post_page.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'map_test_support.dart';

class _Platform extends pi.Geocoding with MockPlatformInterfaceMixin {
  _Platform(super.params) : super.implementation();

  static List<pi.Placemark> marks = const [];
  static bool fail = false;

  @override
  Future<List<pi.Location>> locationFromAddress(
    String address, {
    Locale? locale,
  }) async => [
    pi.Location(latitude: 35.0, longitude: 135.7, timestamp: DateTime(2026)),
  ];

  @override
  Future<List<pi.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    Locale? locale,
  }) async {
    if (fail) throw Exception('no geocoder');
    return marks;
  }
}

class _Factory extends pi.GeocodingPlatformFactory
    with MockPlatformInterfaceMixin {
  @override
  pi.Geocoding createGeocoding(pi.GeocodingCreationParams params) =>
      _Platform(params);
}

const _id = '20261016-143205-k3f9';

Entry _entry({String? place, String? country, String kind = kindPost}) => Entry(
  id: _id,
  kind: kind,
  author: 'me@x.com',
  time: DateTime.utc(2026, 10, 16, 12, 32, 5),
  utcOffsetMinutes: 120,
  text: 'hi',
  place: place,
  country: country,
  updated: DateTime.utc(2026, 10, 16, 13),
);

void main() {
  late JournalStore store;

  setUp(() {
    mockPathProvider();
    pi.GeocodingPlatformFactory.instance = _Factory();
    _Platform.fail = false;
    _Platform.marks = const [
      pi.Placemark(
        street: 'Higashishiokoji',
        locality: 'Kyoto',
        isoCountryCode: 'jp',
      ),
    ];
  });

  Future<void> open(WidgetTester tester, Entry e) async {
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('loc_'));
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@x.com'));
      await store.writeSynced(e, dirty: false);
    });
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openEntry(context, _id),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(PostPage), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('location-row')));
    await tester.tap(find.byKey(const ValueKey('location-row')));
    await tester.pumpAndSettle();
  }

  Future<void> tapMap(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FlutterMap));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Finder countryBox() => find.byKey(const ValueKey('country-box'));

  testWidgets('tapping the map fills the country of a post', (tester) async {
    await open(tester, _entry());
    expect(find.text('Not set'), findsOneWidget);
    await tapMap(tester);
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇯🇵 Japan')),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Higashishiokoji, Kyoto'),
      findsOneWidget,
    );
  });

  testWidgets('a place label that is already there does not stop the country', (
    tester,
  ) async {
    await open(tester, _entry(place: 'My label'));
    await tapMap(tester);
    expect(find.widgetWithText(TextField, 'My label'), findsOneWidget);
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇯🇵 Japan')),
      findsOneWidget,
    );
  });

  testWidgets('Search fills the country for a stamp too', (tester) async {
    await open(tester, _entry(kind: kindStamp));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Kyoto Station');
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Search')),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇯🇵 Japan')),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Kyoto Station'), findsOneWidget);
  });

  testWidgets('moving the pin always replaces the country, even a picked one', (
    tester,
  ) async {
    await open(tester, _entry(country: 'TW'));
    await tapMap(tester);
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇯🇵 Japan')),
      findsOneWidget,
    );

    await tester.tap(countryBox());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-TW')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇹🇼 Taiwan')),
      findsOneWidget,
    );

    await tapMap(tester);
    expect(
      find.descendant(of: countryBox(), matching: find.text('🇯🇵 Japan')),
      findsOneWidget,
    );
  });

  testWidgets('a failed lookup says so and leaves the country alone', (
    tester,
  ) async {
    _Platform.fail = true;
    await open(tester, _entry());
    await tapMap(tester);
    expect(
      find.textContaining("Couldn't work out the country"),
      findsOneWidget,
    );
    expect(find.text('Not set'), findsOneWidget);
  });
}
