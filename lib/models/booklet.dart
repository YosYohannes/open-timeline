import 'countries.dart';
import 'entry.dart';

class Section {
  const Section({required this.series, required this.stamps});

  final String series;
  final List<Entry> stamps;
}

class Booklet {
  const Booklet({required this.country, required this.sections});

  final String? country;
  final List<Section> sections;

  String get name => country == null ? 'Unsorted' : countryName(country!);

  int get count => sections.fold(0, (n, s) => n + s.stamps.length);

  Iterable<Entry> get stamps => sections.expand((s) => s.stamps);

  DateTime get first =>
      stamps.map((e) => e.wallTime).reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime get last =>
      stamps.map((e) => e.wallTime).reduce((a, b) => a.isAfter(b) ? a : b);

  Entry get latest =>
      stamps.reduce((a, b) => b.wallTime.isAfter(a.wallTime) ? b : a);
}

int _byTime(Entry a, Entry b) {
  final c = a.wallTime.compareTo(b.wallTime);
  return c != 0 ? c : a.id.compareTo(b.id);
}

List<Booklet> buildBooklets(Iterable<Entry> entries) {
  final byCountry = <String?, Map<String, List<Entry>>>{};
  for (final e in entries) {
    if (!e.isCollectible || e.deleted) continue;
    final code = (e.country == null || e.country!.isEmpty) ? null : e.country;
    ((byCountry[code] ??= {})[e.series.trim()] ??= []).add(e);
  }
  final booklets = <Booklet>[];
  for (final entry in byCountry.entries) {
    final sections = [
      for (final s in entry.value.entries)
        Section(series: s.key, stamps: [...s.value]..sort(_byTime)),
    ];
    sections.sort((a, b) {
      if (a.series.isEmpty != b.series.isEmpty) {
        return a.series.isEmpty ? 1 : -1;
      }
      return _byTime(a.stamps.first, b.stamps.first);
    });
    booklets.add(Booklet(country: entry.key, sections: sections));
  }
  booklets.sort((a, b) {
    if ((a.country == null) != (b.country == null)) {
      return a.country == null ? 1 : -1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return booklets;
}
