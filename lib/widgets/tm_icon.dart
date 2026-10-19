// ─────────────────────────────────────────────────────────────────────────────
// The icon set.
//
// Authored, not imported: every glyph is a set of straight or arced strokes on
// a 24-unit grid, drawn at 1.5 units, with square caps and mitred joins so they
// carry the same weight as the hairline rules the rest of the product is built
// from. Material's rounded 24 px set belongs to a different world, and an emoji
// is not an icon.
//
// Deliberately tiny. The original nine are still here; the chat added the
// controls a conversation needs — a phone, a camera, a microphone, a picture,
// a calendar, a play mark — drawn to the same grid and the same weight so they
// do not arrive as a second visual language.
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

  // The chat.
  phone,
  phoneDown,
  video,
  videoOff,
  cameraFlip,
  mic,
  micOff,
  image,
  calendar,
  emoji,
  play,
  pause,
  plus,
  speaker,
  speakerOff,
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
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

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

      case TMIconName.phone:
        canvas.drawPath(_phoneOutline(s), p);

      case TMIconName.phoneDown:
        // The same receiver, turned 135°: the one gesture everybody already
        // reads as "end this".
        canvas.save();
        canvas.translate(12 * s, 12 * s);
        canvas.rotate(2.356194490192345);
        canvas.translate(-12 * s, -12 * s);
        canvas.drawPath(_phoneOutline(s), p);
        canvas.restore();

      case TMIconName.video:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3.5 * s, 7 * s, 11.5 * s, 10 * s),
            Radius.circular(1.5 * s),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16 * s, 10.5 * s)
            ..lineTo(20.5 * s, 8 * s)
            ..lineTo(20.5 * s, 16 * s)
            ..lineTo(16 * s, 13.5 * s)
            ..close(),
          p,
        );

      case TMIconName.videoOff:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3.5 * s, 7 * s, 11.5 * s, 10 * s),
            Radius.circular(1.5 * s),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16 * s, 10.5 * s)
            ..lineTo(20.5 * s, 8 * s)
            ..lineTo(20.5 * s, 16 * s)
            ..lineTo(16 * s, 13.5 * s)
            ..close(),
          p,
        );
        canvas.drawLine(at(4, 4), at(20, 20), p);

      case TMIconName.cameraFlip:
        // Two arrows going opposite ways: swap which way the camera looks.
        canvas.drawLine(at(3.5, 9), at(16.5, 9), p);
        canvas.drawLine(at(13.5, 6), at(16.5, 9), p);
        canvas.drawLine(at(13.5, 12), at(16.5, 9), p);
        canvas.drawLine(at(20.5, 15), at(7.5, 15), p);
        canvas.drawLine(at(10.5, 12), at(7.5, 15), p);
        canvas.drawLine(at(10.5, 18), at(7.5, 15), p);

      case TMIconName.mic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at(12, 9.25), width: 5.5 * s, height: 10.5 * s),
            Radius.circular(2.75 * s),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.5 * s, 11 * s)
            ..cubicTo(6.5 * s, 15.2 * s, 9 * s, 17.5 * s, 12 * s, 17.5 * s)
            ..cubicTo(15 * s, 17.5 * s, 17.5 * s, 15.2 * s, 17.5 * s, 11 * s),
          p,
        );
        canvas.drawLine(at(12, 17.5), at(12, 21), p);
        canvas.drawLine(at(8.5, 21), at(15.5, 21), p);

      case TMIconName.micOff:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at(12, 9.25), width: 5.5 * s, height: 10.5 * s),
            Radius.circular(2.75 * s),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.5 * s, 11 * s)
            ..cubicTo(6.5 * s, 15.2 * s, 9 * s, 17.5 * s, 12 * s, 17.5 * s)
            ..cubicTo(15 * s, 17.5 * s, 17.5 * s, 15.2 * s, 17.5 * s, 11 * s),
          p,
        );
        canvas.drawLine(at(12, 17.5), at(12, 21), p);
        canvas.drawLine(at(8.5, 21), at(15.5, 21), p);
        canvas.drawLine(at(4, 4), at(20, 20), p);

      case TMIconName.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3.5 * s, 4.5 * s, 17 * s, 15 * s),
            Radius.circular(1.5 * s),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4.5 * s, 17.5 * s)
            ..lineTo(9 * s, 12 * s)
            ..lineTo(12.5 * s, 15.5 * s)
            ..lineTo(15 * s, 13 * s)
            ..lineTo(19.5 * s, 17.5 * s),
          p,
        );
        canvas.drawCircle(at(16, 8.5), 1.4 * s, fill);

      case TMIconName.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3.5 * s, 5.5 * s, 17 * s, 15 * s),
            Radius.circular(1.5 * s),
          ),
          p,
        );
        canvas.drawLine(at(3.5, 10.5), at(20.5, 10.5), p);
        canvas.drawLine(at(8, 3.5), at(8, 7.5), p);
        canvas.drawLine(at(16, 3.5), at(16, 7.5), p);

      case TMIconName.emoji:
        canvas.drawCircle(at(12, 12), 8.5 * s, p);
        canvas.drawCircle(at(9.25, 9.75), 0.9 * s, fill);
        canvas.drawCircle(at(14.75, 9.75), 0.9 * s, fill);
        canvas.drawPath(
          Path()
            ..moveTo(8.25 * s, 14 * s)
            ..quadraticBezierTo(12 * s, 17.5 * s, 15.75 * s, 14 * s),
          p,
        );

      case TMIconName.play:
        canvas.drawPath(
          Path()
            ..moveTo(8 * s, 5 * s)
            ..lineTo(19 * s, 12 * s)
            ..lineTo(8 * s, 19 * s)
            ..close(),
          fill,
        );

      case TMIconName.pause:
        canvas.drawRect(Rect.fromLTWH(8 * s, 5.5 * s, 3 * s, 13 * s), fill);
        canvas.drawRect(Rect.fromLTWH(13 * s, 5.5 * s, 3 * s, 13 * s), fill);

      case TMIconName.plus:
        canvas.drawLine(at(12, 4.5), at(12, 19.5), p);
        canvas.drawLine(at(4.5, 12), at(19.5, 12), p);

      case TMIconName.speaker:
        canvas.drawPath(
          Path()
            ..moveTo(4 * s, 9.5 * s)
            ..lineTo(8 * s, 9.5 * s)
            ..lineTo(12.5 * s, 5 * s)
            ..lineTo(12.5 * s, 19 * s)
            ..lineTo(8 * s, 14.5 * s)
            ..lineTo(4 * s, 14.5 * s)
            ..close(),
          p,
        );
        canvas.drawArc(
          Rect.fromCircle(center: at(13, 12), radius: 5 * s),
          -0.7853981633974483,
          1.5707963267948966,
          false,
          p,
        );
        canvas.drawArc(
          Rect.fromCircle(center: at(13, 12), radius: 8.5 * s),
          -0.7853981633974483,
          1.5707963267948966,
          false,
          p,
        );

      case TMIconName.speakerOff:
        canvas.drawPath(
          Path()
            ..moveTo(4 * s, 9.5 * s)
            ..lineTo(8 * s, 9.5 * s)
            ..lineTo(12.5 * s, 5 * s)
            ..lineTo(12.5 * s, 19 * s)
            ..lineTo(8 * s, 14.5 * s)
            ..lineTo(4 * s, 14.5 * s)
            ..close(),
          p,
        );
        canvas.drawArc(
          Rect.fromCircle(center: at(13, 12), radius: 5 * s),
          -0.7853981633974483,
          1.5707963267948966,
          false,
          p,
        );
        canvas.drawLine(at(4, 4), at(20, 20), p);
    }
  }

  @override
  bool shouldRepaint(_TMIconPainter old) =>
      old.name != name || old.color != color || old.width != width;
}

