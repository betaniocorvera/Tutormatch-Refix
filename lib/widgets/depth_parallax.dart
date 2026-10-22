// ─────────────────────────────────────────────────────────────────────────────
// Layered depth for the landing hero.
//
// Three planes — a measured grid, the neighbour map, and the words — move by
// different fractions of the same pointer and scroll. The nearest plane barely
// moves; the furthest one travels several times as far. That difference is the
// entire effect. There is no blur, no gradient, no floating card.
//
// The pointer is read by one MouseRegion at the top of the stack, not by each
// layer, so every plane is guaranteed to share one origin. Under reduced motion
// or on a very narrow phone, all layers are flat.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class DepthParallax extends StatefulWidget {
  const DepthParallax({
    required this.child,
    this.maxShift = 18,
    this.scrollShift = 26,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Maximum pointer travel at depth 1.0, in pixels.
  final double maxShift;

  /// Maximum scroll travel at depth 1.0, in pixels.
  final double scrollShift;
  final bool enabled;

  @override
  State<DepthParallax> createState() => _DepthParallaxState();
}

class _DepthParallaxState extends State<DepthParallax> {
  Offset _pointer = Offset.zero;
  double _scroll = 0;
  Size _size = Size.zero;
  ScrollPosition? _position;
  bool _live = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _live = widget.enabled &&
        !Motion.reduced(context) &&
        MediaQuery.sizeOf(context).width >= AppBreakpoints.flat3d;

    final ScrollPosition? next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_onScroll);
      _position = next;
      if (_live) _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final double next = _position?.pixels ?? 0;
    if ((next - _scroll).abs() < 0.5) return;
    setState(() => _scroll = next);
  }

  void _onHover(PointerHoverEvent event) {
    if (!_live || _size.width <= 0 || _size.height <= 0) return;
    setState(() {
      _pointer = Offset(
        (event.localPosition.dx / _size.width - 0.5) * 2,
        (event.localPosition.dy / _size.height - 0.5) * 2,
      );
    });
  }

  void _onExit(PointerExitEvent event) {
    if (!_live) return;
    setState(() => _pointer = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    if (!_live) {
      return _ParallaxScope(
        data: const _ParallaxData(pointer: Offset.zero, scroll: 0, maxShift: 0, scrollShift: 0),
        child: widget.child,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          opaque: false,
          onHover: _onHover,
          onExit: _onExit,
          child: _ParallaxScope(
            data: _ParallaxData(
              pointer: _pointer,
              scroll: _scroll,
              maxShift: widget.maxShift,
              scrollShift: widget.scrollShift,
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class ParallaxLayer extends StatelessWidget {
  const ParallaxLayer({
    required this.depth,
    required this.child,
    super.key,
  });

  /// 0 leaves the layer flat; 1 is the furthest plane.
  final double depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _ParallaxData? data =
        context.dependOnInheritedWidgetOfExactType<_ParallaxScope>()?.data;
    if (data == null || data.maxShift == 0) return child;

    // Scroll is capped so a long page does not push a hero layer off its own
    // canvas. The layer still reads as slower than the copy in front of it.
    final double scroll = (data.scroll.clamp(0.0, 900.0) / 900) * data.scrollShift;
    return Transform.translate(
      offset: Offset(
        data.pointer.dx * depth * data.maxShift,
        data.pointer.dy * depth * data.maxShift + scroll * depth,
      ),
      child: child,
    );
  }
}

class _ParallaxData {
  const _ParallaxData({
    required this.pointer,
    required this.scroll,
    required this.maxShift,
    required this.scrollShift,
  });

  final Offset pointer;
  final double scroll;
  final double maxShift;
  final double scrollShift;
}

class _ParallaxScope extends InheritedWidget {
  const _ParallaxScope({required this.data, required super.child});

  final _ParallaxData data;

  @override
  bool updateShouldNotify(_ParallaxScope oldWidget) =>
      oldWidget.data.pointer != data.pointer ||
      oldWidget.data.scroll != data.scroll;
}
