import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmUserAgent = 'com.opentimeline.open_timeline';

TileLayer osmTileLayer() =>
    TileLayer(urlTemplate: osmTileUrl, userAgentPackageName: osmUserAgent);

// Required by the OSM tile usage policy.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key, this.fontSize = 11});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)),
          ),
          child: Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: fontSize, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}
