import 'dart:math' as math;

import 'package:flutter/material.dart';

const kCoverPaper = Color(0xFFC79F73);
const kCoverInk = Color(0xFF2B2B2B);
const _plainBand = Color(0xFF55585A);

Color _c(String hex) => Color(0xFF000000 | int.parse(hex, radix: 16));

class FlagCanvas {
  FlagCanvas(this.canvas, this.size);

  final Canvas canvas;
  final Size size;

  double get w => size.width;
  double get h => size.height;

  Offset at(double u, double v) => Offset(v * w, (1 - u) * h);

  Offset nat(double along, double across, double hoist) =>
      Offset(across * w / hoist, h - along * w / hoist);

  double sc(double units, double hoist) => units * w / hoist;

  Paint _p(Color c) => Paint()..color = c;

  void fill(Color c) => canvas.drawRect(Offset.zero & size, _p(c));

  void bandsH(List<Color> colors, [List<double>? weights]) {
    final ws = weights ?? List.filled(colors.length, 1.0);
    final total = ws.fold(0.0, (a, b) => a + b);
    var x = 0.0;
    for (var i = 0; i < colors.length; i++) {
      final next = x + ws[i] / total * w;
      canvas.drawRect(Rect.fromLTRB(x, 0, next + 0.5, h), _p(colors[i]));
      x = next;
    }
  }

  void disc(Offset c, double r, Color color) =>
      canvas.drawCircle(c, r, _p(color));

  void rect(Rect r, Color color) => canvas.drawRect(r, _p(color));

  void block(double length, double x0, double x1, Color color) =>
      rect(Rect.fromLTRB(x0, h - length, x1, h), color);

  void star(Offset c, double r, Color color, {int points = 5}) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? r : r * (points == 5 ? 0.4 : 0.55);
      final a = -math.pi / 2 + i * math.pi / points;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), _p(color));
  }

  void triangle(Offset a, Offset b, Offset c, Color color) {
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      _p(color),
    );
  }

  void centered(double hoist, void Function(Canvas c) draw) {
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-math.pi / 2);
    canvas.scale(w / hoist);
    draw(canvas);
    canvas.restore();
  }

  void turned(double hoist, void Function(Canvas c) draw) {
    canvas.save();
    canvas.translate(0, h);
    canvas.rotate(-math.pi / 2);
    canvas.scale(w / hoist);
    draw(canvas);
    canvas.restore();
  }

  void cluster(Offset c, double ring, double r, Color color, {int count = 5}) {
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / count;
      disc(c + Offset(math.cos(a), math.sin(a)) * ring, r, color);
    }
  }
}

typedef _Draw = void Function(FlagCanvas f);

void _stripesFlag(FlagCanvas f, List<String> hexes, {List<double>? weights}) {
  final colors = hexes.map(_c).toList();
  f.bandsH(colors, weights);
}

