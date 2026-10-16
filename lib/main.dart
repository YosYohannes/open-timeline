import 'dart:async';

import 'package:flutter/material.dart';

import 'store/journal_store.dart';
import 'sync/google_auth.dart';
import 'ui/app/store_scope.dart';
import 'ui/home/home_page.dart';
import 'ui/settings/account_actions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await JournalStore.openDefault();
  final auth = AuthService();
  runApp(OpenTimelineApp(store: store, auth: auth));
  // Silent sign-in only after a previous sign-in; otherwise the plugin may pop up the account chooser.
  unawaited(auth.init(attemptSilent: hasSignedInBefore(store)));
}

class OpenTimelineApp extends StatelessWidget {
  const OpenTimelineApp({super.key, required this.store, required this.auth});

  final JournalStore store;
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Open Timeline',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: HomePage(auth: auth),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F7D6E),
        brightness: brightness,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
    );
  }
}
