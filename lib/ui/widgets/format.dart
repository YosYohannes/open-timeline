import 'package:intl/intl.dart';

import '../../models/entry.dart';

final _timeFmt = DateFormat('HH:mm');
final _dayFmt = DateFormat('EEE d MMM yyyy');
final _longDayFmt = DateFormat('EEEE d MMMM yyyy');
final _shortDayFmt = DateFormat('d MMM yyyy');

String formatTime(Entry e) => _timeFmt.format(e.wallTime);
String formatDayHeader(DateTime day) => _dayFmt.format(day);
String formatLongDay(Entry e) => _longDayFmt.format(e.wallTime);
String formatShortDay(DateTime day) => _shortDayFmt.format(day);

String formatCoords(double lat, double lon) =>
    '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

String? placeText(Entry e) {
  final p = e.place?.trim();
  if (p != null && p.isNotEmpty) return p;
  if (e.hasLocation) return formatCoords(e.lat!, e.lon!);
  return null;
}
