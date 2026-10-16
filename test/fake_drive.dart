import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_timeline/sync/drive_client.dart';

class _Node {
  _Node({
    required this.id,
    required this.name,
    required this.parent,
    required this.owner,
    required this.isFolder,
    required this.created,
    required this.modified,
    Uint8List? bytes,
  }) : bytes = bytes ?? Uint8List(0);

  final String id;
  String name;
  final String? parent;
  final String owner;
  final bool isFolder;
  final DateTime created;
  DateTime modified;
  Uint8List bytes;
  bool trashed = false;
}

typedef FakeHook = FutureOr<void> Function(String op, String user);

/// In-memory stand-in for one shared Drive folder tree ("person A's My Drive").
///
/// * ids are unique, `modifiedTime` increases with every write (one second apart),
/// * every phone gets its own view via [as]; `ownedByMe` and deletion rights
///   follow the viewer,
/// * anyone with the folder can read, create and update; only the owner can delete,
/// * several folders may share a name.
class FakeDrive {
  FakeDrive({String ownerOfRoot = 'a@x'}) {
    rootId = _newNode(
      name: 'Open Timeline',
      parent: null,
      owner: ownerOfRoot,
      isFolder: true,
    ).id;
  }

  late final String rootId;
  final Map<String, _Node> _nodes = {};
  int _counter = 0;
  DateTime _clock = DateTime.utc(2026, 10, 16, 12);

  /// How many times each operation ran (all users together), e.g. `createFile`.
  final Map<String, int> calls = {};

  /// Runs before an operation takes effect. May mutate the drive (a partner
  /// writing at the wrong moment) or throw (a lost connection).
  FakeHook? before;

  /// Runs after an operation took effect but before its result is returned.
  /// Throwing here simulates a lost response: the server did the work.
  FakeHook? after;

  /// Ids that [FakeDriveClient.listFiles] does not return yet (a lagging index).
  /// Lookups by name and by id are not affected.
  Set<String> hidden = {};

  FakeDriveClient as(String user) => FakeDriveClient._(this, user);

  /// Moves the server clock forward.
  void advance(Duration d) => _clock = _clock.add(d);

  DateTime get now => _clock;

  void resetCalls() => calls.clear();

  int count(String op) => calls[op] ?? 0;

  // ---------------------------------------------------------- inspection

  /// Live (non-trashed) files whose name is [name], any folder.
  List<String> idsNamed(String name) => [
    for (final n in _nodes.values)
      if (!n.trashed && n.name == name) n.id,
  ];

  /// Names of all live non-folder files, sorted.
  List<String> fileNames() => [
    for (final n in _nodes.values)
      if (!n.trashed && !n.isFolder) n.name,
  ]..sort();

  /// Live folders directly inside the root.
  List<String> yearFolderNames() => [
    for (final n in _nodes.values)
      if (!n.trashed && n.isFolder && n.parent == rootId) n.name,
  ]..sort();

  Uint8List contentOf(String id) => _nodes[id]!.bytes;

  String textOf(String name) {
    final ids = idsNamed(name);
    if (ids.length != 1) {
      throw StateError('expected exactly one "$name", found ${ids.length}');
    }
    return utf8.decode(_nodes[ids.single]!.bytes);
  }

  String ownerOf(String id) => _nodes[id]!.owner;

  String parentOf(String id) => _nodes[id]!.parent!;

  /// Pretend somebody removed the file in the Drive web UI.
  void trashById(String id) => _nodes[id]!.trashed = true;

  /// Overwrites file content as [user] would, bypassing hooks and counters.
  void writeAs(String user, String id, Uint8List bytes) {
    final n = _nodes[id]!;
    n.bytes = Uint8List.fromList(bytes);
    n.modified = _tick();
  }

  // ------------------------------------------------------------ internals

  DateTime _tick() {
    _clock = _clock.add(const Duration(seconds: 1));
    return _clock;
  }

  _Node _newNode({
    required String name,
    required String? parent,
    required String owner,
    required bool isFolder,
    Uint8List? bytes,
  }) {
    final id = 'id${(++_counter).toString().padLeft(4, '0')}';
    final t = _tick();
    final n = _Node(
      id: id,
      name: name,
      parent: parent,
      owner: owner,
      isFolder: isFolder,
      created: t,
      modified: t,
      bytes: bytes,
    );
    _nodes[id] = n;
    return n;
  }

  _Node _live(String id) {
    final n = _nodes[id];
    if (n == null || n.trashed) {
      throw DriveException(404, 'File not found: $id');
    }
    return n;
  }

