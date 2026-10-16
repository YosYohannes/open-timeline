import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';
import '../widgets/osm_map.dart';
import 'filters.dart';

const _defaultCenter = LatLng(30, 10);
const _defaultZoom = 2.5;

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.filter});

  final EntryFilter filter;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _controller = MapController();
  bool _ready = false;
  String? _lastSignature;
  RangeValues? _drag;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit(List<LatLng> pts) {
    if (!_ready || !mounted || pts.isEmpty) return;
    try {
      if (_isSinglePoint(pts)) {
        _controller.move(pts.first, 13);
      } else {
        _controller.fitCamera(
          CameraFit.coordinates(
            coordinates: pts,
            padding: const EdgeInsets.fromLTRB(48, 72, 48, 56),
            maxZoom: 16,
          ),
        );
      }
    } catch (_) {
      // Map not laid out yet; the next change will fit again.
    }
  }

  static bool _isSinglePoint(List<LatLng> pts) {
    final f = pts.first;
    return pts.every(
      (p) => p.latitude == f.latitude && p.longitude == f.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: widget.filter,
      builder: (context, _) {
        final all = store.entries;
        final located = widget.filter
            .apply(all)
            .where((e) => e.hasLocation)
            .toList();
        final pts = [for (final e in located) LatLng(e.lat!, e.lon!)];

        final signature = located
            .map((e) => '${e.id}@${e.lat},${e.lon}')
            .join('|');
        if (signature != _lastSignature) {
          final first = _lastSignature == null;
          _lastSignature = signature;
          if (!first) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit(pts));
          }
        }

        final options = MapOptions(
          initialCenter: pts.isEmpty ? _defaultCenter : pts.first,
          initialZoom: pts.isEmpty ? _defaultZoom : 13,
          initialCameraFit: pts.length > 1 && !_isSinglePoint(pts)
              ? CameraFit.coordinates(
                  coordinates: pts,
                  padding: const EdgeInsets.fromLTRB(48, 72, 48, 56),
                  maxZoom: 16,
                )
              : null,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () => _ready = true,
        );

        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: options,
                    children: [
                      osmTileLayer(),
                      MarkerLayer(
                        markers: [
                          for (final e in located)
                            Marker(
                              point: LatLng(e.lat!, e.lon!),
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _preview(context, e),
                                child: AuthorPin(author: e.author),
                              ),
                            ),
                        ],
                      ),
                      const OsmAttribution(),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    left: 12,
                    child: Chip(
                      avatar: const Icon(Icons.place, size: 18),
                      label: Text(
                        located.isEmpty
                            ? 'No posts with a location'
                            : '${located.length} on map',
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.92),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Fit to posts',
                      icon: const Icon(Icons.center_focus_strong_outlined),
                      onPressed: pts.isEmpty ? null : () => _fit(pts),
                    ),
                  ),
                ],
              ),
            ),
            _DateSlider(
              all: all,
              filter: widget.filter,
              drag: _drag,
              onDrag: (v) => setState(() => _drag = v),
              onDone: () => setState(() => _drag = null),
            ),
          ],
        );
      },
    );
  }

  void _preview(BuildContext context, Entry e) {
    final store = StoreScope.read(context);
    final theme = Theme.of(context);
    final media = e.media.where((m) => isImage(m) || isVideo(m)).firstOrNull;
    final text = e.text.trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: InkWell(
            onTap: () {
              Navigator.pop(sheetContext);
              openEntry(context, e.id);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (media != null) ...[
                    MediaTile(
                      file: store.mediaFile(e, media),
                      name: media,
                      size: 96,
                      radius: 12,
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AuthorDot(author: e.author),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${formatLongDay(e)} · ${formatTime(e)}',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (e.starred)
                              const Icon(
                                Icons.star_rounded,
                                size: 20,
                                color: Color(0xFFF2B01E),
                              ),
                          ],
                        ),
                        if (placeText(e) != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  placeText(e)!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            text,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              openEntry(context, e.id);
                            },
                            child: const Text('Open'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

class _DateSlider extends StatelessWidget {
  const _DateSlider({
    required this.all,
    required this.filter,
    required this.drag,
    required this.onDrag,
    required this.onDone,
  });

  final List<Entry> all;
  final EntryFilter filter;
  final RangeValues? drag;
  final ValueChanged<RangeValues> onDrag;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    if (all.isEmpty) return const SizedBox.shrink();
    var first = dayOf(all.first.wallTime);
    var last = first;
    for (final e in all) {
      final d = dayOf(e.wallTime);
      if (d.isBefore(first)) first = d;
      if (d.isAfter(last)) last = d;
    }
    final total = _daysBetween(first, last);
    final theme = Theme.of(context);
    if (total < 1) {
      return Padding(
        // leave room for the FAB on the right
        padding: const EdgeInsets.fromLTRB(16, 10, 88, 14),
        child: Text(
          'All posts are from ${formatShortDay(first)}',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final range = filter.range;
    final values =
        drag ??
        RangeValues(
          range == null
              ? 0
              : _daysBetween(first, range.start).clamp(0, total).toDouble(),
          range == null
              ? total.toDouble()
              : _daysBetween(first, range.end).clamp(0, total).toDouble(),
        );
    final startDay = _addDays(first, values.start.round());
    final endDay = _addDays(first, values.end.round());

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        // leave room for the FAB on the right
        padding: const EdgeInsets.fromLTRB(16, 8, 88, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.date_range,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    startDay == endDay
                        ? formatShortDay(startDay)
                        : '${formatShortDay(startDay)}  –  ${formatShortDay(endDay)}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            RangeSlider(
              values: values,
              min: 0,
              max: total.toDouble(),
              divisions: total,
              labels: RangeLabels(
                formatShortDay(startDay),
                formatShortDay(endDay),
              ),
              onChanged: onDrag,
              onChangeEnd: (v) {
                final s = v.start.round();
                final e = v.end.round();
                filter.range = (s == 0 && e == total)
                    ? null
                    : DateTimeRange(
                        start: _addDays(first, s),
                        end: _addDays(first, e),
                      );
                onDone();
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatShortDay(first), style: theme.textTheme.labelSmall),
                Text(formatShortDay(last), style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
