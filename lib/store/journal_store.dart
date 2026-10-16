import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/entry.dart';
import '../models/entry_format.dart';

class AppSettings {
  AppSettings({
    this.me = '',
    this.driveFolderId,
    this.downloadMedia = true,
    this.myColor,
  });

  String me;

  String? driveFolderId;

  bool downloadMedia;

  int? myColor;

  AppSettings copyWith({
    String? me,
    String? driveFolderId,
    bool? downloadMedia,
    int? myColor,
  }) => AppSettings(
    me: me ?? this.me,
    driveFolderId: driveFolderId ?? this.driveFolderId,
    downloadMedia: downloadMedia ?? this.downloadMedia,
    myColor: myColor ?? this.myColor,
  );
}

final _yearDir = RegExp(r'^\d{4}$');

String _basename(String path) =>
    path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

class JournalStore extends ChangeNotifier {
  JournalStore(this.root);

  final Directory root;

  AppSettings _settings = AppSettings();
  final Map<String, Entry> _all = {};
  final Set<String> _dirty = {};
  final Map<String, dynamic> _sync = {};
  List<Entry> _visible = const [];
  Map<String, int> _peopleColors = const {};
  Future<void> _tail = Future.value();

  static Future<JournalStore> openDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/journal');
    await dir.create(recursive: true);
    final store = JournalStore(dir);
    await store.load();
    return store;
  }

  AppSettings get settings => _settings;

  Future<void> updateSettings(AppSettings settings) => _locked(() async {
    _settings = settings;
    await _writeState();
    notifyListeners();
  });

  Future<void> load() => _locked(() async {
    await root.create(recursive: true);
    final loaded = <String, Entry>{};
    await for (final dir in root.list(followLinks: false)) {
      if (dir is! Directory) continue;
      final year = _basename(dir.path);
      if (!_yearDir.hasMatch(year)) continue;
      await for (final f in dir.list(followLinks: false)) {
        if (f is! File || !f.path.endsWith('.md')) continue;
        final stem = _basename(f.path).replaceFirst(RegExp(r'\.md$'), '');
        try {
          final e = entryFromMarkdown(await f.readAsString(), fallbackId: stem);
          // A mismatch would make save() write a second copy.
          if (e.id != stem || e.year != year) {
            throw FormatException('id "${e.id}" does not match its location');
          }
          loaded[e.id] = e;
        } catch (err) {
          debugPrint('JournalStore: skipping ${f.path}: $err');
        }
      }
    }
    _all
      ..clear()
      ..addAll(loaded);
    await _readState();
    _rebuild();
    notifyListeners();
  });

  Future<void> _readState() async {
    final file = _stateFile;
    _settings = AppSettings();
    _dirty.clear();
    _sync.clear(); // in place: callers may hold the map
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) throw const FormatException('state is not an object');
      final s = json['settings'];
      if (s is Map) {
        _settings = AppSettings(
          me: s['me'] is String ? s['me'] as String : '',
          driveFolderId: s['driveFolderId'] is String
              ? s['driveFolderId'] as String
              : null,
          downloadMedia: s['downloadMedia'] is bool
              ? s['downloadMedia'] as bool
              : true,
          myColor: s['myColor'] is int ? s['myColor'] as int : null,
        );
      }
      final d = json['dirty'];
      if (d is List) _dirty.addAll(d.whereType<String>());
      final sync = json['sync'];
      if (sync is Map) _sync.addAll(Map<String, dynamic>.from(sync));
    } catch (err) {
      // Keep the broken file; posts differing from their base (or lacking one) become dirty.
      debugPrint('JournalStore: unreadable ${file.path}: $err');
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
      _settings = AppSettings();
      _sync.clear();
      for (final e in _all.values) {
        final b = base(e.id);
        if (b == null || entryToMarkdown(b) != entryToMarkdown(e)) {
          _dirty.add(e.id);
        }
      }
      await _writeState();
    }
  }

  List<Entry> get entries => _visible;

  Entry? byId(String id) {
    final e = _all[id];
    return (e == null || e.deleted) ? null : e;
  }

  Iterable<Entry> get allEntries => List.unmodifiable(_all.values);

  Entry? anyById(String id) => _all[id];

  List<String> get allTags {
    final tags = <String>{for (final e in _visible) ...e.tags};
    return tags.toList()..sort(_compareText);
  }

  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final e in _visible) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<String> get authors {
    final names = <String>{
      for (final e in _visible)
        if (e.author.isNotEmpty) e.author,
    };
    return names.toList()..sort(_compareText);
  }

  static int _compareText(String a, String b) {
    final c = a.toLowerCase().compareTo(b.toLowerCase());
    return c != 0 ? c : a.compareTo(b);
  }

  void _rebuild() {
    final list = _all.values.where((e) => !e.deleted).toList()
      ..sort((a, b) {
        final c = b.time.compareTo(a.time);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    _visible = List.unmodifiable(list);
    final latest = <String, Entry>{};
    for (final e in list) {
      if (e.color == null) continue;
      final k = e.author.toLowerCase();
      final cur = latest[k];
      if (cur == null || e.updated.isAfter(cur.updated)) latest[k] = e;
    }
    _peopleColors = {for (final e in latest.entries) e.key: e.value.color!};
  }

  Map<String, int> get peopleColors => _peopleColors;

  Future<void> setMyColor(int color) async {
    await updateSettings(_settings.copyWith(myColor: color));
    final me = _settings.me.trim().toLowerCase();
    final mine = _visible
        .where((e) => e.author.toLowerCase() == me && e.color != color)
        .firstOrNull;
    if (mine != null) await save(mine.copyWith(color: color));
  }

  Future<void> save(Entry entry) => _locked(() async {
    // Round-trip through the file format so memory matches what a reload produces.
    final stored = _normalized(
      entry.copyWith(updated: DateTime.now().toUtc(), conflict: false),
    );
    // Dirty is persisted before the post so a crash never loses track of an edit.
    _dirty.add(stored.id);
    await _writeState();
    await _writeEntry(stored);
    _all[stored.id] = stored;
    _rebuild();
    notifyListeners();
  });

  /// Renames [from] to [to] on every post, or removes it when [to] is null. Returns the posts changed.
  Future<int> changeTag(String from, String? to) => _locked(() async {
    final changed = <Entry>[];
    final now = DateTime.now().toUtc();
    for (final e in _all.values) {
      if (e.deleted || !e.tags.contains(from)) continue;
      final seen = <String>{};
      final tags = <String>[];
      for (final t in e.tags) {
        final next = t == from ? to : t;
        if (next != null && seen.add(next.toLowerCase())) tags.add(next);
      }
      changed.add(_normalized(e.copyWith(tags: tags, updated: now)));
    }
    if (changed.isEmpty) return 0;
    _dirty.addAll(changed.map((e) => e.id));
    await _writeState();
    for (final e in changed) {
      await _writeEntry(e);
      _all[e.id] = e;
    }
    _rebuild();
    notifyListeners();
    return changed.length;
  });

  Future<void> delete(String id) => _locked(() async {
    final old = _all[id];
    if (old == null || old.deleted) return;
    final tombstone = _normalized(
      Entry(
        id: old.id,
        author: old.author,
        time: old.time,
        utcOffsetMinutes: old.utcOffsetMinutes,
        tags: old.tags,
        updated: DateTime.now().toUtc(),
        deleted: true,
      ),
    );
    _dirty.add(id);
    await _writeState();
    await _writeEntry(tombstone);
    _all[id] = tombstone;
    for (final name in old.media) {
      try {
        final f = mediaFile(old, name);
        if (await f.exists()) await f.delete();
      } catch (err) {
        debugPrint('JournalStore: could not delete media $name: $err');
      }
    }
    _rebuild();
    notifyListeners();
  });

  /// Does not save the entry: the caller adds the returned name to `media`.
  Future<String> importMedia(Entry entry, File source) => _locked(() async {
    final dir = Directory('${root.path}/${entry.year}');
    await dir.create(recursive: true);
    final ext = extensionOf(_basename(source.path))
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    var name = entry.newMediaName(ext.isEmpty ? 'bin' : ext);
    while (await File('${dir.path}/$name').exists()) {
      name = entry.newMediaName(ext.isEmpty ? 'bin' : ext);
    }
    final tmp = await source.copy('${dir.path}/$name.tmp');
    await tmp.rename('${dir.path}/$name');
    return name;
  });

  /// Only the last segment of [name] is used, so it cannot escape the year folder.
  File mediaFile(Entry entry, String name) {
    final safe = name.split(RegExp(r'[/\\]')).last;
    return File('${root.path}/${entry.year}/$safe');
  }

  Set<String> get dirtyIds => Set.of(_dirty);
  int get dirtyCount => _dirty.length;

  Entry? base(String id) {
    try {
      final f = _baseFile(id);
      if (!f.existsSync()) return null;
      return entryFromMarkdown(f.readAsStringSync(), fallbackId: id);
    } catch (err) {
      debugPrint('JournalStore: unreadable base for $id: $err');
      return null;
    }
  }

  Future<void> setBase(Entry e) => _locked(() async {
    await _atomicWrite(_baseFile(e.id), entryToMarkdown(e));
  });

  /// Unlike [save], does not restamp `updated` or clear `conflict`.
  Future<void> writeSynced(Entry e, {required bool dirty}) => _locked(() async {
    final stored = _normalized(e);
    if (dirty) {
      _dirty.add(stored.id);
      await _writeState();
      await _writeEntry(stored);
    } else {
      await _writeEntry(stored);
      if (_dirty.remove(stored.id)) await _writeState();
    }
    _all[stored.id] = stored;
    _rebuild();
    notifyListeners();
  });

  Future<void> clearDirty(String id) => _locked(() async {
    if (!_dirty.remove(id)) return;
    await _writeState();
    notifyListeners();
  });

  Map<String, dynamic> get syncData => _sync;

  Future<void> saveState() => _locked(_writeState);

  File get _stateFile => File('${root.path}/.state.json');
  File _baseFile(String id) => File('${root.path}/.base/$id.md');

  Entry _normalized(Entry e) => entryFromMarkdown(entryToMarkdown(e));

  Future<void> _writeEntry(Entry e) => _atomicWrite(
    File('${root.path}/${e.year}/${e.fileName}'),
    entryToMarkdown(e),
  );

  Future<void> _writeState() {
    final json = {
      'version': 1,
      'settings': {
        'me': _settings.me,
        'driveFolderId': _settings.driveFolderId,
        'downloadMedia': _settings.downloadMedia,
        'myColor': _settings.myColor,
      },
      'dirty': _dirty.toList()..sort(),
      'sync': _sync,
    };
    // The toEncodable fallback keeps odd syncData values from failing a save.
    return _atomicWrite(
      _stateFile,
      JsonEncoder.withIndent('  ', (o) => o.toString()).convert(json),
    );
  }

  Future<void> _atomicWrite(File target, String content) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final done = Completer<T>();
    final previous = _tail;
    _tail = done.future.then<void>((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        done.complete(await action());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }
}
