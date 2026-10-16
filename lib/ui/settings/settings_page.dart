import 'package:flutter/material.dart';

import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';
import '../app/store_scope.dart';
import 'account_actions.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final JournalStore _store;
  late final TextEditingController _email;
  final _emailFocus = FocusNode();
  bool _authBusy = false;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    final s = _store.settings;
    _email = TextEditingController(text: s.me);
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _store.settings;
    final email = _email.text.trim();
    if (email.isEmpty || email == current.me) return;
    await _store.updateSettings(
      AppSettings(
        me: email,
        driveFolderId: current.driveFolderId,
        downloadMedia: current.downloadMedia,
      ),
    );
  }

  Future<void> _signIn(AuthService auth) async {
    if (_authBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _authBusy = true);
    final ok = await signInAndRemember(_store, auth);
    if (!mounted) return;
    setState(() => _authBusy = false);
    if (ok) {
      // Otherwise the next _save() writes the old text back.
      _email.text = _store.settings.me;
    }
    final problem = auth.error;
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _signOut(AuthService auth) async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    await signOutAndForget(_store, auth);
    if (mounted) setState(() => _authBusy = false);
  }

  Widget _googleAccount(ThemeData theme) {
    final auth = widget.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final error = auth.error;
        final Widget account;
        if (!auth.configured) {
          account = const ListTile(
            enabled: false,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.login),
            title: Text(
              'Google sign-in not configured yet '
              '(Web client ID missing in lib/config.dart)',
            ),
          );
        } else if (auth.signedIn) {
          account = ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: Text('Signed in as ${auth.email}'),
            trailing: TextButton(
              onPressed: _authBusy ? null : () => _signOut(auth),
              child: const Text('Sign out'),
            ),
          );
        } else {
          account = Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _authBusy ? null : () => _signIn(auth),
              icon: _authBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            account,
            if (auth.configured && error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _section(theme, 'You'),
            TextField(
              controller: _email,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Your email',
                helperText: 'Used as the author of your posts',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            _section(theme, 'Google account'),
            _googleAccount(theme),
            const SizedBox(height: 24),
            _section(theme, 'This phone'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Local journal folder'),
              subtitle: SelectableText(_store.root.path),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
