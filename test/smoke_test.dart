import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/main.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/ui/app/app_title.dart';
import 'package:open_timeline/sync/google_auth.dart';
import 'package:open_timeline/sync/sync_service.dart';

void main() {
  testWidgets('app builds and shows the empty Timeline', (
    WidgetTester tester,
  ) async {
    late JournalStore store;
    // Real file IO has to run outside the fake-async zone of testWidgets.
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_test'),
      );
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@example.com'));
    });

    final auth = AuthService(webClientId: '');
    await tester.pumpWidget(
      OpenTimelineApp(store: store, auth: auth, sync: SyncService(store, auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text(kAppTitle), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.textContaining('Tap the + button'), findsOneWidget);
  });

  testWidgets(
    'the + button offers a post or a stamp scan, and the filter has a Collection view',
    (WidgetTester tester) async {
      late JournalStore store;
      await tester.runAsync(() async {
        store = JournalStore(
          Directory.systemTemp.createTempSync('open_timeline_test'),
        );
        await store.load();
        await store.updateSettings(AppSettings(me: 'me@example.com'));
      });
      final auth = AuthService(webClientId: '');
      await tester.pumpWidget(
        OpenTimelineApp(
          store: store,
          auth: auth,
          sync: SyncService(store, auth),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New'));
      await tester.pumpAndSettle();
      expect(find.text('New post'), findsOneWidget);
      expect(find.text('Scan a stamp'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Collection'), findsOneWidget);
      await tester.tap(find.text('Collection'));
      await tester.pumpAndSettle();
      expect(find.text('Clear'), findsOneWidget);
    },
  );
}
