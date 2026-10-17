import 'package:flutter/material.dart';

import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';
import '../../sync/sync_service.dart';
import '../../update/update_check.dart';
import '../app/app_title.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../settings/account_actions.dart';
import '../settings/settings_page.dart';
import '../stamp/stamp_scan.dart';
import 'calendar_page.dart';
import 'filter_sheet.dart';
import 'filters.dart';
import 'map_page.dart';
import 'timeline_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.auth,
    required this.sync,
    this.updater,
  });

  final AuthService auth;
  final SyncService sync;
  final UpdateChecker? updater;

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
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askForEmailIfNeeded();
      _checkForUpdate();
    });
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
    await store.updateSettings(s.copyWith(me: email));
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('New post'),
              onTap: () {
                Navigator.pop(ctx);
                newEntry(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan a stamp'),
              subtitle: const Text('Add it to your collection'),
              onTap: () {
                Navigator.pop(ctx);
                newStamp(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    final updater = widget.updater;
    if (updater == null || !mounted) return;
    if (!StoreScope.read(context).settings.checkForUpdates) return;
    final found = await updater.check();
    if (found != null && mounted) setState(() => _update = found);
  }

  Widget _updateBanner(UpdateInfo update) => MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text('Version ${update.version} is available'),
    actions: [
      TextButton(
        onPressed: () => setState(() => _update = null),
        child: const Text('Later'),
      ),
      TextButton(
        onPressed: () => widget.updater?.platform.openUrl(update.url),
        child: const Text('Update'),
      ),
    ],
  );

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(auth: widget.auth, sync: widget.sync),
      ),
    );
  }

  Future<void> _runSync() async {
    final store = StoreScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final r = await widget.sync.sync();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (r.ok) {
      final conflicts = r.conflicts > 0
          ? ' · ${r.conflicts} conflict(s) – look for ⚠'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('Synced · ↑${r.uploaded} ↓${r.downloaded}$conflicts'),
        ),
      );
      return;
    }
    final needsSettings =
        !widget.auth.configured ||
        !widget.auth.signedIn ||
        (store.settings.driveFolderId ?? '').trim().isEmpty;
    messenger.showSnackBar(
      SnackBar(
        content: Text(r.errors.first),
        duration: const Duration(seconds: 10),
        action: needsSettings
            ? SnackBarAction(label: 'Settings', onPressed: _openSettings)
            : SnackBarAction(
                label: 'Details',
                onPressed: () => _showSyncErrors(r.errors),
              ),
      ),
    );
  }

  void _showSyncErrors(List<String> errors) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync problems'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText('• $e'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _syncButton(ThemeData theme, JournalStore store) {
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        if (widget.sync.running) {
          return const IconButton(
            tooltip: 'Syncing…',
            onPressed: null,
            icon: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        return IconButton(
          tooltip: 'Sync',
          icon: Badge(
            smallSize: 8,
            backgroundColor: theme.colorScheme.primary,
            isLabelVisible: store.dirtyCount > 0,
            child: const Icon(Icons.sync),
          ),
          onPressed: _runSync,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreScope.of(context);

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
            : const Text(kAppTitle),
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
            icon: Badge(
              smallSize: 8,
              backgroundColor: theme.colorScheme.primary,
              isLabelVisible: hasSheetFilters(_filter),
              child: const Icon(Icons.filter_alt_outlined),
            ),
            tooltip: 'Filters',
            onPressed: () => showFilterSheet(context, _filter),
          ),
          _syncButton(theme, store),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_update != null) _updateBanner(_update!),
          Expanded(
            child: IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: [
                TimelinePage(filter: _filter),
                CalendarPage(filter: _filter),
                if (_mapVisited)
                  MapPage(filter: _filter, active: _tab == 2)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New',
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          if (i == 2) _mapVisited = true;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_timeline_outlined),
            selectedIcon: Icon(Icons.view_timeline),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
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
            'Posts you write are marked with your email, so everyone sharing '
            'this diary can tell them apart. You can change it later in Settings.',
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
