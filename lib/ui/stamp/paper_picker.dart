import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The average colour of the pixels within [radius] of ([x], [y]).
Color sampleColor(
  Uint8List rgba,
  int width,
  int height,
  int x,
  int y, {
  int radius = 3,
}) {
  var r = 0, g = 0, b = 0, n = 0;
  for (var yy = y - radius; yy <= y + radius; yy++) {
    for (var xx = x - radius; xx <= x + radius; xx++) {
      if (xx < 0 || yy < 0 || xx >= width || yy >= height) continue;
      final i = (yy * width + xx) * 4;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
  }
  if (n == 0) return Colors.white;
  return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

String hexOf(Color c) {
  String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

/// Shows the picture and lets the user tap the paper. Pops the picked colour
/// as `#RRGGBB`, an empty string for "find it automatically", or null.
class PaperPickerPage extends StatefulWidget {
  const PaperPickerPage({super.key, required this.file});

  final File file;

  @override
  State<PaperPickerPage> createState() => _PaperPickerPageState();
}

class _PaperPickerPageState extends State<PaperPickerPage> {
  ui.Image? _image;
  Uint8List? _rgba;
  Offset? _spot;
  Color? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(
        await widget.file.readAsBytes(),
        targetWidth: 1200,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (!mounted || data == null) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        _rgba = data.buffer.asUint8List();
      });
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open the image");
    }
  }

  void _tap(Offset local, Rect shown) {
    final image = _image;
    final rgba = _rgba;
    if (image == null || rgba == null || !shown.contains(local)) return;
    final x = ((local.dx - shown.left) / shown.width * image.width)
        .floor()
        .clamp(0, image.width - 1);
    final y = ((local.dy - shown.top) / shown.height * image.height)
        .floor()
        .clamp(0, image.height - 1);
    setState(() {
      _spot = local;
      _picked = sampleColor(rgba, image.width, image.height, x, y);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _picked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap the paper'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _image == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Text(_error!),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final image = _image!;
                      final size = applyBoxFit(
                        BoxFit.contain,
                        Size(image.width.toDouble(), image.height.toDouble()),
                        Size(box.maxWidth - 32, box.maxHeight - 32),
                      ).destination;
                      final shown = Rect.fromLTWH(
                        (box.maxWidth - size.width) / 2,
                        (box.maxHeight - size.height) / 2,
                        size.width,
                        size.height,
                      );
                      return GestureDetector(
                        key: const ValueKey('paper-area'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _tap(d.localPosition, shown),
                        child: CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _PickerPainter(
                            image: image,
                            shown: shown,
                            spot: _spot,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    picked == null
                        ? 'Tap the paper around the stamp. Everything that '
                              'colour, touching the edge, is removed.'
                        : 'Paper colour ${hexOf(picked)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('paper-auto'),
                          onPressed: () => Navigator.of(context).pop(''),
                          child: const Text('Automatic'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('paper-use'),
                          onPressed: picked == null
                              ? null
                              : () => Navigator.of(context).pop(hexOf(picked)),
                          child: const Text('Use this colour'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerPainter extends CustomPainter {
  _PickerPainter({
    required this.image,
    required this.shown,
    required this.spot,
    required this.color,
  });

  final ui.Image image;
  final Rect shown;
  final Offset? spot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: shown,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    final at = spot;
    if (at == null) return;
    canvas.drawCircle(
      at,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.black,
    );
    canvas.drawCircle(
      at,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PickerPainter old) =>
      old.spot != spot || old.image != image || old.shown != shown;
}
