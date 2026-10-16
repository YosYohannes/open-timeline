import 'package:flutter/material.dart';

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

Color authorColor(String author) {
  final h = _fnv1a(author.toLowerCase());
  final hue = (h % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.62, 0.46).toColor();
}

class AuthorDot extends StatelessWidget {
  const AuthorDot({super.key, required this.author, this.size = 10});

  final String author;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: author,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: authorColor(author),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Anchor with `Alignment.topCenter` so the tip sits on the coordinate.
class AuthorPin extends StatelessWidget {
  const AuthorPin({super.key, required this.author, this.size = 40});

  final String author;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Icon(Icons.location_on, size: size + 4, color: Colors.white),
        Icon(Icons.location_on, size: size, color: authorColor(author)),
      ],
    );
  }
}
