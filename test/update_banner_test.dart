import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_timeline/main.dart';
import 'package:open_timeline/store/journal_store.dart';
import 'package:open_timeline/sync/google_auth.dart';
import 'package:open_timeline/sync/sync_service.dart';
import 'package:open_timeline/update/update_check.dart';

import 'update_check_test.dart' show FakePlatform;

void main() {
  late JournalStore store;
  late FakePlatform platform;

  Future<void> pumpApp(WidgetTester tester, {bool check = true}) async {
    await tester.runAsync(() async {
      store = JournalStore(Directory.systemTemp.createTempSync('update_'));
      await store.load();
      await store.updateSettings(
        AppSettings(me: 'me@x.com', checkForUpdates: check),
      );
    });
    platform = FakePlatform('0.2.0');
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'tag_name': 'v0.3.0',
          'assets': [
            {'browser_download_url': 'https://example.com/ot.apk'},
          ],
        }),
        200,
      ),
    );
    final auth = AuthService(webClientId: '');
    await tester.pumpWidget(
      OpenTimelineApp(
        store: store,
        auth: auth,
        sync: SyncService(store, auth),
        updater: UpdateChecker(platform: platform, client: client),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a newer release shows a banner with Update and Later', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Version 0.3.0 is available'), findsOneWidget);

    await tester.tap(find.text('Update'));
    expect(platform.opened, ['https://example.com/ot.apk']);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets(
    'switching the check off in Settings means no request and no banner',
    (tester) async {
      await pumpApp(tester, check: false);
      expect(find.textContaining('is available'), findsNothing);
    },
  );
}
