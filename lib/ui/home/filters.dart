import 'package:flutter/material.dart';

import '../../models/entry.dart';

enum ContentShow { all, posts, collection }

class EntryFilter extends ChangeNotifier {
  DateTimeRange? _range;
  String? _tag;
  String? _author;
  String _query = '';
  ContentShow _show = ContentShow.all;

  /// Inclusive calendar days, compared against `wallTime`.
  DateTimeRange? get range => _range;
  String? get tag => _tag;
  String? get author => _author;
  String get query => _query;
  ContentShow get show => _show;

  bool get active =>
      _range != null ||
      _tag != null ||
      _author != null ||
      _query.trim().isNotEmpty;

  set range(DateTimeRange? value) {
    if (_range == value) return;
    _range = value == null
        ? null
        : DateTimeRange(start: dayOf(value.start), end: dayOf(value.end));
    notifyListeners();
  }

  set tag(String? value) {
    if (_tag == value) return;
    _tag = value;
    notifyListeners();
  }

  set author(String? value) {
    if (_author == value) return;
    _author = value;
    notifyListeners();
  }

  set show(ContentShow value) {
    if (_show == value) return;
    _show = value;
    notifyListeners();
  }

  set query(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void clear() {
    if (!active && _query.isEmpty && _show == ContentShow.all) return;
    _show = ContentShow.all;
    _range = null;
    _tag = null;
    _author = null;
    _query = '';
    notifyListeners();
  }

  bool matches(Entry e) {
    if (_show == ContentShow.posts && e.isCollectible) return false;
    if (_show == ContentShow.collection && !e.isCollectible) return false;
    final r = _range;
    if (r != null) {
      final day = dayOf(e.wallTime);
      if (day.isBefore(r.start) || day.isAfter(r.end)) return false;
    }
    final t = _tag;
    if (t != null && !e.tags.any((x) => x.toLowerCase() == t.toLowerCase())) {
      return false;
    }
    final a = _author;
    if (a != null && e.author != a) return false;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [
        e.title,
        e.text,
        e.place ?? '',
        e.series,
        e.country ?? '',
        ...e.tags,
      ].join('\n').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  List<Entry> apply(Iterable<Entry> entries) => entries.where(matches).toList();
}

/// Local midnight from the date fields only, so it compares safely and suits pickers.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
