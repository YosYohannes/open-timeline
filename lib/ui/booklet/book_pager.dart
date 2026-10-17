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

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    var target = _anim.value.round();
    if (v < -350) {
      target = _anim.value.floor() + 1;
    } else if (v > 350) {
      target = _anim.value.ceil() - 1;
    }
    _goTo(target);
  }

  Widget _turning(Widget page, double frac) {
    final angle = frac * math.pi * 0.72;
    if (angle >= math.pi / 2) return const SizedBox.shrink();
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..rotateY(angle),
      child: Stack(
        fit: StackFit.expand,
        children: [
          page,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: frac * 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
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
          onHorizontalDragStart: (_) => _anim.stop(),
          onHorizontalDragUpdate: (d) =>
              _anim.value = (_anim.value - d.delta.dx / width * 1.4).clamp(
                0.0,
                _last.toDouble(),
              ),
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
                    child: _turning(widget.pages[i], hasNext ? frac : 0),
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
