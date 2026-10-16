import 'package:flutter/material.dart';

import '../../store/journal_store.dart';
import '../app/store_scope.dart';

const kAuthorPalette = <Color>[
  Color(0xFF9DBB9A),
  Color(0xFF8FAEC9),
  Color(0xFFB5A4D4),
  Color(0xFFD4A0A8),
  Color(0xFFD3BE8F),
  Color(0xFFD9A98A),
  Color(0xFF8CC0BC),
  Color(0xFFB0B0B0),
];

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

Color defaultAuthorColor(String author) =>
    kAuthorPalette[_fnv1a(author.toLowerCase()) % kAuthorPalette.length];

Color authorColorFor(JournalStore store, String author) {
  final key = author.toLowerCase();
  final mine = store.settings.myColor;
  if (mine != null && store.settings.me.trim().toLowerCase() == key) {
    return Color(mine);
  }
  final shared = store.peopleColors[key];
  return shared == null ? defaultAuthorColor(author) : Color(shared);
}

Color authorColorOf(BuildContext context, String author) =>
    authorColorFor(StoreScope.of(context), author);

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
          color: authorColorOf(context, author),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class AuthorPin extends StatelessWidget {
  const AuthorPin({super.key, required this.color, this.size = 40});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Icon(Icons.location_on, size: size + 4, color: Colors.black),
        Icon(Icons.location_on, size: size, color: color),
      ],
    );
  }
}
