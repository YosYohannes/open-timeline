import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app/theme.dart';

const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmUserAgent = 'com.opentimeline.open_timeline';

TileLayer osmTileLayer() => TileLayer(
  urlTemplate: osmTileUrl,
  userAgentPackageName: osmUserAgent,
  tileBuilder: darkModeTileBuilder,
);

// Required by the OSM tile usage policy.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key, this.fontSize = 11});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(kRadius),
            ),
          ),
          child: Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: fontSize, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
