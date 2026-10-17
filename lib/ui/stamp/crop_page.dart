import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const _handle = 22.0;
const _minSide = 24.0;

Rect clampCrop(Rect r, Size image) {
  final minW = math.min(_minSide, image.width);
  final minH = math.min(_minSide, image.height);
  var left = r.left.clamp(0.0, image.width - minW);
  var top = r.top.clamp(0.0, image.height - minH);
  var right = r.right.clamp(left + minW, image.width);
  var bottom = r.bottom.clamp(top + minH, image.height);
  left = math.min(left, right - minW);
  top = math.min(top, bottom - minH);
  return Rect.fromLTRB(left, top, right, bottom);
}

Rect makeSquare(Rect r, Size image) {
  final side = math.min(
    math.min(r.width, r.height),
    math.min(image.width, image.height),
  );
  final c = r.center;
  final left = (c.dx - side / 2).clamp(0.0, image.width - side);
  final top = (c.dy - side / 2).clamp(0.0, image.height - side);
  return Rect.fromLTWH(left, top, side, side);
}

Rect squareFromCorner({
  required Offset anchor,
  required Offset moved,
  required Size image,
}) {
  final sx = moved.dx >= anchor.dx ? 1.0 : -1.0;
  final sy = moved.dy >= anchor.dy ? 1.0 : -1.0;
  final room = math.min(
    sx > 0 ? image.width - anchor.dx : anchor.dx,
    sy > 0 ? image.height - anchor.dy : anchor.dy,
  );
  final wanted = math.max(
    (moved.dx - anchor.dx).abs(),
    (moved.dy - anchor.dy).abs(),
  );
  final side = wanted.clamp(math.min(_minSide, room), room);
  return Rect.fromPoints(
    anchor,
    Offset(anchor.dx + sx * side, anchor.dy + sy * side),
  );
}

Future<Uint8List> cropToPng(ui.Image image, Rect area) async {
  final w = area.width.round();
  final h = area.height.round();
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    area,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final out = await recorder.endRecording().toImage(w, h);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return data!.buffer.asUint8List();
}

