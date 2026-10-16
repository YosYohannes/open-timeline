import 'package:flutter/material.dart';

import 'sync/google_auth.dart';

void main() {
  runApp(OpenTimelineApp(auth: AuthService()));
}

class OpenTimelineApp extends StatelessWidget {
  const OpenTimelineApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Timeline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F7D6E),
      ),
      home: LoginCheckPage(auth: auth),
    );
  }
}

/// Proves the Google Cloud setup (client IDs, signing key, Drive scope) works
/// end to end: sign in, then list a few Drive files.
class LoginCheckPage extends StatefulWidget {
  const LoginCheckPage({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginCheckPage> createState() => _LoginCheckPageState();
}

class _LoginCheckPageState extends State<LoginCheckPage> {
  bool _busy = false;
  String? _driveResult;

  @override
  void initState() {
    super.initState();
    widget.auth.init(attemptSilent: false);
  }

  Future<void> _testDrive() async {
    setState(() {
      _busy = true;
      _driveResult = null;
    });
    final api = await widget.auth.driveApi(interactive: true);
    String result;
    if (api == null) {
      result = widget.auth.error ?? 'Drive access was not granted.';
    } else {
      try {
        final list = await api.files.list(
          pageSize: 5,
          q: 'trashed = false',
          $fields: 'files(name)',
        );
        final names = [for (final f in list.files ?? const []) f.name ?? '?'];
        result = names.isEmpty
            ? 'Drive access works (no files visible).'
            : 'Drive access works. Some of your files:\n${names.join('\n')}';
      } catch (e) {
        result = 'Drive request failed: $e';
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _driveResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return Scaffold(
      appBar: AppBar(title: const Text('Open Timeline')),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!auth.configured)
              const Text(
                'Set kGoogleWebClientId in lib/config.dart, then rebuild.',
              ),
            if (auth.signedIn) ...[
              Text('Signed in as ${auth.email}'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: auth.signOut,
                child: const Text('Sign out'),
              ),
            ] else
              FilledButton.icon(
                onPressed: auth.configured ? auth.signIn : null,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: auth.signedIn && !_busy ? _testDrive : null,
              child: const Text('Test Drive access'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_driveResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(_driveResult!),
              ),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  auth.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
