import 'dart:math';

const _keep = Object();
final _rand = Random.secure();
const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

String _randomSuffix(int length) => List.generate(
  length,
  (_) => _idChars[_rand.nextInt(_idChars.length)],
).join();

String _two(int n) => n.toString().padLeft(2, '0');

const videoExtensions = {'mp4', 'mov', '3gp', 'webm', 'mkv'};
const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'};

String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}

bool isVideo(String fileName) =>
    videoExtensions.contains(extensionOf(fileName));
bool isImage(String fileName) =>
    imageExtensions.contains(extensionOf(fileName));

const kindPost = 'post';
const kindStamp = 'stamp';

const sizeSmall = 'small';
const sizeMedium = 'medium';
const sizeLarge = 'large';
const stampSizes = [sizeSmall, sizeMedium, sizeLarge];

class Entry {
  const Entry({
    required this.id,
    required this.author,
    required this.time,
    required this.utcOffsetMinutes,
    this.lat,
    this.lon,
    this.place,
    this.title = '',
    this.color,
    this.text = '',
    this.tags = const [],
    this.media = const [],
    required this.updated,
    this.deleted = false,
    this.conflict = false,
    this.kind = kindPost,
    this.series = '',
    this.country,
    this.size = sizeMedium,
    this.blend = false,
    this.cutout = '',
  });

  factory Entry.create({
    required String author,
    DateTime? now,
    String kind = kindPost,
  }) {
    final t = now ?? DateTime.now();
    return Entry(
      id: newId(t),
      kind: kind,
      author: author,
      time: t.toUtc(),
      utcOffsetMinutes: t.timeZoneOffset.inMinutes,
      updated: t.toUtc(),
    );
  }

  /// Fixed at creation: editing [time] later must not move the post's files.
  static String newId(DateTime createdAt) {
    final t = createdAt.isUtc ? createdAt.toLocal() : createdAt;
    return '${t.year}${_two(t.month)}${_two(t.day)}-'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}-${_randomSuffix(4)}';
  }

  final String id;

  final String author;

  final DateTime time;

  final int utcOffsetMinutes;

  final double? lat;
  final double? lon;

  final String? place;

  final String title;

  final int? color;

  final String text;
  final List<String> tags;

  final List<String> media;

  final DateTime updated;

  final bool deleted;

  final bool conflict;

  final String kind;

  /// Stamps only: the set a stamp belongs to, such as "JR West eki".
  final String series;

  /// Stamps only: ISO 3166 alpha-2 code.
  final String? country;

  /// Collectibles only: how big the item is drawn on a booklet page.
  final String size;

  /// Collectibles only: show the item without its paper, as if printed on the page.
  final bool blend;

  /// Collectibles only: how the background is removed. Empty finds the paper
  /// colour by itself, `#RRGGBB` is a paper colour picked by hand and
  /// `subject` asks the phone to find the item.
  final String cutout;

  bool get isStamp => kind == kindStamp;

  bool get isCollectible => kind != kindPost;

  /// UTC-flagged but holds the local clock reading: format it, never convert it.
  DateTime get wallTime =>
      time.toUtc().add(Duration(minutes: utcOffsetMinutes));

  bool get hasLocation => lat != null && lon != null;

  /// From the id, not [time].
  String get year => id.substring(0, 4);

  String get fileName => '$id.md';

  /// Random rather than counted: two phones adding media offline must not collide.
  String newMediaName(String extension) =>
      '${id}_${_randomSuffix(4)}.${extension.toLowerCase().replaceFirst('.', '')}';

  Entry copyWith({
    String? author,
    DateTime? time,
    int? utcOffsetMinutes,
    Object? lat = _keep,
    Object? lon = _keep,
    Object? place = _keep,
    String? title,
    int? color,
    String? text,
    List<String>? tags,
    List<String>? media,
    DateTime? updated,
    bool? deleted,
    bool? conflict,
    String? series,
    Object? country = _keep,
    String? size,
    bool? blend,
    String? cutout,
  }) {
    return Entry(
      id: id,
      author: author ?? this.author,
      time: time ?? this.time,
      utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
      lat: identical(lat, _keep) ? this.lat : lat as double?,
      lon: identical(lon, _keep) ? this.lon : lon as double?,
      place: identical(place, _keep) ? this.place : place as String?,
      title: title ?? this.title,
      color: color ?? this.color,
      text: text ?? this.text,
      tags: tags ?? this.tags,
      media: media ?? this.media,
      updated: updated ?? this.updated,
      deleted: deleted ?? this.deleted,
      conflict: conflict ?? this.conflict,
      kind: kind,
      series: series ?? this.series,
      country: identical(country, _keep) ? this.country : country as String?,
      size: size ?? this.size,
      blend: blend ?? this.blend,
      cutout: cutout ?? this.cutout,
    );
  }
}
