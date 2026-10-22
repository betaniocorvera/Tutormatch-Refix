// ─────────────────────────────────────────────────────────────────────────────
// One entrance, used everywhere something arrives in a list.
//
// The product reveals in a single direction — 12 px up, opacity from nothing,
// 420 ms on an ease-out curve — because a page where every element invents its
// own arrival reads as noise. Lists pass a small delay per item so the eye can
// follow the order.
//
// Under MediaQuery.disableAnimations the child is simply present: no timer, no
// controller, no invisible widget waiting to be tapped.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class TMReveal extends StatefulWidget {
  const TMReveal({
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
    this.duration = Motion.reveal,
    this.curve = Motion.emphasized,
    super.key,
  });

  final Widget child;
  final Duration delay;

  /// Pixels travelled. Vertical by default; a page-level reveal can pass 0.
  final double offset;
  final Duration duration;
  final Curve curve;

  @override
  State<TMReveal> createState() => _TMRevealState();
}

class _TMRevealState extends State<TMReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;
  bool _scheduled = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    _still = Motion.reduced(context);
    if (_still) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = widget.curve.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: IgnorePointer(
              ignoring: t < 0.92,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
