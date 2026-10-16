import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/entry.dart';

/// The Drive operations the sync engine needs, and nothing more. The engine only
/// talks to this interface so it can be tested against an in-memory fake.

/// MIME type Drive uses for folders.
const driveFolderMimeType = 'application/vnd.google-apps.folder';

/// Year folders are named with exactly four digits.
final yearFolderPattern = RegExp(r'^\d{4}$');

/// An error from Drive with its HTTP status (404 = gone, 403 = not allowed, ...).
class DriveException implements Exception {
  DriveException(this.status, this.message);

  final int status;
  final String message;

  bool get notFound => status == 404;
  bool get forbidden => status == 403;

  @override
  String toString() => 'Drive error $status: $message';
}

/// Metadata of one Drive file or folder.
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.modifiedTime,
    this.createdTime,
    this.ownedByMe = false,
    this.parents = const [],
    this.mimeType,
  });

  final String id;
  final String name;

  /// UTC, millisecond precision as Drive reports it.
  final DateTime modifiedTime;
  final DateTime? createdTime;

  /// Only the owner of a file can delete it in a My Drive folder.
  final bool ownedByMe;
  final List<String> parents;
  final String? mimeType;

  bool get isFolder => mimeType == driveFolderMimeType;

  @override
  String toString() =>
      'DriveFile($name, $id, ${modifiedTime.toIso8601String()})';
}

abstract class DriveClient {
  /// Metadata of one file or folder. Throws [DriveException] (404) when it does
  /// not exist or is in the trash.
  Future<DriveFile> getFile(String fileId);

  /// All non-trashed folders directly inside [rootId] whose name is four digits.
  /// Several folders may share a name.
  Future<List<DriveFile>> listYearFolders(String rootId);

  /// Creates a folder named [name] inside [parentId].
  Future<DriveFile> createFolder(String parentId, String name);

  /// All non-trashed files (not folders) inside any of [folderIds], optionally
  /// only those with `modifiedTime` strictly after [modifiedAfter]. Handles paging.
  Future<List<DriveFile>> listFiles(
    List<String> folderIds, {
    DateTime? modifiedAfter,
  });

  /// Non-trashed files (not folders) called exactly [name] inside any of [folderIds].
  Future<List<DriveFile>> findByName(List<String> folderIds, String name);

  /// Content of a (small) file, e.g. a post.
  Future<Uint8List> download(String fileId);

  /// Streams a file's content to [target] (replaced if it exists).
  Future<void> downloadToFile(String fileId, File target);

  /// Creates a file with [bytes] inside [folderId].
  Future<DriveFile> createFile(
    String folderId,
    String name,
    Uint8List bytes, {
    String? mimeType,
  });

  /// Creates a file by streaming [source] (photos, videos) inside [folderId].
  Future<DriveFile> createFileFromFile(
    String folderId,
    String name,
    File source, {
    String? mimeType,
  });

  /// Replaces the content of an existing file. Returns the new metadata.
  Future<DriveFile> updateFile(
    String fileId,
    Uint8List bytes, {
    String? mimeType,
  });

  /// Permanently deletes a file. Only allowed for its owner.
  Future<void> deleteFile(String fileId);
}

/// MIME type from a file name's extension.
String mimeTypeFor(String fileName) {
  switch (extensionOf(fileName)) {
    case 'md':
      return 'text/markdown';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'gif':
      return 'image/gif';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case '3gp':
      return 'video/3gpp';
    case 'webm':
      return 'video/webm';
    case 'mkv':
      return 'video/x-matroska';
    default:
      return 'application/octet-stream';
  }
}

// ======================================================================
// Real implementation on top of the googleapis Drive v3 client
// ======================================================================

const _fileFields =
    'id, name, mimeType, modifiedTime, createdTime, ownedByMe, parents, trashed';
const _listFields = 'nextPageToken, files($_fileFields)';

