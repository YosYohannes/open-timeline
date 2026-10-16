import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/main.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/google_auth.dart';
import 'package:open_timeline/sync/sync_service.dart';

void main() {
  testWidgets('Sync without a client ID explains why and offers Settings', (
    tester,
  ) async {
    late JournalStore store;
    await tester.runAsync(() async {
      store = JournalStore(
        Directory.systemTemp.createTempSync('open_timeline_syncui_'),
      );
      await store.load();
      await store.updateSettings(AppSettings(me: 'me@example.com'));
    });
    final auth = AuthService(webClientId: '');

    await tester.pumpWidget(
      OpenTimelineApp(
        store: store,
        auth: auth,
        sync: SyncService(store, auth, webClientId: ''),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Google sign-in is not set up'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Shared Drive folder (link or ID)'), findsOneWidget);
    expect(find.text('Last sync: Never'), findsOneWidget);
  });
}
