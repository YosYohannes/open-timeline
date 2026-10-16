import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/entry.dart';
import '../../store/journal_store.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';
import '../widgets/osm_map.dart';
import '../widgets/snack.dart';
import 'filters.dart';

const _defaultCenter = LatLng(30, 10);
const _defaultZoom = 2.5;

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.filter, required this.active});

  final EntryFilter filter;
  final bool active;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _controller = MapController();
  late final JournalStore _store;
  bool _ready = false;
  bool _locating = false;
  bool _autoLocated = false;
  LatLng? _me;
  String? _lastSignature;
  RangeValues? _drag;
  Widget? _built;
  List<Marker> _markers = const [];
  String? _markerSignature;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    _store.addListener(_onChange);
    widget.filter.addListener(_onChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    widget.filter.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  void _onChange() {
    if (widget.active && mounted) setState(() {});
  }

  Future<void> _locate({bool quiet = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!quiet) _say('Turn on location services');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && !quiet) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!quiet) {
          _say(
            permission == LocationPermission.deniedForever
                ? 'Allow location for this app in the phone settings'
                : 'Location permission was not granted',
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = here);
      _controller.move(here, math.max(_controller.camera.zoom, 14));
    } on TimeoutException {
      if (!quiet) _say('Could not get your location in time');
    } catch (_) {
      if (!quiet) _say('Could not get your location');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _say(String message) {
    if (mounted) showSnack(context, message);
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

  List<Marker> _markersFor(
    BuildContext context,
    List<Entry> located,
    String signature,
  ) {
    if (signature == _markerSignature) return _markers;
    _markerSignature = signature;
    return _markers = [
      for (final e in located)
        Marker(
          point: LatLng(e.lat!, e.lon!),
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _preview(context, e),
            child: AuthorPin(color: authorColorOf(context, e.author)),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return _built ?? const SizedBox.shrink();
    return _built = _content(context);
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _store.entries;
    final located = widget.filter
        .apply(all)
        .where((e) => e.hasLocation)
        .toList();
    final pts = [for (final e in located) LatLng(e.lat!, e.lon!)];

    final colors = '${_store.settings.myColor}${_store.peopleColors}';
    final signature =
        '$colors|${located.map((e) => '${e.id}@${e.lat},${e.lon}').join('|')}';
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
      onMapReady: () {
        _ready = true;
        if (!_autoLocated && !_store.entries.any((e) => e.hasLocation)) {
          _autoLocated = true;
          _locate(quiet: true);
        }
      },
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
                  if (_me != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _me!,
                          width: 26,
                          height: 26,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF4A4A4A),
                                width: 6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      maxClusterRadius: 60,
                      size: const Size(40, 40),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(50),
                      maxZoom: 16,
                      markers: _markersFor(context, located, signature),
                      builder: (context, markers) => Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: kBorderRadius,
                          border: Border.all(color: scheme.primary),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${markers.length}',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
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
                  backgroundColor: scheme.surface.withValues(alpha: 0.92),
                ),
              ),
              Positioned(
                top: 4,
                right: 8,
                child: Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Fit to posts',
                      icon: const Icon(Icons.center_focus_strong_outlined),
                      onPressed: pts.isEmpty ? null : () => _fit(pts),
                    ),
                    const SizedBox(height: 8),
                    IconButton.filledTonal(
                      tooltip: 'My location',
                      icon: _locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      onPressed: _locating ? null : _locate,
                    ),
                  ],
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
                      radius: kRadius,
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
                          ],
                        ),
                        if (e.title.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
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