/// Files above this size are uploaded with the resumable protocol (chunked,
/// restartable per chunk); smaller ones in a single request.
const _resumableThreshold = 4 * 1024 * 1024;

/// Max folder ids in one `... in parents or ...` query.
const _folderChunk = 40;

class GoogleDriveClient implements DriveClient {
  GoogleDriveClient(this._api, {List<Duration>? retryDelays})
    : _retryDelays =
          retryDelays ??
          const [
            Duration(seconds: 1),
            Duration(seconds: 3),
            Duration(seconds: 8),
          ];

  final drive.DriveApi _api;
  final List<Duration> _retryDelays;

  // ---------------------------------------------------------------- helpers

  /// Runs [action]; retries when Drive says "slow down" (429 / rate-limit 403),
  /// and, for [idempotent] calls, on 5xx and dropped connections. Other API errors
  /// become [DriveException].
  Future<T> _call<T>(
    Future<T> Function() action, {
    bool idempotent = true,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } on drive.DetailedApiRequestError catch (e) {
        final status = e.status ?? 0;
        final retryable =
            status == 429 ||
            (status == 403 && _isRateLimit(e)) ||
            (idempotent && status >= 500 && status < 600);
        if (retryable && attempt < _retryDelays.length) {
          await Future<void>.delayed(_retryDelays[attempt]);
          continue;
        }
        throw DriveException(status, e.message ?? 'request failed');
      } on Exception catch (e) {
        if (idempotent &&
            _isConnectionError(e) &&
            attempt < _retryDelays.length) {
          await Future<void>.delayed(_retryDelays[attempt]);
          continue;
        }
        rethrow;
      }
    }
  }

  static bool _isConnectionError(Exception e) =>
      e is SocketException ||
      e is HttpException ||
      e is TimeoutException ||
      e is http.ClientException;

  static bool _isRateLimit(drive.DetailedApiRequestError e) {
    final text = '${e.message} ${e.errors.map((x) => x.reason).join(' ')}'
        .toLowerCase();
    return text.contains('ratelimit') ||
        text.contains('rate limit') ||
        text.contains('quota');
  }

  static DriveFile _convert(drive.File f) => DriveFile(
    id: f.id ?? '',
    name: f.name ?? '',
    modifiedTime:
        (f.modifiedTime ??
                f.createdTime ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
            .toUtc(),
    createdTime: f.createdTime?.toUtc(),
    ownedByMe: f.ownedByMe ?? false,
    parents: f.parents ?? const [],
    mimeType: f.mimeType,
  );

  /// Single-quoted string literal for a Drive search query.
  static String _lit(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  static String _rfc3339(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  static String _inParents(List<String> ids) =>
      '(${ids.map((id) => '${_lit(id)} in parents').join(' or ')})';

  Future<List<DriveFile>> _list(String q) async {
    final out = <DriveFile>[];
    String? token;
    do {
      final page = await _call(
        () => _api.files.list(
          q: q,
          $fields: _listFields,
          pageSize: 1000,
          pageToken: token,
          spaces: 'drive',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        ),
      );
      for (final f in page.files ?? const <drive.File>[]) {
        if (f.id != null && f.trashed != true) out.add(_convert(f));
      }
      token = page.nextPageToken;
    } while (token != null && token.isNotEmpty);
    return out;
  }

  // -------------------------------------------------------------- interface

  @override
  Future<DriveFile> getFile(String fileId) async {
    final f = await _call(
      () =>
          _api.files.get(fileId, $fields: _fileFields, supportsAllDrives: true),
    );
    final file = f as drive.File;
    if (file.trashed == true) {
      throw DriveException(404, 'File is in the trash: $fileId');
    }
    return _convert(file);
  }

  @override
  Future<List<DriveFile>> listYearFolders(String rootId) async {
    final all = await _list(
      "${_inParents([rootId])} and mimeType = ${_lit(driveFolderMimeType)} and trashed = false",
    );
    return all.where((f) => yearFolderPattern.hasMatch(f.name)).toList();
  }

  @override
  Future<DriveFile> createFolder(String parentId, String name) async {
    final f = await _call(
      () => _api.files.create(
        drive.File(
          name: name,
          mimeType: driveFolderMimeType,
          parents: [parentId],
        ),
        $fields: _fileFields,
        supportsAllDrives: true,
      ),
      idempotent: false,
    );
    return _convert(f);
  }

  @override
  Future<List<DriveFile>> listFiles(
    List<String> folderIds, {
    DateTime? modifiedAfter,
  }) async {
    final out = <DriveFile>[];
    for (var i = 0; i < folderIds.length; i += _folderChunk) {
      final chunk = folderIds.sublist(
        i,
        i + _folderChunk > folderIds.length
            ? folderIds.length
            : i + _folderChunk,
      );
      final since = modifiedAfter == null
          ? ''
          : ' and modifiedTime > ${_lit(_rfc3339(modifiedAfter))}';
      out.addAll(
        await _list(
          '${_inParents(chunk)} and mimeType != ${_lit(driveFolderMimeType)} and trashed = false$since',
        ),
      );
    }
    return out;
  }

  @override
  Future<List<DriveFile>> findByName(
    List<String> folderIds,
    String name,
  ) async {
    final out = <DriveFile>[];
    for (var i = 0; i < folderIds.length; i += _folderChunk) {
      final chunk = folderIds.sublist(
        i,
        i + _folderChunk > folderIds.length
            ? folderIds.length
            : i + _folderChunk,
      );
      out.addAll(
        await _list(
          '${_inParents(chunk)} and name = ${_lit(name)} and mimeType != ${_lit(driveFolderMimeType)} and trashed = false',
        ),
      );
    }
    return out;
  }

  Future<drive.Media> _openMedia(String fileId) async {
    final m = await _call(
      () => _api.files.get(
        fileId,
        supportsAllDrives: true,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ),
    );
    return m as drive.Media;
  }

  @override
  Future<Uint8List> download(String fileId) => _call(() async {
    final media = await _openMedia(fileId);
    final b = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      b.add(chunk);
    }
    return b.takeBytes();
  });

  @override
  Future<void> downloadToFile(String fileId, File target) => _call(() async {
    final media = await _openMedia(fileId);
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    try {
      await sink.addStream(media.stream);
      await sink.flush();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    }
    await sink.close();
  });

  @override
  Future<DriveFile> createFile(
    String folderId,
    String name,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    final type = mimeType ?? mimeTypeFor(name);
    final f = await _call(
      () => _api.files.create(
        drive.File(name: name, parents: [folderId], mimeType: type),
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: type,
        ),
        $fields: _fileFields,
        supportsAllDrives: true,
      ),
      idempotent: false,
    );
    return _convert(f);
  }

  @override
  Future<DriveFile> createFileFromFile(
    String folderId,
    String name,
    File source, {
    String? mimeType,
  }) async {
    final type = mimeType ?? mimeTypeFor(name);
    final length = await source.length();
    final f = await _call(
      // The stream is reopened on every attempt.
      () => _api.files.create(
        drive.File(name: name, parents: [folderId], mimeType: type),
        uploadMedia: drive.Media(source.openRead(), length, contentType: type),
        uploadOptions: length > _resumableThreshold
            ? drive.UploadOptions.resumable
            : drive.UploadOptions.defaultOptions,
        $fields: _fileFields,
        supportsAllDrives: true,
      ),
      idempotent: false,
    );
    return _convert(f);
  }

  @override
  Future<DriveFile> updateFile(
    String fileId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    final type = mimeType ?? 'application/octet-stream';
    final f = await _call(
      () => _api.files.update(
        drive.File(),
        fileId,
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: type,
        ),
        $fields: _fileFields,
        supportsAllDrives: true,
      ),
    );
    return _convert(f);
  }

  @override
  Future<void> deleteFile(String fileId) =>
      _call(() => _api.files.delete(fileId, supportsAllDrives: true));
}
