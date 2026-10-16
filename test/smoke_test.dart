import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/main.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/google_auth.dart';

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

    await tester.pumpWidget(
      OpenTimelineApp(
        store: store,
        auth: AuthService(webClientId: ''),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open Timeline'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.textContaining('Tap the + button'), findsOneWidget);
  });
}
