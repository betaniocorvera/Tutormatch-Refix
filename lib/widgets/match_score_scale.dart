// ─────────────────────────────────────────────────────────────────────────────
// The match score, drawn as a measurement.
//
// A ring, a gauge or a soft-shadowed percentage all say "trust me". A ruler says
// "count it". The score is a 0-100 agreement across five weighted dimensions, so
// it is drawn as a 100-unit rule: major ticks every ten points, the agreed part
// filled in the accent, and a cursor standing on the exact value. The numeral
// sits beside it in tabular figures because the numeral is data, and data in
// this product is set in Public Sans.
//
// Everything here is one [CustomPainter] and one [Semantics] node: a screen
// reader hears "Match score 87 out of 100, strong match", not twenty-one ticks.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';

/// The ruler on its own. Use [MatchScoreBlock] when you also want the number.
class MatchScoreScale extends StatelessWidget {
  const MatchScoreScale({
    required this.score,
    this.height = 22,
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
    return Semantics(
      label: 'Match score $score out of 100',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _RulerPainter(
            score: score,
            tickColor: tickColor,
            trackColor: trackColor,
            showTicks: showTicks,
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.score,
    required this.tickColor,
    required this.trackColor,
    required this.showTicks,
  });

  final int score;
  final Color tickColor;
  final Color trackColor;
  final bool showTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double value = score.clamp(0, 100) / 100;
    final double trackTop = size.height * 0.42;
    const double trackHeight = 7;

    // The full range, at rest.
    canvas.drawRect(
      Rect.fromLTWH(0, trackTop, w, trackHeight),
      Paint()..color = trackColor,
    );

    // The agreed part.
    canvas.drawRect(
      Rect.fromLTWH(0, trackTop, w * value, trackHeight),
      Paint()..color = AppColors.accent,
    );

    // Major ticks every ten points, sitting above the rule like the graduations
    // on a printed scale. Drawn in the track colour so they read as the rule's
    // own detail and never as content.
    if (showTicks) {
      final Paint tick = Paint()..color = tickColor;
      for (int i = 0; i <= 10; i++) {
        final double x = (w - 1) * (i / 10);
        final bool major = i % 5 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, trackTop - (major ? 6 : 3.5), 1, major ? 6 : 3.5),
          tick,
        );
      }
    }

    // The cursor, standing on the exact value. Ink, not accent, so it stays
    // legible even when the value is zero.
    final double cx = (w - 2) * value;
    canvas.drawRect(
      Rect.fromLTWH(cx, 1, 2, size.height - 1),
      Paint()..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.score != score ||
      old.tickColor != tickColor ||
      old.trackColor != trackColor ||
      old.showTicks != showTicks;
}

/// The number, the word for it, and the ruler under both.
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
    return Semantics(
      container: true,
      label: 'Match score $score out of 100. ${tier.label}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '$score',
                      style: large ? AppType.score : AppType.scoreSmall,
                    ),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        '/ 100',
                        style: AppType.bodySmall.quieter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            tier.label.toUpperCase(),
            style: AppType.micro.tone(AppColors.inkSecondary),
          ),
          if (showMeaning) ...<Widget>[
            const SizedBox(height: Space.xs),
            SizedBox(
              width: 280,
              child: Text(tier.meaning, style: AppType.bodySmall.quieter),
            ),
          ],
          SizedBox(height: large ? Space.lg : Space.md),
          MatchScoreScale(score: score),
        ],
      ),
    );
  }
}

/// The five dimensions, each on one shared scale, so the weights are visible
/// rather than described. A subject score of 40 draws a full-length bar; a
/// format score of 10 draws a quarter-length one. The reader can see why the
/// totals differ without being told about weights at all.
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
              Text(
                '$value',
                style: AppType.figure.tone(full ? AppColors.accepted : AppColors.ink),
              ),
              Text(
                ' / ${dimension.max}',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          // The shared 0-40 scale: every bar starts at the same origin and its
          // track length is its own weight. Comparable across rows.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double track = c.maxWidth * (dimension.max / 40);
              final double fill = track * (value / dimension.max);
              return SizedBox(
                height: 6,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: track,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: AppColors.rule),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: Motion.slow,
                          curve: Motion.ease,
                          width: fill,
                          color: none
                              ? AppColors.ruleStrong
                              : value >= dimension.max
                                  ? AppColors.accepted
                                  : AppColors.accent,
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