/// The receiver, drawn as one outline on the 24-unit grid. Shared by the
/// ringing phone and the one that puts it down.
Path _phoneOutline(double s) => Path()
  ..moveTo(6.62 * s, 10.79 * s)
  ..cubicTo(8.06 * s, 13.62 * s, 10.38 * s, 15.94 * s, 13.21 * s, 17.38 * s)
  ..lineTo(15.41 * s, 15.18 * s)
  ..cubicTo(15.68 * s, 14.91 * s, 16.08 * s, 14.82 * s, 16.43 * s, 14.94 * s)
  ..cubicTo(17.55 * s, 15.31 * s, 18.76 * s, 15.51 * s, 20 * s, 15.51 * s)
  ..cubicTo(20.55 * s, 15.51 * s, 21 * s, 15.96 * s, 21 * s, 16.51 * s)
  ..lineTo(21 * s, 20 * s)
  ..cubicTo(21 * s, 20.55 * s, 20.55 * s, 21 * s, 20 * s, 21 * s)
  ..cubicTo(10.61 * s, 21 * s, 3 * s, 13.39 * s, 3 * s, 4 * s)
  ..cubicTo(3 * s, 3.45 * s, 3.45 * s, 3 * s, 4 * s, 3 * s)
  ..lineTo(7.5 * s, 3 * s)
  ..cubicTo(8.05 * s, 3 * s, 8.5 * s, 3.45 * s, 8.5 * s, 4 * s)
  ..cubicTo(8.5 * s, 5.25 * s, 8.7 * s, 6.45 * s, 9.07 * s, 7.57 * s)
  ..cubicTo(9.18 * s, 7.92 * s, 9.1 * s, 8.31 * s, 8.82 * s, 8.59 * s)
  ..close();
