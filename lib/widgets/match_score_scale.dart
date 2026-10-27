// ─────────────────────────────────────────────────────────────────────────────
// The match score, drawn as an instrument reading.
//
// A number is the claim; the ring is the measurement. The ring fills from zero
// to the value while the figure counts up with it, once, when the card arrives.
// From then on it is still: no looping, no glow, no gauge that celebrates.
//
// The five dimensions keep the ruler they had — a short, comparable scale for
// each contribution — because a ring can say how much and a row can say where.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';

/// The compact linear reading. Kept for any caller that needs a score in one
/// line; [MatchScorePanel] uses the ring instead.
class MatchScoreScale extends StatelessWidget {
  const MatchScoreScale({
    required this.score,
    this.height = 8,
    this.tickColor = AppColors.ruleStrong,
    this.trackColor = AppColors.rule,
    this.showTicks = true,
    super.key,
  });

  final int score;
  final double height;
  final Color tickColor;
  final Color trackColor;
  final bool showTicks;

  @override
  Widget build(BuildContext context) {
    final double value = score.clamp(0, 100) / 100;
    return Semantics(
      label: 'Match score $score out of 100',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: Motion.respect(context, const Duration(milliseconds: 620)),
        curve: Motion.emphasized,
        builder: (BuildContext context, double t, Widget? child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: height,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) => Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        height: height,
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius: BorderRadius.circular(height / 2),
                        ),
                      ),
                      Container(
                        height: height,
                        width: c.maxWidth * t,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(height / 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showTicks) ...<Widget>[
                const SizedBox(height: Space.xs),
                Row(
                  children: <Widget>[
                    for (int i = 0; i <= 10; i++)
                      Expanded(
                        child: Align(
                          alignment: i == 0
                              ? Alignment.centerLeft
                              : i == 10
                                  ? Alignment.centerRight
                                  : Alignment.center,
                          child: Container(
                            width: 1,
                            height: i % 5 == 0 ? 5 : 3,
                            color: tickColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The number, the word for it, and the ring that measures it.
class MatchScorePanel extends StatelessWidget {
  const MatchScorePanel({
    required this.score,
    this.large = false,
    this.showMeaning = true,
    this.trailing,
    super.key,
  });

  final int score;
  final bool large;
  final bool showMeaning;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final MatchTier tier = tierFor(score);
    final double ring = large ? 98 : 62;

    return Semantics(
      container: true,
      label: 'Match score $score out of 100. ${tier.label}.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RepaintBoundary(
            child: SizedBox.square(
              dimension: ring,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: score.toDouble()),
                duration:
                    Motion.respect(context, const Duration(milliseconds: 720)),
                curve: Motion.emphasized,
                builder: (BuildContext context, double value, Widget? child) {
                  return CustomPaint(
                    painter: _ScoreRingPainter(
                      value: value.clamp(0, 100),
                      large: large,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            value.round().toString(),
                            style: (large ? AppType.score : AppType.scoreSmall)
                                .copyWith(fontSize: large ? 31 : 20),
                          ),
                          if (large)
                            Text(
                              '/ 100',
                              style: AppType.micro.copyWith(fontSize: 8.5)
                                  .tone(AppColors.inkMuted),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: large ? Space.xs : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          tier.label,
                          style: AppType.label.copyWith(
                            fontWeight: FontWeight.w600,
                          ).tone(
                                score >= 60
                                    ? AppColors.accent
                                    : AppColors.inkSecondary,
                              ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    tier.meaning,
                    style: AppType.bodySmall.quieter,
                    maxLines: showMeaning ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!large) ...<Widget>[
                    const SizedBox(height: Space.sm),
                    SizedBox(
                      width: 140,
                      child: MatchScoreScale(
                        score: score,
                        height: 3,
                        showTicks: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({required this.value, required this.large});

  final double value;
  final bool large;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double stroke = large ? 4 : 3;
    final double radius = size.width / 2 - stroke;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.rule,
    );

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent;

    final double sweep = (value.clamp(0, 100) / 100) * math.pi * 2;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);

    // Graduations at each fifth. A measuring ring, not a progress donut.
    final Paint tick = Paint()
      ..strokeWidth = 1
      ..color = AppColors.ruleStrong;
    for (int i = 0; i < 5; i++) {
      final double a = -math.pi / 2 + (i / 5) * math.pi * 2;
      final Offset from = Offset(
        center.dx + math.cos(a) * (radius + stroke + 3),
        center.dy + math.sin(a) * (radius + stroke + 3),
      );
      final Offset to = Offset(
        center.dx + math.cos(a) * (radius + stroke + (large ? 6 : 5)),
        center.dy + math.sin(a) * (radius + stroke + (large ? 6 : 5)),
      );
      canvas.drawLine(from, to, tick);
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.value != value || old.large != large;
}

/// The five dimensions, each on one shared scale, so the weights are visible
/// rather than described. The reader can see why the totals differ without
/// being told about weights at all.
class ScoreBreakdown extends StatelessWidget {
  const ScoreBreakdown({
    required this.score,
    this.showExplainers = true,
    super.key,
  });

  final MatchScore score;
  final bool showExplainers;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < MatchDimension.values.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Space.lg),
            child: _DimensionRow(
              dimension: MatchDimension.values[i],
              value: score.byDimension[MatchDimension.values[i]] ?? 0,
              showExplainer: showExplainers,
            ),
          ),
      ],
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({
    required this.dimension,
    required this.value,
    required this.showExplainer,
  });

  final MatchDimension dimension;
  final int value;
  final bool showExplainer;

  @override
  Widget build(BuildContext context) {
    final bool full = value >= dimension.max;
    final bool none = value == 0;
    final Color ink = none
        ? AppColors.inkMuted
        : full
            ? AppColors.accepted
            : AppColors.accent;

    return Semantics(
      label: '${dimension.label}: $value out of ${dimension.max}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  dimension.label,
                  style: AppType.label.tone(
                    none ? AppColors.inkMuted : AppColors.ink,
                  ),
                ),
              ),
              Text('$value', style: AppType.figure.tone(ink)),
              Text(' / ${dimension.max}', style: AppType.bodySmall.quieter),
            ],
          ),
          const SizedBox(height: Space.sm),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double track = c.maxWidth * (dimension.max / 40);
              final double fill = track * (value / dimension.max);
              return SizedBox(
                height: 5,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: track,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.rule,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: Motion.respect(context, Motion.slow),
                          curve: Motion.ease,
                          width: fill,
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (showExplainer) ...<Widget>[
            const SizedBox(height: Space.sm),
            SizedBox(
              width: 460,
              child: Text(dimension.explainer, style: AppType.bodySmall.quieter),
            ),
          ],
        ],
      ),
    );
  }
}
