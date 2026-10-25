import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Popped from the detection screen to crop the stamps by hand instead.
class CropByHand {
  const CropByHand();
}

/// Shows the picture with a box around every stamp the phone found. Pops the
/// boxes that are still ticked, as fractions of the picture, [CropByHand], or
/// null when the user cancels.
class DetectedStampsPage extends StatefulWidget {
  const DetectedStampsPage({
    super.key,
    required this.file,
    required this.boxes,
  });

  final File file;
  final List<Rect> boxes;

  @override
  State<DetectedStampsPage> createState() => _DetectedStampsPageState();
}

class _DetectedStampsPageState extends State<DetectedStampsPage> {
  ui.Image? _image;
  late final Set<int> _on = {for (var i = 0; i < widget.boxes.length; i++) i};
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
        targetWidth: 1400,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open the picture");
    }
  }

  void _tap(Offset p, Rect shown) {
    if (!shown.contains(p)) return;
    final u = (p.dx - shown.left) / shown.width;
    final v = (p.dy - shown.top) / shown.height;
    int? best;
    for (var i = 0; i < widget.boxes.length; i++) {
      final b = widget.boxes[i];
      if (!b.contains(Offset(u, v))) continue;
      if (best == null ||
          b.width * b.height <
              widget.boxes[best].width * widget.boxes[best].height) {
        best = i;
      }
    }
    if (best == null) return;
    final hit = best;
    setState(() => _on.contains(hit) ? _on.remove(hit) : _on.add(hit));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _on.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.boxes.length == 1
              ? 'Found 1 stamp'
              : 'Found ${widget.boxes.length} stamps',
        ),
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
                        key: const ValueKey('detected-area'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _tap(d.localPosition, shown),
                        child: CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _BoxesPainter(
                            image: image,
                            shown: shown,
                            boxes: widget.boxes,
                            on: Set.of(_on),
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
                    'Tap a box to leave that one out.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('by-hand'),
                          onPressed: () =>
                              Navigator.of(context).pop(const CropByHand()),
                          child: const Text('Crop by hand'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('use-found'),
                          onPressed: count == 0
                              ? null
                              : () => Navigator.of(context).pop([
                                  for (final i in _on.toList()..sort())
                                    widget.boxes[i],
                                ]),
                          child: Text(
                            count == 1 ? 'Use 1 stamp' : 'Use $count stamps',
                          ),
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

class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.image,
    required this.shown,
    required this.boxes,
    required this.on,
    required this.color,
  });

  final ui.Image image;
  final Rect shown;
  final List<Rect> boxes;
  final Set<int> on;
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
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      final r = Rect.fromLTWH(
        shown.left + b.left * shown.width,
        shown.top + b.top * shown.height,
        b.width * shown.width,
        b.height * shown.height,
      );
      final selected = on.contains(i);
      if (!selected) {
        canvas.drawRect(
          r,
          Paint()..color = Colors.black.withValues(alpha: 0.55),
        );
      }
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 1.5
          ..color = selected ? color : Colors.white54,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tag = Rect.fromLTWH(
        r.left,
        r.top,
        label.width + 10,
        label.height + 4,
      );
      canvas.drawRect(tag, Paint()..color = selected ? color : Colors.black54);
      label.paint(canvas, Offset(tag.left + 5, tag.top + 2));
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) =>
      !setEquals(old.on, on) || old.image != image || old.shown != shown;
}
