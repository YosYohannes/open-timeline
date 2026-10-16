import 'package:flutter/material.dart';

import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../settings/account_actions.dart';
import '../settings/settings_page.dart';
import 'filter_bar.dart';
import 'filters.dart';
import 'map_page.dart';
import 'timeline_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.auth});

  final AuthService auth;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final EntryFilter _filter = EntryFilter();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  int _tab = 0;
  bool _mapVisited = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForEmailIfNeeded());
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    _filter.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (_searchController.text != _filter.query) {
      _searchController.text = _filter.query;
    }
    if (mounted) setState(() {});
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (_searching) {
        _searchFocus.requestFocus();
      } else {
        _filter.query = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _askForEmailIfNeeded() async {
    if (!mounted) return;
    final store = StoreScope.read(context);
    if (store.settings.me.trim().isNotEmpty) return;
    final email = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmailDialog(auth: widget.auth),
    );
    if (email == null || !mounted) return;
    final s = store.settings;
    await store.updateSettings(
      AppSettings(
        me: email,
        driveFolderId: s.driveFolderId,
        downloadMedia: s.downloadMedia,
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(auth: widget.auth)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: _searching ? 0 : null,
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Close search',
                onPressed: _toggleSearch,
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search text, places, tags',
                  border: InputBorder.none,
                ),
                style: theme.textTheme.titleMedium,
                onChanged: (v) => _filter.query = v,
              )
            : const Text('Open Timeline'),
        actions: [
          if (!_searching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _toggleSearch,
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear text',
              onPressed: () {
                _searchController.clear();
                _filter.query = '';
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          FilterBar(filter: _filter),
          Expanded(
            child: IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: [
                TimelinePage(filter: _filter),
                if (_mapVisited)
                  MapPage(filter: _filter)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New post',
        onPressed: () => newEntry(context),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          if (i == 1) _mapVisited = true;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_timeline_outlined),
            selectedIcon: Icon(Icons.view_timeline),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
        ],
      ),
    );
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.auth});

  final AuthService auth;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _controller = TextEditingController();
  bool _signingIn = false;
  String? _signInError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  Future<void> _signInWithGoogle() async {
    final auth = widget.auth;
    final store = StoreScope.read(context);
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    final ok = await signInAndRemember(store, auth);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, auth.email);
    } else {
      setState(() {
        _signingIn = false;
        _signInError = auth.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return AlertDialog(
      title: const Text('Welcome'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Posts you write are marked with your email, so you and your partner '
            'can tell them apart. You can change it later in Settings.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Your email',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (_signInError != null) ...[
            const SizedBox(height: 8),
            Text(
              _signInError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (auth.configured)
          TextButton.icon(
            onPressed: _signingIn ? null : _signInWithGoogle,
            icon: _signingIn
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login, size: 18),
            label: const Text('Sign in with Google instead'),
          ),
        FilledButton(
          onPressed: _signingIn || _controller.text.trim().isEmpty
              ? null
              : _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
