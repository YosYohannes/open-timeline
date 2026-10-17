import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';
import '../../sync/sync_service.dart';
import '../../update/update_check.dart';
import '../app/store_scope.dart';
import 'account_actions.dart';
import 'author_colors.dart';
import 'tags_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.auth,
    required this.sync,
    this.platform,
  });

  final AuthService auth;
  final SyncService sync;
  final AppPlatform? platform;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final JournalStore _store;
  late final TextEditingController _email;
  late final TextEditingController _folder;
  String? _folderError;
  late bool _editingFolder;
  final _emailFocus = FocusNode();
  bool _authBusy = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    (widget.platform ?? PlatformApp()).installedVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
    _store = StoreScope.read(context);
    final s = _store.settings;
    _email = TextEditingController(text: s.me);
    _folder = TextEditingController(text: s.driveFolderId ?? '');
    _editingFolder = s.driveFolderId == null;
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _folder.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _saveFolder() async {
    final text = _folder.text.trim();
    final id = parseDriveFolderId(text);
    if (text.isNotEmpty && id == null) {
      setState(() => _folderError = 'Not a Drive folder link or ID');
      return;
    }
    setState(() {
      _folderError = null;
      if (id != null) _editingFolder = false;
    });
    if (id != null) _folder.text = id;
    final current = _store.settings;
    if (id == current.driveFolderId) return;
    await _store.updateSettings(current.copyWith(driveFolderId: id));
  }

  String _shortId(String id) => id.length <= 12
      ? id
      : '${id.substring(0, 6)}…${id.substring(id.length - 4)}';

  Widget _folderField() {
    final saved = _store.settings.driveFolderId;
    if (!_editingFolder && saved != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.folder_outlined),
        title: const Text('Shared Drive folder'),
        subtitle: Text(_shortId(saved)),
        trailing: TextButton(
          onPressed: () => setState(() => _editingFolder = true),
          child: const Text('Change'),
        ),
      );
    }
    return TextField(
      controller: _folder,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: 'Shared Drive folder (link or ID)',
        errorText: _folderError,
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (saved != null)
              TextButton(
                onPressed: () => setState(() {
                  _folder.text = saved;
                  _folderError = null;
                  _editingFolder = false;
                }),
                child: const Text('Cancel'),
              ),
            TextButton(onPressed: _saveFolder, child: const Text('Set')),
          ],
        ),
      ),
      onSubmitted: (_) => _saveFolder(),
    );
  }

  Future<void> _save() async {
    final current = _store.settings;
    final email = _email.text.trim();
    if (email.isEmpty || email == current.me) return;
    await _store.updateSettings(current.copyWith(me: email));
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
        if (didPop) {
          _save();
          _saveFolder();
        }
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
            _section(theme, 'Google Drive'),
            _folderField(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Download photos & videos when syncing'),
              value: _store.settings.downloadMedia,
              onChanged: (v) async {
                await _store.updateSettings(
                  _store.settings.copyWith(downloadMedia: v),
                );
                if (mounted) setState(() {});
              },
            ),
            ListenableBuilder(
              listenable: widget.sync,
              builder: (context, _) {
                final at = widget.sync.lastAt;
                final r = widget.sync.last;
                final when = at == null
                    ? 'Never'
                    : '${DateFormat('d MMM HH:mm').format(at)}${r == null ? '' : ' · ↑${r.uploaded} ↓${r.downloaded}'}';
                return Text(
                  'Last sync: $when',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
            const SizedBox(height: 24),
            _section(theme, 'Your colour'),
            const MyColorPicker(),
            const SizedBox(height: 24),
            _section(theme, 'Tags'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Rename, merge or delete tags'),
              subtitle: Text(
                _store.allTags.length == 1
                    ? '1 tag'
                    : '${_store.allTags.length} tags',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(builder: (_) => const TagsPage()),
                  )
                  .then((_) {
                    if (mounted) setState(() {});
                  }),
            ),
            const SizedBox(height: 24),
            _section(theme, 'Updates'),
            if (_version != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                subtitle: Text(_version!),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check for a new version'),
              subtitle: const Text('Asks GitHub once when the app opens'),
              value: _store.settings.checkForUpdates,
              onChanged: (v) async {
                await _store.updateSettings(
                  _store.settings.copyWith(checkForUpdates: v),
                );
                if (mounted) setState(() {});
              },
            ),
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
