import 'dart:async';

import 'package:flutter/material.dart';

import 'store/journal_store.dart';
import 'sync/google_auth.dart';
import 'sync/sync_service.dart';
import 'ui/app/app_title.dart';
import 'ui/app/store_scope.dart';
import 'ui/app/theme.dart';
import 'ui/home/home_page.dart';
import 'ui/settings/account_actions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await JournalStore.openDefault();
  final auth = AuthService()..restore(rememberedGoogleEmail(store));
  runApp(
    OpenTimelineApp(store: store, auth: auth, sync: SyncService(store, auth)),
  );
  unawaited(auth.init());
}

class OpenTimelineApp extends StatelessWidget {
  const OpenTimelineApp({
    super.key,
    required this.store,
    required this.auth,
    required this.sync,
  });

  final JournalStore store;
  final AuthService auth;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: kAppTitle,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: HomePage(auth: auth, sync: sync),
      ),
    );
  }
}