class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.file, this.saved = 0});

  final File file;
  final int saved;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  ui.Image? _image;
  Rect _crop = Rect.zero;
  bool _busy = false;
  bool _square = false;
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
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      setState(() {
        _image = frame.image;
        _crop = _initial(size);
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't open the image");
    }
  }

  Rect _initial(Size s) => Rect.fromLTWH(
    s.width * 0.1,
    s.height * 0.1,
    s.width * 0.8,
    s.height * 0.8,
  );

  Size get _size => Size(_image!.width.toDouble(), _image!.height.toDouble());

  Future<void> _use() async {
    if (_busy || _image == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await cropToPng(_image!, _crop);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't crop: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = widget.saved;
    return Scaffold(
      appBar: AppBar(
        title: Text(saved == 0 ? 'Crop the stamp' : 'Crop another stamp'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(saved == 0 ? 'Cancel' : 'Done'),
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
                : _CropArea(
                    image: _image!,
                    crop: _crop,
                    square: _square,
                    onChanged: (r) => setState(() => _crop = r),
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
                    saved == 0
                        ? 'Drag the corners to frame one stamp. A page with several stamps can be cropped one at a time.'
                        : saved == 1
                        ? '1 stamp saved. Crop another, or tap Done.'
                        : '$saved stamps saved. Crop another, or tap Done.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_error != null && _image != null)
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 4),
                  FilterChip(
                    key: const ValueKey('square'),
                    avatar: const Icon(Icons.crop_square, size: 18),
                    label: const Text('Square 1:1'),
                    selected: _square,
                    onSelected: _image == null || _busy
                        ? null
                        : (v) => setState(() {
                            _square = v;
                            if (v) _crop = makeSquare(_crop, _size);
                          }),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _image == null || _busy
                              ? null
                              : () => setState(() {
                                  final all = Offset.zero & _size;
                                  _crop = _square
                                      ? makeSquare(all, _size)
                                      : all;
                                }),
                          child: const Text('Whole page'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _image == null || _busy ? null : _use,
                          child: const Text('Use crop'),
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

enum _Drag { none, move, tl, tr, bl, br }

class _CropArea extends StatefulWidget {
  const _CropArea({
    required this.image,
    required this.crop,
    required this.square,
    required this.onChanged,
  });

  final ui.Image image;
  final Rect crop;
  final bool square;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropArea> createState() => _CropAreaState();
}

class _CropAreaState extends State<_CropArea> {
  _Drag _drag = _Drag.none;

  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final fit = applyBoxFit(
          BoxFit.contain,
          _imageSize,
          Size(box.maxWidth - 32, box.maxHeight - 32),
        ).destination;
        final origin = Offset(
          (box.maxWidth - fit.width) / 2,
          (box.maxHeight - fit.height) / 2,
        );
        final scale = fit.width / _imageSize.width;

        Rect toScreen(Rect r) => Rect.fromLTWH(
          origin.dx + r.left * scale,
          origin.dy + r.top * scale,
          r.width * scale,
          r.height * scale,
        );

        _Drag pick(Offset p) {
          final s = toScreen(widget.crop);
          final corners = {
            _Drag.tl: s.topLeft,
            _Drag.tr: s.topRight,
            _Drag.bl: s.bottomLeft,
            _Drag.br: s.bottomRight,
          };
          for (final c in corners.entries) {
            if ((c.value - p).distance <= _handle * 1.6) return c.key;
          }
          return s.contains(p) ? _Drag.move : _Drag.none;
        }

        void update(Offset delta) {
          final d = delta / scale;
          final r = widget.crop;
          final next = switch (_drag) {
            _Drag.move => r.shift(d),
            _Drag.tl => Rect.fromLTRB(
              r.left + d.dx,
              r.top + d.dy,
              r.right,
              r.bottom,
            ),
            _Drag.tr => Rect.fromLTRB(
              r.left,
              r.top + d.dy,
              r.right + d.dx,
              r.bottom,
            ),
            _Drag.bl => Rect.fromLTRB(
              r.left + d.dx,
              r.top,
              r.right,
              r.bottom + d.dy,
            ),
            _Drag.br => Rect.fromLTRB(
              r.left,
              r.top,
              r.right + d.dx,
              r.bottom + d.dy,
            ),
            _Drag.none => r,
          };
          if (widget.square &&
              (_drag == _Drag.tl ||
                  _drag == _Drag.tr ||
                  _drag == _Drag.bl ||
                  _drag == _Drag.br)) {
            final anchor = switch (_drag) {
              _Drag.tl => r.bottomRight,
              _Drag.tr => r.bottomLeft,
              _Drag.bl => r.topRight,
              _ => r.topLeft,
            };
            final moved = switch (_drag) {
              _Drag.tl => r.topLeft,
              _Drag.tr => r.topRight,
              _Drag.bl => r.bottomLeft,
              _ => r.bottomRight,
            };
            widget.onChanged(
              squareFromCorner(
                anchor: anchor,
                moved: moved + d,
                image: _imageSize,
              ),
            );
          } else if (_drag == _Drag.move) {
            final w = r.width;
            final h = r.height;
            final left = next.left.clamp(0.0, _imageSize.width - w);
            final top = next.top.clamp(0.0, _imageSize.height - h);
            widget.onChanged(Rect.fromLTWH(left, top, w, h));
          } else {
            widget.onChanged(clampCrop(next, _imageSize));
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (d) => _drag = pick(d.localPosition),
          onPanUpdate: (d) => update(d.delta),
          onPanEnd: (_) => _drag = _Drag.none,
          child: CustomPaint(
            key: const ValueKey('crop-area'),
            size: Size(box.maxWidth, box.maxHeight),
            painter: _CropPainter(
              image: widget.image,
              imageRect: Rect.fromLTWH(
                origin.dx,
                origin.dy,
                fit.width,
                fit.height,
              ),
              crop: toScreen(widget.crop),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.imageRect,
    required this.crop,
    required this.color,
  });

  final ui.Image image;
  final Rect imageRect;
  final Rect crop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: imageRect,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(imageRect),
        Path()..addRect(crop),
      ),
      dim,
    );
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    final thirds = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.35);
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        thirds,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        thirds,
      );
    }
    final fill = Paint()..color = color;
    for (final p in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawCircle(p, 9, fill);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.image != image || old.imageRect != imageRect;
}
