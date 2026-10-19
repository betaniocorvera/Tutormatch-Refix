// ─────────────────────────────────────────────────────────────────────────────
// The icon set.
//
// Authored, not imported: every glyph is a set of straight or arced strokes on
// a 24-unit grid, drawn at 1.5 units, with square caps and mitred joins so they
// carry the same weight as the hairline rules the rest of the product is built
// from. Material's rounded 24 px set belongs to a different world, and an emoji
// is not an icon.
//
// Deliberately tiny. There are nine glyphs because the product only needs nine;
// anything that can be said in a word is said in a word.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:tutormatch/theme/app_theme.dart';

enum TMIconName {
  arrowRight,
  arrowLeft,
  check,
  cross,
  dash,
  chevronDown,
  menu,
  close,
  sliders,
}

class TMIcon extends StatelessWidget {
  const TMIcon(
    this.name, {
    this.size = 18,
    this.color = AppColors.ink,
    this.strokeWidth = 1.5,
    super.key,
  });

  final TMIconName name;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TMIconPainter(name, color, strokeWidth * (size / 24)),
      ),
    );
  }
}

/// An icon that turns with a short, purposeful ease — used by the expanding
/// sections, where the rotation *is* the state.
class TMRotatingIcon extends StatelessWidget {
  const TMRotatingIcon(
    this.name, {
    required this.turns,
    this.size = 18,
    this.color = AppColors.ink,
    super.key,
  });

  final TMIconName name;
  final double turns;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: turns,
      duration: Motion.base,
      curve: Motion.ease,
      child: TMIcon(name, size: size, color: color),
    );
  }
}

class _TMIconPainter extends CustomPainter {
  _TMIconPainter(this.name, this.color, this.width);

  final TMIconName name;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 24;
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width.clamp(1.2, 2.4)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    Offset at(double x, double y) => Offset(x * s, y * s);

    switch (name) {
      case TMIconName.arrowRight:
        canvas.drawLine(at(3, 12), at(20, 12), p);
        canvas.drawLine(at(13.5, 5.5), at(20, 12), p);
        canvas.drawLine(at(13.5, 18.5), at(20, 12), p);

      case TMIconName.arrowLeft:
        canvas.drawLine(at(21, 12), at(4, 12), p);
        canvas.drawLine(at(10.5, 5.5), at(4, 12), p);
        canvas.drawLine(at(10.5, 18.5), at(4, 12), p);

      case TMIconName.check:
        canvas.drawLine(at(4, 12.5), at(9.75, 18.25), p);
        canvas.drawLine(at(9.75, 18.25), at(20, 5.75), p);

      case TMIconName.cross:
        canvas.drawLine(at(5.5, 5.5), at(18.5, 18.5), p);
        canvas.drawLine(at(18.5, 5.5), at(5.5, 18.5), p);

      case TMIconName.dash:
        canvas.drawLine(at(5, 12), at(19, 12), p);

      case TMIconName.chevronDown:
        canvas.drawLine(at(5.5, 9.25), at(12, 15.75), p);
        canvas.drawLine(at(12, 15.75), at(18.5, 9.25), p);

      case TMIconName.menu:
        for (final double y in <double>[7, 12, 17]) {
          canvas.drawLine(at(3.5, y), at(20.5, y), p);
        }

      case TMIconName.close:
        canvas.drawLine(at(5, 5), at(19, 19), p);
        canvas.drawLine(at(19, 5), at(5, 19), p);

      case TMIconName.sliders:
        // Two rules with a handle on each: the universal filter mark, drawn to
        // the same stroke weight as every other rule in the product.
        canvas.drawLine(at(3.5, 8), at(20.5, 8), p);
        canvas.drawLine(at(3.5, 16), at(20.5, 16), p);
        canvas.drawRect(Rect.fromCenter(center: at(9, 8), width: 4.5 * s, height: 7 * s), p);
        canvas.drawRect(Rect.fromCenter(center: at(15.5, 16), width: 4.5 * s, height: 7 * s), p);
    }
  }

  @override
  bool shouldRepaint(_TMIconPainter old) =>
      old.name != name || old.color != color || old.width != width;
}
