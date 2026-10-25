import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/entry.dart';
import '../models/entry_format.dart';
import '../store/journal_store.dart';
import 'drive_client.dart';
import 'merge.dart';

/// Outcome of one sync run. Nothing in here is ever thrown: problems end up in [errors].
class SyncResult {
  SyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    List<String>? errors,
  }) : errors = errors ?? [];

  /// A result for a sync that could not even start.
  SyncResult.failed(String message) : this(errors: [message]);

  /// Files written to Drive (posts and media).
  int uploaded;

  /// Files fetched from Drive (posts and media).
  int downloaded;

  /// Posts that have a conflict block on this phone after this sync and did not before.
  int conflicts;

  /// Human-readable problems. The sync continued past each of them.
  final List<String> errors;

  bool get ok => errors.isEmpty;

  @override
  String toString() =>
      'SyncResult(uploaded: $uploaded, downloaded: $downloaded, '
      'conflicts: $conflicts, errors: $errors)';
}

/// Bumped whenever posts gain fields, so phones that stored posts read by an older
/// app fetch them again.
const _syncSchema = 2;

/// Two-way sync between a [JournalStore] and the shared Drive folder.
///
/// Bookkeeping lives in [JournalStore.syncData]:
///   `watermark`  ISO time; only files modified after it are listed (minus an overlap)
///   `files`      `{<file name>: {id, modifiedTime, owned, bad?}}`, the version of every
///                Drive file this phone has seen or written. A listed file that matches
///                its record is a no-op, which is what makes the overlap safe.
///   `readme`     true once README.md exists in the folder
///   `schema`     the post format this phone's local copy was last read with; an older
///                app reads posts without the fields added later and stores them that
///                way, so a newer one reads every post file again
///
/// Order of a run: check folder, README, year folders, pull, push, download media.
/// One failing file never stops the others.
class SyncEngine {
  SyncEngine(
    this.store,
    this.drive, {
    this.overlap = const Duration(minutes: 10),
    this.maxMediaLookups = 30,
  });

  final JournalStore store;
  final DriveClient drive;

  /// Listings are eventually consistent: look this far behind the newest file seen.
  final Duration overlap;

  /// Cap on "is this photo on Drive although the listing never showed it?" queries per run.
  final int maxMediaLookups;

  bool _running = false;
  late SyncResult _r;
  late String _root;
  final Map<String, List<DriveFile>> _folders =
      {}; // year -> folders, oldest first

  Future<SyncResult> run() async {
    final result = SyncResult();
    if (_running) {
      result.errors.add('A sync is already running.');
      return result;
    }
    _running = true;
    _r = result;
    try {
      await _run();
    } catch (e) {
      result.errors.add(_describe(e));
    } finally {
      _running = false;
      try {
        await store.saveState();
      } catch (_) {}
    }
    return result;
  }

  // ===================================================================== run

  Future<void> _run() async {
    final id = store.settings.driveFolderId?.trim();
    if (id == null || id.isEmpty) {
      _r.errors.add(
        'No Drive folder is set. Choose the shared folder in Settings first.',
      );
      return;
    }
    _root = id;

    try {
      final root = await drive.getFile(_root);
      if (!root.isFolder) {
        _r.errors.add('The configured Drive item is not a folder.');
        return;
      }
    } on DriveException catch (e) {
      _r.errors.add(
        e.notFound || e.forbidden
            ? 'The Drive folder was not found or is not shared with this account (${e.message}).'
            : _describe(e),
      );
      return;
    }

    await _ensureReadme();

    try {
      await _loadFolders();
    } catch (e) {
      _r.errors.add('Could not list the year folders: ${_describe(e)}');
      return;
    }

    await _refreshAfterUpgrade();

    try {
      await _pull();
    } catch (e) {
      // Without a reliable listing the rest would only produce a pile of errors.
      _r.errors.add('Could not read the folder: ${_describe(e)}');
      return;
    }

    await _push();
    await _downloadMedia();
    await store.saveState();
  }

  Future<void> _refreshAfterUpgrade() async {
    if (store.syncData['schema'] == _syncSchema) return;
    store.syncData.remove('watermark');
    for (final name in [
      for (final k in _files.keys)
        if (k.endsWith('.md')) k,
    ]) {
      _files.remove(name);
    }
    store.syncData['schema'] = _syncSchema;
    await store.saveState();
  }

  // ============================================================ small helpers

