// ─────────────────────────────────────────────────────────────────────────────
// A two-sided card that turns around its own vertical axis.
//
// The profile preview is the one place in the product where a surface has two
// faces: your profile as you wrote it, and the card a tutor would read. The
// turn is 500 ms and it is a real turn — a perspective matrix, a single face
// visible at a time, and the back face counter-rotated so its text is never
// mirrored.
//
// Under reduced motion the card swaps instantly. It is controlled by [flipped],
// so the button that asks for the other side keeps its own state and its own
// accessible label.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class FlipCard extends StatefulWidget {
  const FlipCard({
    required this.front,
    required this.back,
    required this.flipped,
    this.duration = Motion.flip,
    this.onTap,
    super.key,
  });

  final Widget front;
  final Widget back;
  final bool flipped;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipped == widget.flipped) return;
    if (Motion.reduced(context)) {
      _controller.value = widget.flipped ? 1 : 0;
    } else {
      widget.flipped ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return _TapWrap(
        onTap: widget.onTap,
        child: widget.flipped ? widget.back : widget.front,
      );
    }

    return _TapWrap(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeInOutCubic.transform(_controller.value);
          final double angle = t * math.pi;
          final bool showBack = angle >= math.pi / 2;

          // Only one face is in the tree at a time. That is the whole of
          // back-face hiding: the back is not merely covered, it is absent.
          final Widget face = showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: widget.back,
                )
              : widget.front;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: face,
          );
        },
      ),
    );
  }
}

class _TapWrap extends StatelessWidget {
  const _TapWrap({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}
