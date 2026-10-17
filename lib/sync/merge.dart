import '../models/entry.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `d MMM HH:mm`, e.g. `16 Oct 14:30`. Formats [t] as given (no timezone
/// conversion) and does not depend on the intl default locale.
String _stamp(DateTime t) =>
    '${t.day} ${_months[t.month - 1]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameTime(Entry a, Entry b) =>
    a.time.isAtSameMomentAs(b.time) && a.utcOffsetMinutes == b.utcOffsetMinutes;

bool _samePlace(Entry a, Entry b) =>
    a.lat == b.lat && a.lon == b.lon && a.place == b.place;

/// True when [side] differs from [base] in any user-visible content
/// (`updated` and `conflict` are bookkeeping and do not count).
bool _changed(Entry side, Entry? base) {
  if (base == null) return true;
  return !_sameTime(side, base) ||
      !_samePlace(side, base) ||
      side.author != base.author ||
      side.title != base.title ||
      side.color != base.color ||
      side.series != base.series ||
      side.country != base.country ||
      side.size != base.size ||
      side.blend != base.blend ||
      side.text != base.text ||
      !_sameList(side.tags, base.tags) ||
      !_sameList(side.media, base.media) ||
      side.deleted != base.deleted;
}

/// Set merge: [base] plus additions from either side minus removals from either
/// side. Order: [remote]'s order first, then [local]'s new items.
List<String> _mergeList(
  List<String> base,
  List<String> local,
  List<String> remote,
) {
  final b = base.toSet();
  final l = local.toSet();
  final r = remote.toSet();
  final out = <String>[];
  final seen = <String>{};
  for (final x in remote) {
    final removedByLocal = b.contains(x) && !l.contains(x);
    if (!removedByLocal && seen.add(x)) out.add(x);
  }
  for (final x in local) {
    // Not in base => added locally. In base but missing from remote => removed there.
    if (!b.contains(x) && !r.contains(x) && seen.add(x)) out.add(x);
  }
  return out;
}

/// Three-way merge of one post that changed on both sides since the last sync.
/// Pure: no I/O. [base] is the version both sides had at the last sync (null only
/// in a corrupt/edge case, then every differing field counts as changed on both
/// sides). The result keeps [local]'s id.
///
/// Rules per field, against [base]:
///  * time(+offset), location(+place), author, title, color: one side changed -> that
///    side; both changed -> [remote].
///  * text: one side changed -> that side; both changed to the same text -> it;
///    both changed differently -> both are kept in one text, `conflict: true`.
///  * tags, media: set merge (additions and removals from both sides).
///  * delete vs edit: the edit wins; delete vs unchanged: tombstone.
Entry mergeEntry({
  required Entry? base,
  required Entry local,
  required Entry remote,
  required String localUser,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final updated = at.toUtc();

  // ---- deletions
  if (local.deleted && remote.deleted) {
    return remote.copyWith(updated: updated, conflict: false);
  }
  if (local.deleted || remote.deleted) {
    final tombstone = local.deleted ? local : remote;
    final editor = local.deleted ? remote : local;
    if (_changed(editor, base)) {
      return editor.copyWith(updated: updated, deleted: false);
    }
    return tombstone.copyWith(updated: updated);
  }

  // ---- scalar groups: remote wins unless only local changed
  final localTime = base == null || !_sameTime(local, base);
  final remoteTime = base == null || !_sameTime(remote, base);
  final timeFrom = (localTime && !remoteTime) ? local : remote;

  final localPlace = base == null || !_samePlace(local, base);
  final remotePlace = base == null || !_samePlace(remote, base);
  final placeFrom = (localPlace && !remotePlace) ? local : remote;

  final localAuthor = base == null || local.author != base.author;
  final remoteAuthor = base == null || remote.author != base.author;
  final author = (localAuthor && !remoteAuthor) ? local.author : remote.author;

  final localTitle = base == null || local.title != base.title;
  final remoteTitle = base == null || remote.title != base.title;
  final title = (localTitle && !remoteTitle) ? local.title : remote.title;

  final localColor = base == null || local.color != base.color;
  final remoteColor = base == null || remote.color != base.color;
  final color = (localColor && !remoteColor) ? local.color : remote.color;

  final localSeries = base == null || local.series != base.series;
  final remoteSeries = base == null || remote.series != base.series;
  final series = (localSeries && !remoteSeries) ? local.series : remote.series;

  final localCountry = base == null || local.country != base.country;
  final remoteCountry = base == null || remote.country != base.country;
  final country = (localCountry && !remoteCountry)
      ? local.country
      : remote.country;

  final localSize = base == null || local.size != base.size;
  final remoteSize = base == null || remote.size != base.size;
  final size = (localSize && !remoteSize) ? local.size : remote.size;

  final localBlend = base == null || local.blend != base.blend;
  final remoteBlend = base == null || remote.blend != base.blend;
  final blend = (localBlend && !remoteBlend) ? local.blend : remote.blend;

  // ---- text
  final localText = base == null || local.text != base.text;
  final remoteText = base == null || remote.text != base.text;
  final String text;
  final bool conflict;
  if (localText && remoteText) {
    if (local.text == remote.text) {
      text = remote.text;
      conflict = local.conflict || remote.conflict;
    } else {
      text =
          '${remote.text}\n\n──── conflicting edit by $localUser · ${_stamp(at)} ────\n${local.text}';
      conflict = true;
    }
  } else if (localText) {
    text = local.text;
    conflict = local.conflict;
  } else if (remoteText) {
    text = remote.text;
    conflict = remote.conflict;
  } else {
    text = remote.text;
    conflict = local.conflict || remote.conflict;
  }

  return Entry(
    id: local.id,
    author: author,
    time: timeFrom.time,
    utcOffsetMinutes: timeFrom.utcOffsetMinutes,
    lat: placeFrom.lat,
    lon: placeFrom.lon,
    place: placeFrom.place,
    title: title,
    color: color,
    kind: remote.kind,
    series: series,
    country: country,
    size: size,
    blend: blend,
    text: text,
    tags: _mergeList(base?.tags ?? const [], local.tags, remote.tags),
    media: _mergeList(base?.media ?? const [], local.media, remote.media),
    updated: updated,
    deleted: false,
    conflict: conflict,
  );
}