  static String _describe(Object e) {
    if (e is DriveException) return e.toString();
    if (e is SocketException) return 'no connection (${e.message})';
    if (e is FileSystemException) {
      return 'file problem: ${e.message} ${e.path ?? ''}'.trim();
    }
    return e.toString();
  }

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  static bool _safeName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains(r'\');

  Map<String, dynamic> get _files {
    final v = store.syncData['files'];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    if (v is Map) m.addAll(Map<String, dynamic>.from(v));
    store.syncData['files'] = m;
    return m;
  }

  Map<String, dynamic>? _rec(String name) {
    final v = _files[name];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  void _setRec(DriveFile f, {bool bad = false}) {
    _files[f.name] = {
      'id': f.id,
      'modifiedTime': _iso(f.modifiedTime),
      'owned': f.ownedByMe,
      if (bad) 'bad': true,
    };
  }

  bool _matchesRec(Map<String, dynamic>? rec, DriveFile f) {
    if (rec == null || rec['id'] != f.id) return false;
    final t = DateTime.tryParse('${rec['modifiedTime']}');
    return t != null && t.isAtSameMomentAs(f.modifiedTime);
  }

  /// Deterministic choice among same-named files: the one we already know, else the lowest id.
  DriveFile _pick(List<DriveFile> same) {
    if (same.length == 1) return same.first;
    final known = _rec(same.first.name)?['id'];
    for (final f in same) {
      if (f.id == known) return f;
    }
    return (same.toList()..sort((a, b) => a.id.compareTo(b.id))).first;
  }

  // ================================================================== folders

  List<String> get _allFolderIds => [
    for (final list in _folders.values)
      for (final f in list) f.id,
  ];

  List<String> _folderIdsFor(String year) => [
    for (final f in _folders[year] ?? const <DriveFile>[]) f.id,
  ];

  Future<void> _loadFolders() async {
    final list = await drive.listYearFolders(_root);
    _folders.clear();
    for (final f in list) {
      (_folders[f.name] ??= []).add(f);
    }
    for (final l in _folders.values) {
      l.sort(_oldestFirst);
    }
  }

  static int _oldestFirst(DriveFile a, DriveFile b) {
    final c = (a.createdTime ?? a.modifiedTime).compareTo(
      b.createdTime ?? b.modifiedTime,
    );
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// The folder new files of [year] go into: the oldest one with that name; created if none.
  Future<String> _ensureYearFolder(String year) async {
    var existing = _folders[year];
    if (existing != null && existing.isNotEmpty) return existing.first.id;
    // Look again right before creating: someone else may just have made it.
    await _loadFolders();
    existing = _folders[year];
    if (existing != null && existing.isNotEmpty) return existing.first.id;
    final created = await drive.createFolder(_root, year);
    _folders[year] = [created];
    return created.id;
  }

  // ================================================================== README

  Future<void> _ensureReadme() async {
    if (store.syncData['readme'] == true) return;
    try {
      final existing = await drive.findByName([_root], 'README.md');
      if (existing.isEmpty) {
        await drive.createFile(
          _root,
          'README.md',
          Uint8List.fromList(utf8.encode(_readmeText)),
          mimeType: 'text/markdown',
        );
      }
      store.syncData['readme'] = true;
      await store.saveState();
    } catch (e) {
      _r.errors.add('Could not create README.md: ${_describe(e)}');
    }
  }

  // ===================================================================== pull

  Future<void> _pull() async {
    final folderIds = _allFolderIds;
    if (folderIds.isEmpty) return;

    final wmText = store.syncData['watermark'];
    final watermark = wmText is String ? DateTime.tryParse(wmText) : null;
    final listing = await drive.listFiles(folderIds, modifiedAfter: watermark);

    final byName = <String, List<DriveFile>>{};
    for (final f in listing) {
      (byName[f.name] ??= []).add(f);
    }
    final files = <DriveFile>[];
    for (final group in byName.values) {
      if (group.length > 1) {
        _r.errors.add(
          'Drive has ${group.length} files named "${group.first.name}"; using one of them.',
        );
      }
      files.add(_pick(group));
    }
    files.sort((a, b) {
      final c = a.modifiedTime.compareTo(b.modifiedTime);
      return c != 0 ? c : a.name.compareTo(b.name);
    });

    DateTime? maxSeen;
    DateTime? failedMin;
    for (final f in files) {
      if (maxSeen == null || f.modifiedTime.isAfter(maxSeen)) {
        maxSeen = f.modifiedTime;
      }
      if (_matchesRec(_rec(f.name), f)) continue;
      if (!f.name.endsWith('.md')) {
        _setRec(f); // media: remembered now, fetched later; persisted with the next saveState
        continue;
      }
      try {
        await _applyRemote(f);
      } catch (e) {
        _r.errors.add('Could not read ${f.name}: ${_describe(e)}');
        if (failedMin == null || f.modifiedTime.isBefore(failedMin)) {
          failedMin = f.modifiedTime;
        }
      }
    }
    await store.saveState();

    if (maxSeen != null) {
      var next = maxSeen.subtract(overlap);
      if (failedMin != null) {
        // Never move past a file we could not read: it must be listed again next time.
        final cap = failedMin.subtract(const Duration(milliseconds: 1));
        if (cap.isBefore(next)) next = cap;
      }
      if (watermark != null && next.isBefore(watermark)) next = watermark;
      store.syncData['watermark'] = _iso(next);
      await store.saveState();
    }
  }

  /// Downloads the post file [f] and folds it into the local copy: adopt it when
  /// there are no unsynced local changes, else three-way merge (the merged post
  /// stays dirty and is pushed later). Returns false when the file is unreadable
  /// (reported, remembered as bad so it is not retried until it changes).
  /// Throws on download/storage problems; the caller reports them.
  Future<bool> _applyRemote(DriveFile f) async {
    final stem = f.name.substring(0, f.name.length - 3);
    final bytes = await drive.download(f.id);

    final Entry remote;
    try {
      remote = entryFromMarkdown(utf8.decode(bytes), fallbackId: stem);
      if (remote.id != stem) {
        throw FormatException('id "${remote.id}" does not match the file name');
      }
    } on FormatException catch (e) {
      _r.errors.add('Skipped ${f.name}: ${e.message}');
      _setRec(f, bad: true);
      await store.saveState();
      return false;
    }
    _r.downloaded++;

    // Let edits that are already queued in the store land, so the dirty check
    // below is current. Nothing awaits between the check and the write.
    await store.saveState();
    final local = store.anyById(remote.id);
    final dirty = store.dirtyIds.contains(remote.id);
    final prevBase = store.base(remote.id);
    final localMediaBefore = <String>[...?local?.media, ...?prevBase?.media];

    if (local == null || !dirty) {
      if (local == null || entryToMarkdown(local) != entryToMarkdown(remote)) {
        await store.writeSynced(remote, dirty: false);
      }
      await store.setBase(remote);
      if (remote.deleted) {
        await _dropDeletedPost(remote, localMediaBefore);
      } else if (remote.conflict && !(local?.conflict ?? false)) {
        _r.conflicts++;
      }
    } else {
      final merged = mergeEntry(
        base: prevBase,
        local: local,
        remote: remote,
        localUser: store.settings.me,
      );
      await store.writeSynced(merged, dirty: true);
      await store.setBase(remote);
      if (merged.conflict && !local.conflict) _r.conflicts++;
      if (merged.deleted) {
        await _dropDeletedPost(merged, localMediaBefore);
      } else if (remote.deleted) {
        // An edit beat a deletion. The deleting side may already have removed its
        // media from Drive: forget what we knew about the post's media so push
        // re-checks Drive and re-uploads whatever is still only on this phone.
        for (final name in {...merged.media, ...localMediaBefore}) {
          _files.remove(name);
        }
      }
    }

    _setRec(f);
    await store.saveState();
    return true;
  }

  /// Media files this app created for post [id] are named `<id>_<4 chars>.<ext>`.
  /// Only those are ever deleted when a post is deleted, so a hand-placed file
  /// that several posts link to is never removed by accident.
  static bool _isOwnMedia(String id, String name) =>
      RegExp('^${RegExp.escape(id)}_[a-z0-9]{4}\\.[a-z0-9]+\$').hasMatch(name);

  /// A tombstone arrived: remove the post's local media and the media files on
  /// Drive that this account owns (the owner's phone cleans up its own files).
  Future<void> _dropDeletedPost(
    Entry tombstone,
    Iterable<String> knownMedia,
  ) async {
    for (final name in knownMedia.toSet()) {
      if (!_safeName(name) || !_isOwnMedia(tombstone.id, name)) continue;
      try {
        final f = store.mediaFile(tombstone, name);
        if (await f.exists()) await f.delete();
      } catch (e) {
        _r.errors.add('Could not delete local file $name: ${_describe(e)}');
      }
    }
    await _deleteOwnedMedia(tombstone.id);
  }

  /// Deletes from Drive every media file of post [id] that this account owns and
  /// forgets all its media records. Files owned by other people are left to them.
  Future<void> _deleteOwnedMedia(String id) async {
    final names = [
      for (final k in _files.keys)
        if (_isOwnMedia(id, k)) k,
    ];
    for (final name in names) {
      final rec = _rec(name);
      if (rec == null) continue;
      if (rec['owned'] == true) {
        try {
          await drive.deleteFile('${rec['id']}');
        } on DriveException catch (e) {
          if (!e.notFound) {
            _r.errors.add('Could not delete $name from Drive: ${_describe(e)}');
            continue; // keep the record, try again next time
          }
        } catch (e) {
          _r.errors.add('Could not delete $name from Drive: ${_describe(e)}');
          continue;
        }
      }
      _files.remove(name);
      await store.saveState();
    }
  }

  // ===================================================================== push

  Set<String> _pushCandidates() {
    final ids = {...store.dirtyIds};
    // A post Drive has never seen (e.g. state file lost) is pushed too.
    for (final e in store.allEntries) {
      if (_rec(e.fileName) == null) ids.add(e.id);
    }
    return ids;
  }

  Future<void> _push() async {
    final failed = <String>{};
    // A few passes: a post edited while it was being uploaded is still dirty.
    for (var pass = 0; pass < 3; pass++) {
      final ids = (_pushCandidates()..removeAll(failed)).toList()..sort();
      if (ids.isEmpty) break;
      for (final id in ids) {
        try {
          if (!await _pushPost(id)) failed.add(id);
        } catch (e) {
          failed.add(id);
          _r.errors.add('Could not upload $id: ${_describe(e)}');
        }
      }
    }
  }

  /// Uploads one post (media first, then the `.md`). Returns false when the post
  /// could not be pushed; it then stays dirty and an error was reported.
  Future<bool> _pushPost(String id) async {
    var entry = store.anyById(id);
    if (entry == null) {
      await store.clearDirty(id);
      return true;
    }
    final year = entry.year;

    // ---- media first, so nobody sees a post whose photo is missing
    var mediaOk = true;
    for (final name in entry.media) {
      if (!_safeName(name) || _rec(name) != null) continue;
      final file = store.mediaFile(entry, name);
      if (!await file.exists()) continue;
      try {
        await _uploadMedia(year, name, file);
      } catch (e) {
        mediaOk = false;
        _r.errors.add('Could not upload $name: ${_describe(e)}');
      }
    }
    if (!mediaOk) return false;

    // ---- has someone else changed the post since we last saw it?
    final mdName = entry.fileName;
    var rec = _rec(mdName);
    DriveFile? meta;
    if (rec != null) {
      try {
        meta = await drive.getFile('${rec['id']}');
      } on DriveException catch (e) {
        if (!e.notFound) rethrow;
        _files.remove(
          mdName,
        ); // deleted on Drive: it will be created again below
        rec = null;
      }
    } else {
      final found = await drive.findByName(_folderIdsFor(year), mdName);
      if (found.isNotEmpty) meta = _pick(found);
    }

    if (meta != null) {
      if (_matchesRec(rec, meta)) {
        if (rec?['bad'] == true) {
          _r.errors.add(
            'Not uploading $mdName: the copy on Drive is unreadable. Fix or delete it there.',
          );
          return false;
        }
      } else {
        // Someone wrote it since our last look (or we never looked): merge first.
        if (!await _applyRemote(meta)) return false;
        entry = store.anyById(id);
        if (entry == null || !store.dirtyIds.contains(id)) {
          return true; // nothing of ours left to push
        }
      }
    }

    // ---- write the post
    final text = entryToMarkdown(entry);
    final bytes = Uint8List.fromList(utf8.encode(text));
    final known = _rec(mdName);
    DriveFile written;
    if (known != null && known['bad'] != true) {
      try {
        written = await drive.updateFile(
          '${known['id']}',
          bytes,
          mimeType: 'text/markdown',
        );
      } on DriveException catch (e) {
        if (!e.notFound) rethrow;
        _files.remove(mdName);
        written = await drive.createFile(
          await _ensureYearFolder(year),
          mdName,
          bytes,
          mimeType: 'text/markdown',
        );
      }
    } else {
      written = await drive.createFile(
        await _ensureYearFolder(year),
        mdName,
        bytes,
        mimeType: 'text/markdown',
      );
    }
    _r.uploaded++;

    // Base first: if we crash after this, the next run merges identical versions.
    await store.setBase(entry);
    _setRec(written);
    await store.saveState();
    final current = store.anyById(id);
    if (current != null && entryToMarkdown(current) == text) {
      await store.clearDirty(id);
    } // else edited meanwhile: stays dirty, next pass pushes it

    if (entry.deleted) await _deleteOwnedMedia(id);
    return true;
  }

  Future<void> _uploadMedia(String year, String name, File file) async {
    final folderId = await _ensureYearFolder(year);
    // A previous run may have uploaded it and died before remembering.
    final existing = await drive.findByName(_folderIdsFor(year), name);
    final DriveFile f;
    if (existing.isNotEmpty) {
      f = _pick(existing);
    } else {
      f = await drive.createFileFromFile(
        folderId,
        name,
        file,
        mimeType: mimeTypeFor(name),
      );
      _r.uploaded++;
    }
    _setRec(f);
    await store.saveState();
  }

  // ============================================================ media download

  Future<void> _downloadMedia() async {
    if (!store.settings.downloadMedia) return;
    var lookups = 0;
    for (final entry in store.entries.toList()) {
      for (final name in entry.media) {
        if (!_safeName(name)) continue;
        final target = store.mediaFile(entry, name);
        try {
          if (await target.exists()) continue;
          var rec = _rec(name);
          if (rec == null) {
            // Never listed (e.g. the listing lagged): ask Drive directly.
            if (lookups >= maxMediaLookups) continue;
            lookups++;
            final found = await drive.findByName(
              _folderIdsFor(entry.year),
              name,
            );
            if (found.isEmpty) continue;
            _setRec(_pick(found));
            rec = _rec(name);
          }
          await _fetchMedia(entry, name, '${rec!['id']}', target);
        } on DriveException catch (e) {
          if (e.notFound) {
            _files.remove(name);
            await store.saveState();
            _r.errors.add('$name is no longer on Drive.');
          } else {
            _r.errors.add('Could not download $name: ${_describe(e)}');
          }
        } catch (e) {
          _r.errors.add('Could not download $name: ${_describe(e)}');
        }
      }
    }
  }

  Future<void> _fetchMedia(
    Entry entry,
    String name,
    String driveId,
    File target,
  ) async {
    final tmp = File('${target.path}.tmp');
    try {
      await drive.downloadToFile(driveId, tmp);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    _r.downloaded++;
    // The post may have been deleted while the file was coming down.
    final now = store.anyById(entry.id);
    if (now == null || now.deleted) {
      try {
        await target.delete();
      } catch (_) {}
    }
  }
}

const _readmeText = '''# Open Timeline

This folder is the shared diary written with the Open Timeline app. It syncs
through Google Drive. Everything in it is plain files, so you can read the diary
without the app.

## Layout

```
README.md                         this file
2026/                             one folder per year
  20261016-143205-k3f9.md         one post
  20261016-143205-k3f9_x7q2.jpg   a photo or video of that post
```

File names start with the moment the post was created (year, month, day, hour,
minute, second) followed by a short random code.

## A post

A post is a Markdown file: a header between two `---` lines, then the text.

```
---
id: "20261016-143205-k3f9"
author: "someone@example.com"
time: "2026-10-16T14:32:05+02:00"
title: "Evening walk"
color: "#E8590C"
location: [52.0705, 4.3007]
place: "Scheveningen beach"
tags: ["beach", "sunset"]
media: ["20261016-143205-k3f9_x7q2.jpg"]
updated: "2026-10-16T12:40:00.000Z"
deleted: false
conflict: false
---
The text of the post.
```

* `time` is when the post is about, with the local UTC offset of where it was written.
* `title` and `color` (the author's chosen colour, `#RRGGBB`) are optional.
* `location: [lat, lon]` is written in the format the Obsidian "Map View" plugin understands.
* `media` lists the photos and videos stored next to the post, in the same folder.
* A stamp is a post with `kind: "stamp"`, a `series` (the event, which is also listed in `tags`) and a `country` (a two-letter code such as `JP`), and one image in `media`. `size` (`small` or `large`) and `blend: true` (background removed) appear only when they are not the defaults.
* `deleted: true` marks a deleted post; the file stays so the other phone learns about it.
* `conflict: true` means two edits of the text clashed; both are kept in the text, tidy up and save.

## Reading without the app

Open any `.md` file in a text editor or Markdown viewer. Photos and videos are
linked at the bottom of each post. With Obsidian, open this folder as a vault.

## Please

Do not rename or move the files, and keep each post in the folder of the year in
its name. Editing a post's text by hand is fine; the app picks the change up.
''';
