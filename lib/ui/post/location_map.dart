import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/theme.dart';
import '../widgets/author.dart';
import '../widgets/osm_map.dart';

class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.point,
    required this.author,
    required this.onTap,
    this.fallbackCenter,
    this.height = 200,
  });

  final LatLng? point;
  final String author;
  final ValueChanged<LatLng> onTap;

  final LatLng? fallbackCenter;
  final double height;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  final _controller = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(LocationMap old) {
    super.didUpdateWidget(old);
    final p = widget.point;
    if (p != null && p != old.point) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(p));
    }
  }

  void _reveal(LatLng p) {
    if (!mounted || !_ready || widget.point != p) return;
    final camera = _controller.camera;
    if (camera.visibleBounds.contains(p)) return;
    _controller.move(p, camera.zoom < 12 ? 14 : camera.zoom);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final fallback = widget.fallbackCenter;
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: kBorderRadius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: point ?? fallback ?? const LatLng(30, 10),
                initialZoom: point != null ? 14 : (fallback != null ? 10 : 2),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () => _ready = true,
                onTap: (_, p) => widget.onTap(p),
              ),
              children: [
                osmTileLayer(),
                if (point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: AuthorPin(
                          color: authorColorOf(context, widget.author),
                        ),
                      ),
                    ],
                  ),
                const OsmAttribution(fontSize: 10),
              ],
            ),
            if (point == null)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.92,
                        ),
                        borderRadius: kBorderRadius,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          'Tap the map to set the location',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
