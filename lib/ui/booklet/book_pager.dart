import 'dart:math' as math;

import 'package:flutter/material.dart';

class BookController extends ChangeNotifier {
  _BookPagerState? _state;

  double get position => _state?._anim.value ?? 0;

  int get page => position.round();

  void goTo(int page) => _state?._goTo(page);

  void _changed() => notifyListeners();
}

class BookPager extends StatefulWidget {
  const BookPager({super.key, required this.pages, required this.controller});

  final List<Widget> pages;
  final BookController controller;

  @override
  State<BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends State<BookPager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController.unbounded(
    vsync: this,
    value: 0,
  )..addListener(widget.controller._changed);

  int get _last => math.max(0, widget.pages.length - 1);

  int _dragFrom = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(BookPager old) {
    super.didUpdateWidget(old);
    widget.controller._state = this;
    if (_anim.value > _last) _anim.value = _last.toDouble();
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _anim.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final target = page.clamp(0, _last);
    final distance = (target - _anim.value).abs();
    _anim.animateTo(
      target.toDouble(),
      duration: Duration(
        milliseconds: (320 + 90 * distance).round().clamp(320, 900),
      ),
      curve: Curves.easeInOutCubic,
    );
  }

  void _dragStart(DragStartDetails d) {
    _anim.stop();
    _dragFrom = _anim.value.round();
  }

  void _dragUpdate(DragUpdateDetails d, double width) {
    final lo = math.max(0, _dragFrom - 1).toDouble();
    final hi = math.min(_last, _dragFrom + 1).toDouble();
    _anim.value = (_anim.value - d.delta.dx / width * 1.4).clamp(lo, hi);
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    var target = _anim.value.round();
    if (v < -350) {
      target = _dragFrom + 1;
    } else if (v > 350) {
      target = _dragFrom - 1;
    }
    _goTo(target.clamp(_dragFrom - 1, _dragFrom + 1));
  }

  Widget _turning(Widget page, double frac, Size size) {
    if (frac <= 0) return page;
    final theta = frac * math.pi;
    final curl = 0.6 * math.sin(frac * math.pi);
    final stripWidth = size.width / _strips;
    final strips = <Widget>[];
    var x = 0.0;
    var z = 0.0;
    for (var k = 0; k < _strips; k++) {
      final t = (k + 1) / _strips;
      final angle = theta * ((1 - curl) + curl * math.pow(t, 1.6));
      final back = angle > math.pi / 2;
      final shade = back ? 0.2 : 0.3 * math.sin(angle);
      strips.add(
        Transform(
          transform: Matrix4.identity()
            ..translateByDouble(x, 0, z, 1)
            ..rotateY(angle)
            ..translateByDouble(-k * stripWidth, 0, 0, 1),
          child: SizedBox.fromSize(
            size: size,
            child: ClipRect(
              clipper: _Strip(k * stripWidth, stripWidth + 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  back ? const ColoredBox(color: kPaperBack) : page,
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: shade),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      x += stripWidth * math.cos(angle);
      z -= stripWidth * math.sin(angle);
    }
    return ClipRect(
      clipper: const _FromSpine(),
      child: Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.identity()..setEntry(3, 2, 0.0011),
        child: Stack(fit: StackFit.expand, children: strips),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(1.0, box.maxWidth);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: (d) => _dragUpdate(d, width),
          onHorizontalDragEnd: _dragEnd,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final p = _anim.value.clamp(0.0, _last.toDouble());
              final i = p.floor().clamp(0, _last);
              final frac = (p - i).clamp(0.0, 1.0);
              final hasNext = i + 1 <= _last && frac > 0.001;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (hasNext)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        KeyedSubtree(
                          key: ValueKey(i + 1),
                          child: widget.pages[i + 1],
                        ),
                        IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: (1 - frac) * 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  KeyedSubtree(
                    key: ValueKey(i),
                    child: _turning(
                      widget.pages[i],
                      hasNext ? frac : 0,
                      box.biggest,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

const kPaperBack = Color(0xFFE4DAC4);
const _strips = 12;

class _Strip extends CustomClipper<Rect> {
  const _Strip(this.left, this.width);

  final double left;
  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(left, 0, width, size.height);

  @override
  bool shouldReclip(_Strip old) => old.left != left || old.width != width;
}

class _FromSpine extends CustomClipper<Rect> {
  const _FromSpine();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -100, size.width + 100, size.height + 100);

  @override
  bool shouldReclip(_FromSpine old) => false;
}
