import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;

import '../config.dart';
import '../store/journal_store.dart';
import 'drive_client.dart';
import 'google_auth.dart';
import 'keep_alive.dart';
import 'sync_engine.dart';

export 'sync_engine.dart' show SyncResult;

/// What the UI talks to: one "Sync" action, plus state to show while it runs and after.
/// [sync] never throws; every problem ends up in the returned [SyncResult.errors].
class SyncService extends ChangeNotifier {
  SyncService(
    this.store,
    this.auth, {
    DriveClient Function(DriveApi api)? clientFactory,
    this.webClientId = kGoogleWebClientId,
    KeepAlive? keepAlive,
  }) : _clientFactory = clientFactory ?? GoogleDriveClient.new,
       _keepAlive = keepAlive ?? const NoKeepAlive();

  final JournalStore store;
  final AuthService auth;
  final String webClientId;
  final DriveClient Function(DriveApi api) _clientFactory;
  final KeepAlive _keepAlive;

  bool _running = false;
  SyncResult? _last;
  DateTime? _lastAt;
  Future<SyncResult>? _inflight;

  /// True while a sync is in progress.
  bool get running => _running;

  /// Result of the most recent sync of this app session (null before the first).
  SyncResult? get last => _last;

  /// When the most recent sync attempt that got as far as talking to Drive
  /// finished. Survives app restarts (kept in the store's sync data).
  DateTime? get lastAt {
    if (_lastAt != null) return _lastAt;
    final saved = store.syncData['lastSyncAt'];
    return saved is String ? DateTime.tryParse(saved)?.toLocal() : null;
  }

  /// Runs one sync. A second call while one is running returns the same future.
  Future<SyncResult> sync() {
    final running = _inflight;
    if (running != null) return running;
    _running = true;
    notifyListeners();
    final future = _run().whenComplete(() {
      _running = false;
      _inflight = null;
      notifyListeners();
    });
    _inflight = future;
    return future;
  }

  Future<SyncResult> _run() async {
    await _keepAlive.start();
    try {
      return await _execute();
    } finally {
      await _keepAlive.stop();
    }
  }

  Future<SyncResult> _execute() async {
    SyncResult result;
    var reachedDrive = false;
    try {
      if (webClientId.isEmpty) {
        result = SyncResult.failed(
          'Google sign-in is not set up: kGoogleWebClientId in lib/config.dart is empty.',
        );
      } else if (!auth.signedIn) {
        result = SyncResult.failed(
          'Not signed in to Google. Sign in in Settings first.',
        );
      } else if ((store.settings.driveFolderId ?? '').trim().isEmpty) {
        result = SyncResult.failed(
          'No Drive folder is set. Paste the shared folder link in Settings first.',
        );
      } else {
        final api = await auth.driveApi(interactive: true);
        if (api == null) {
          result = SyncResult.failed(
            auth.error ?? 'Google Drive access is not granted. Sign out and sign in again, and allow access to Drive.',
          );
        } else {
          reachedDrive = true;
          result = await SyncEngine(store, _clientFactory(api)).run();
          if (result.errors.any((e) => e.contains('Drive error 401'))) {
            result.errors.add('Google access expired. Press Sync again.');
            await auth.invalidateToken();
          }
        }
      }
    } catch (e) {
      result = SyncResult.failed('Sync failed: $e');
    }

    _last = result;
    if (reachedDrive) {
      final now = DateTime.now();
      _lastAt = now;
      try {
        store.syncData['lastSyncAt'] = now.toUtc().toIso8601String();
        await store.saveState();
      } catch (_) {}
    }
    return result;
  }
}

/// Extracts a Drive folder id from what a person pastes: a share link such as
/// `https://drive.google.com/drive/folders/<id>?usp=sharing`, a `...open?id=<id>`
/// link, or the bare id. Returns null when nothing looks like an id.
String? parseDriveFolderId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final id = RegExp(r'^[A-Za-z0-9_-]{10,}$');
  if (id.hasMatch(text)) return text;
  final fromPath = RegExp(r'/folders/([A-Za-z0-9_-]{10,})').firstMatch(text);
  if (fromPath != null) return fromPath.group(1);
  final fromQuery = RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(text);
  if (fromQuery != null) return fromQuery.group(1);
  return null;
}