final Map<String, _Draw> _flags = {
  'JP': (f) {
    f.fill(_c('FFFFFF'));
    f.disc(f.at(0.5, 0.5), f.w * 0.36, _c('BC002D'));
  },
  'TW': (f) {
    f.fill(_c('FE0000'));
    f.block(f.w * 1.3, 0, f.w * 0.5, _c('000095'));
    f.disc(Offset(f.w * 0.25, f.h - f.w * 0.65), f.w * 0.15, _c('FFFFFF'));
  },
  'KR': (f) {
    f.fill(_c('FFFFFF'));
    f.centered(60, (c) {
      final theta = math.atan2(2, 3);
      c.save();
      c.rotate(-theta);
      c.clipPath(
        Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 15)),
      );
      f.rect(const Rect.fromLTRB(-15, -15, 15, 0), _c('CD2E3A'));
      f.rect(const Rect.fromLTRB(-15, 0, 15, 15), _c('0047A0'));
      f.disc(const Offset(-7.5, 0), 7.5, _c('CD2E3A'));
      f.disc(const Offset(7.5, 0), 7.5, _c('0047A0'));
      c.restore();
      for (final (sx, sy, solid) in [
        (-1.0, -1.0, [true, true, true]),
        (1.0, -1.0, [false, true, false]),
        (-1.0, 1.0, [true, false, true]),
        (1.0, 1.0, [false, false, false]),
      ]) {
        c.save();
        final dir = Offset(sx * math.cos(theta), sy * math.sin(theta));
        c.translate(dir.dx * 30, dir.dy * 30);
        c.rotate(dir.direction - math.pi / 2);
        for (var i = 0; i < 3; i++) {
          final y = (i - 1) * 4.5;
          if (solid[i]) {
            f.rect(
              Rect.fromCenter(center: Offset(0, y), width: 15, height: 2.5),
              _c('000000'),
            );
          } else {
            for (final x in [-4.25, 4.25]) {
              f.rect(
                Rect.fromCenter(center: Offset(x, y), width: 6.5, height: 2.5),
                _c('000000'),
              );
            }
          }
        }
        c.restore();
      }
    });
  },
  'CN': (f) {
    f.fill(_c('DE2910'));
    f.star(f.nat(5, 5, 20), f.sc(3, 20), _c('FFDE00'));
    for (final p in [(10.0, 2.0), (12.0, 4.0), (12.0, 7.0), (10.0, 9.0)]) {
      f.star(f.nat(p.$1, p.$2, 20), f.sc(1, 20), _c('FFDE00'));
    }
  },
  'HK': (f) {
    f.fill(_c('DE2910'));
    f.cluster(f.at(0.5, 0.5), f.w * 0.17, f.w * 0.11, _c('FFFFFF'));
  },
  'SG': (f) {
    f.bandsH([_c('EF3340'), _c('FFFFFF')]);
    f.turned(60, (c) {
      f.disc(const Offset(21, 15), 11, _c('FFFFFF'));
      f.disc(const Offset(25, 15), 9.5, _c('EF3340'));
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / 5;
        f.star(
          const Offset(27, 15) + Offset(math.cos(a), math.sin(a)) * 5.2,
          2.6,
          _c('FFFFFF'),
        );
      }
    });
  },
  'TH': (f) => _stripesFlag(
    f,
    ['A51931', 'F4F5F8', '2D2A4A', 'F4F5F8', 'A51931'],
    weights: [1, 1, 2, 1, 1],
  ),
  'VN': (f) {
    f.fill(_c('DA251D'));
    f.star(f.at(0.5, 0.5), f.w * 0.38, _c('FFFF00'));
  },
  'MY': (f) {
    f.bandsH([for (var i = 0; i < 14; i++) _c(i.isEven ? 'CC0001' : 'FFFFFF')]);
    f.turned(14, (c) {
      f.rect(const Rect.fromLTWH(0, 0, 14, 8), _c('010066'));
      f.disc(const Offset(5.3, 4), 3, _c('FFCC00'));
      f.disc(const Offset(6.2, 4), 2.5, _c('010066'));
      f.star(const Offset(8.8, 4), 2.7, _c('FFCC00'), points: 14);
    });
  },
  'ID': (f) => _stripesFlag(f, ['CE1126', 'FFFFFF']),
  'PH': (f) {
    f.bandsH([_c('0038A8'), _c('CE1126')]);
    f.turned(10, (c) {
      const sun = Offset(2.9, 5);
      f.triangle(
        const Offset(0, 0),
        const Offset(0, 10),
        const Offset(8.66, 5),
        _c('FFFFFF'),
      );
      f.disc(sun, 1.0, _c('FCD116'));
      final ray = Paint()
        ..color = _c('FCD116')
        ..strokeWidth = 0.25;
      for (var i = 0; i < 24; i++) {
        final a = i * math.pi / 12;
        final d = Offset(math.cos(a), math.sin(a));
        c.drawLine(sun + d * 1.2, sun + d * (i % 3 == 1 ? 1.9 : 1.55), ray);
      }
      for (final p in [(0.9, 0.9), (0.9, 9.1), (7.2, 5.0)]) {
        f.star(Offset(p.$1, p.$2), 0.9, _c('FCD116'));
      }
    });
  },
};

bool hasFlagSpine(String code) => _flags.containsKey(code);

int get flagSpineCount => _flags.length;

void paintFlagSpine(Canvas canvas, Size size, String? country) {
  final draw = country == null ? null : _flags[country];
  final f = FlagCanvas(canvas, size);
  if (draw == null) {
    f.fill(_plainBand);
  } else {
    draw(f);
  }
}

class FlagSpine extends StatelessWidget {
  const FlagSpine({super.key, required this.country});

  final String? country;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: _SpinePainter(country),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter(this.country);

  final String? country;

  @override
  void paint(Canvas canvas, Size size) => paintFlagSpine(canvas, size, country);

  @override
  bool shouldRepaint(_SpinePainter old) => old.country != country;
}
