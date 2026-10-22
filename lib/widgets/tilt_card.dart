// ─────────────────────────────────────────────────────────────────────────────
// A surface that leans towards the pointer.
//
// This is the only 3D in the product that responds to a mouse, and it is kept
// deliberately slight: at most four degrees, on desktop-width screens only, on
// card-sized surfaces that are already the focus of the eye. It is a way of
// saying "this is a physical thing you can open", not a toy.
//
// It never wraps another TiltCard (the inner one opts out), and it never wraps
// body copy on its own. At rest the transform is identity, so nothing is
// rotated while it is being read.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class TiltCard extends StatefulWidget {
  const TiltCard({
    required this.child,
    this.maxTilt = 4,
    this.lift = 4,
    this.borderRadius = Radii.sharp,
    this.highlight = true,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Degrees. The brief caps the result card at 4°; the person header uses 3°.
  final double maxTilt;

  /// How far the surface lifts towards the viewer on hover, in pixels.
  final double lift;
  final double borderRadius;
  final bool highlight;
  final bool enabled;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  Offset _target = Offset.zero;
  bool _hovered = false;
  bool _nested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nested = TiltScope.of(context);
  }

  bool get _live =>
      widget.enabled &&
      !_nested &&
      TMLayout.isWide(context) &&
      !Motion.reduced(context);

  void _onHover(PointerHoverEvent event) {
    if (!_live) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Size size = box.size;
    if (size.width <= 0 || size.height <= 0) return;
    final double dx = (event.localPosition.dx / size.width - 0.5) * 2;
    final double dy = (event.localPosition.dy / size.height - 0.5) * 2;
    setState(() {
      _hovered = true;
      _target = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
    });
  }

  void _onExit(PointerExitEvent event) {
    if (!_live) return;
    setState(() {
      _hovered = false;
      _target = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_live) {
      return TiltScope(child: widget.child);
    }

    return TiltScope(
      child: MouseRegion(
        onHover: _onHover,
        onExit: _onExit,
        child: TweenAnimationBuilder<Offset>(
          tween: Tween<Offset>(begin: Offset.zero, end: _target),
          duration: Motion.fast,
          curve: Motion.ease,
          builder: (BuildContext context, Offset tilt, Widget? child) {
            final double rx = -tilt.dy * widget.maxTilt * math.pi / 180;
            final double ry = tilt.dx * widget.maxTilt * math.pi / 180;
            final Matrix4 transform = Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..translateByDouble(0, _hovered ? -widget.lift : 0, 0, 1)
              ..rotateX(rx)
              ..rotateY(ry);

            return AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: _hovered ? TMShadows.floating : null,
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: transform,
                child: Stack(
                  children: <Widget>[
                    child!,
                    if (widget.highlight)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            curve: Motion.ease,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(widget.borderRadius),
                              border: Border.all(
                                color: _hovered
                                    ? AppColors.accent.withValues(alpha: 0.28)
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

/// Marks descendants as already inside a tilt, so a card inside a card never
/// compounds two perspectives.
class TiltScope extends InheritedWidget {
  const TiltScope({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TiltScope>() != null;

  @override
  bool updateShouldNotify(TiltScope oldWidget) => false;
}