  DriveFile _meta(_Node n, String viewer) => DriveFile(
    id: n.id,
    name: n.name,
    modifiedTime: n.modified,
    createdTime: n.created,
    ownedByMe: n.owner == viewer,
    parents: n.parent == null ? const [] : [n.parent!],
    mimeType: n.isFolder ? driveFolderMimeType : 'application/octet-stream',
  );

  Future<void> _enter(String op, String user) async {
    calls[op] = (calls[op] ?? 0) + 1;
    final h = before;
    if (h != null) await h(op, user);
  }

  Future<void> _leave(String op, String user) async {
    final h = after;
    if (h != null) await h(op, user);
  }
}

class FakeDriveClient implements DriveClient {
  FakeDriveClient._(this._d, this.user);

  final FakeDrive _d;
  final String user;

  Future<T> _op<T>(String op, FutureOr<T> Function() body) async {
    await _d._enter(op, user);
    final result = await body();
    await _d._leave(op, user);
    return result;
  }

  @override
  Future<DriveFile> getFile(String fileId) =>
      _op('getFile', () => _d._meta(_d._live(fileId), user));

  @override
  Future<List<DriveFile>> listYearFolders(String rootId) =>
      _op('listYearFolders', () {
        _d._live(rootId);
        return [
          for (final n in _d._nodes.values)
            if (!n.trashed &&
                n.isFolder &&
                n.parent == rootId &&
                yearFolderPattern.hasMatch(n.name))
              _d._meta(n, user),
        ];
      });

  @override
  Future<DriveFile> createFolder(String parentId, String name) => _op(
    'createFolder',
    () {
      _d._live(parentId);
      return _d._meta(
        _d._newNode(name: name, parent: parentId, owner: user, isFolder: true),
        user,
      );
    },
  );

  @override
  Future<List<DriveFile>> listFiles(
    List<String> folderIds, {
    DateTime? modifiedAfter,
  }) => _op('listFiles', () {
    for (final id in folderIds) {
      _d._live(id);
    }
    return [
      for (final n in _d._nodes.values)
        if (!n.trashed &&
            !n.isFolder &&
            !_d.hidden.contains(n.id) &&
            folderIds.contains(n.parent) &&
            (modifiedAfter == null || n.modified.isAfter(modifiedAfter)))
          _d._meta(n, user),
    ];
  });

  @override
  Future<List<DriveFile>> findByName(List<String> folderIds, String name) =>
      _op('findByName', () {
        return [
          for (final n in _d._nodes.values)
            if (!n.trashed &&
                !n.isFolder &&
                folderIds.contains(n.parent) &&
                n.name == name)
              _d._meta(n, user),
        ];
      });

  @override
  Future<Uint8List> download(String fileId) =>
      _op('download', () => Uint8List.fromList(_d._live(fileId).bytes));

  @override
  Future<void> downloadToFile(String fileId, File target) =>
      _op('downloadToFile', () async {
        final bytes = _d._live(fileId).bytes;
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes);
      });

  @override
  Future<DriveFile> createFile(
    String folderId,
    String name,
    Uint8List bytes, {
    String? mimeType,
  }) => _op('createFile', () {
    final parent = _d._live(folderId);
    if (!parent.isFolder) throw DriveException(400, 'not a folder');
    return _d._meta(
      _d._newNode(
        name: name,
        parent: folderId,
        owner: user,
        isFolder: false,
        bytes: Uint8List.fromList(bytes),
      ),
      user,
    );
  });

  @override
  Future<DriveFile> createFileFromFile(
    String folderId,
    String name,
    File source, {
    String? mimeType,
  }) => _op('createFile', () async {
    final parent = _d._live(folderId);
    if (!parent.isFolder) throw DriveException(400, 'not a folder');
    final bytes = await source.readAsBytes();
    return _d._meta(
      _d._newNode(
        name: name,
        parent: folderId,
        owner: user,
        isFolder: false,
        bytes: bytes,
      ),
      user,
    );
  });

  @override
  Future<DriveFile> updateFile(
    String fileId,
    Uint8List bytes, {
    String? mimeType,
  }) => _op('updateFile', () {
    final n = _d._live(fileId);
    if (n.isFolder) throw DriveException(400, 'cannot update a folder');
    n.bytes = Uint8List.fromList(bytes);
    n.modified = _d._tick();
    return _d._meta(n, user);
  });

  @override
  Future<void> deleteFile(String fileId) => _op('deleteFile', () {
    final n = _d._live(fileId);
    if (n.owner != user) {
      throw DriveException(
        403,
        'The user does not have sufficient permissions for file $fileId',
      );
    }
    n.trashed = true;
  });
}
