// ─────────────────────────────────────────────────────────────────────────────
// The week grid.
//
// This is the second half of the product's argument. A match score says two
// people agree; the grid says on what. It is a timetable, not an art asset: one
// column per day, one row per part of the day, and a cell is filled when both
// people are free in it. Count the filled cells and you have the number the
// score used.
//
// Three renditions, one geometry:
//   overlapOnly  — the match card. Filled means both. Nothing else competes.
//   comparison   — the profile. Both / you only / them only, with a legend.
//   editor       — onboarding and the filter rail. Keyboard reachable, each
//                  cell 44 px tall and roughly 39 px wide at 360 px, which is
//                  what fitting seven days on the narrowest phone costs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

enum AvailabilityDisplay { overlapOnly, comparison }

class AvailabilityGrid extends StatelessWidget {
  const AvailabilityGrid({
    required this.overlap,
    this.you,
    this.them,
    this.display = AvailabilityDisplay.overlapOnly,
    this.cellHeight = 15,
    this.dayLabels = true,
    this.partLabels = true,
    super.key,
  }) : assert(
          display == AvailabilityDisplay.overlapOnly || (you != null && them != null),
          'A comparison grid needs both weeks to compare.',
        );

  /// Cells where both people are free. Always supplied.
  final List<bool> overlap;

  /// The viewer's own week and the candidate's week. Only read in
  /// [AvailabilityDisplay.comparison].
  final List<bool>? you;
  final List<bool>? them;

  final AvailabilityDisplay display;
  final double cellHeight;
  final bool dayLabels;
  final bool partLabels;

  @override
  Widget build(BuildContext context) {
    final double labelWidth = partLabels ? 30 : 0;
    final int filled = overlap.where((bool c) => c).length;

    return Semantics(
      label: '$filled of 21 half-day blocks are free for both of you',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (dayLabels)
            Padding(
              padding: EdgeInsets.only(left: labelWidth, bottom: Space.xs),
              child: Row(
                children: <Widget>[
                  for (int d = 0; d < Week.days.length; d++)
                    Expanded(
                      child: Center(
                        child: Text(
                          Week.days[d].substring(0, 1),
                          style: AppType.micro.tone(AppColors.inkMuted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          for (int p = 0; p < Week.partKeys.length; p++)
            Padding(
              padding: EdgeInsets.only(top: p == 0 ? 0 : Space.xs),
              child: Row(
                children: <Widget>[
                  if (partLabels)
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        Week.partShort[p],
                        style: AppType.micro.copyWith(fontSize: 9.5).tone(AppColors.inkMuted),
                      ),
                    ),
                  for (int d = 0; d < Week.days.length; d++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: d == 0 ? 0 : Space.xs),
                        child: _Cell(
                          index: Week.index(d, p),
                          overlap: overlap,
                          you: you,
                          them: them,
                          display: display,
                          height: cellHeight,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.overlap,
    required this.you,
    required this.them,
    required this.display,
    required this.height,
  });

  final int index;
  final List<bool> overlap;
  final List<bool>? you;
  final List<bool>? them;
  final AvailabilityDisplay display;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool both = overlap[index];
    final bool mineOnly = !both && (you?[index] ?? false);
    final bool theirsOnly = !both && !mineOnly && (them?[index] ?? false);
    final bool nothing =
        !both && !mineOnly && !theirsOnly && display == AvailabilityDisplay.comparison;

    final Color fill;
    final Color border;
    if (both) {
      fill = AppColors.accent;
      border = AppColors.accent;
    } else if (mineOnly) {
      fill = AppColors.accentWash;
      border = AppColors.accent;
    } else if (theirsOnly) {
      fill = AppColors.paperSunken;
      border = AppColors.ruleStrong;
    } else if (nothing) {
      fill = Colors.transparent;
      border = AppColors.rule;
    } else {
      fill = AppColors.paperSunken;
      border = AppColors.rule;
    }

    return AnimatedContainer(
      duration: Motion.slow,
      curve: Motion.ease,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
      child: theirsOnly
          ? const Center(
              child: SizedBox(
                width: 3,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.inkMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// The three swatches, spelled out. A person should never have to guess what a
/// filled cell means.
class AvailabilityLegend extends StatelessWidget {
  const AvailabilityLegend({this.mode = AvailabilityDisplay.comparison, super.key});

  final AvailabilityDisplay mode;

  @override
  Widget build(BuildContext context) {
    final List<(Color, Color, String)> swatches = mode == AvailabilityDisplay.comparison
        ? <(Color, Color, String)>[
            (AppColors.accent, AppColors.accent, 'Both free'),
            (AppColors.accentWash, AppColors.accent, 'You only'),
            (AppColors.paperSunken, AppColors.ruleStrong, 'They are only'),
          ]
        : <(Color, Color, String)>[
            (AppColors.accent, AppColors.accent, 'Both free'),
            (AppColors.paperSunken, AppColors.rule, 'Not free'),
          ];

    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.sm,
      children: <Widget>[
        for (final (Color fill, Color border, String label) in swatches)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    border: Border.all(color: border),
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(label, style: AppType.bodySmall.quieter),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The editor
// ─────────────────────────────────────────────────────────────────────────────

/// Fill in your own week. One row per part of the day, seven cells per row,
/// reachable by Tab and announced as "Monday, evening, free".
///
/// Cells are 44 px tall always; the width is whatever a seventh of the row is,
/// which is about 39 px at 360 px — 44 px would push the week into a sideways
/// scroll on the phone this is most likely to be opened on. Both dimensions
/// clear the 24 px minimum of WCAG 2.5.8; the 44x44 AAA target is met on height
/// and missed on width by five pixels, which is the honest cost of showing a
/// whole week at once. On any wider screen the cells grow.
class AvailabilityEditor extends StatelessWidget {
  const AvailabilityEditor({
    required this.value,
    required this.onChanged,
    this.you,
    this.onRemove,
    this.showSummary = true,
    super.key,
  });

  final List<bool> value;
  final ValueChanged<List<bool>> onChanged;

  /// Optional counterpart week, drawn as a faint outline behind each cell so
  /// you can see what you are editing towards.
  final List<bool>? you;

  /// When supplied, a cell that is only free on the other side gets a "no
  /// overlap" mark, and tapping it still works.
  final VoidCallback? onRemove;
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    final int count = value.where((bool c) => c).length;
    final String? summary = describeOverlap(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.rule),
            borderRadius: Radii.sharpAll,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              children: <Widget>[
                for (int p = 0; p < Week.partKeys.length; p++) ...<Widget>[
                  if (p > 0) const SizedBox(height: Space.md),
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
                    child: Text(
                      Week.partLong[p].toUpperCase(),
                      style: AppType.micro.tone(AppColors.inkMuted),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (int d = 0; d < Week.days.length; d++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: d == 0 ? 0 : Space.xs),
                            child: _EditorCell(
                              day: d,
                              part: p,
                              on: value[Week.index(d, p)],
                              theirs: you?[Week.index(d, p)] ?? false,
                              onTap: () {
                                final List<bool> next = List<bool>.of(value);
                                next[Week.index(d, p)] = !next[Week.index(d, p)];
                                onChanged(next);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showSummary) ...<Widget>[
          const SizedBox(height: Space.md),
          Row(
            children: <Widget>[
              TMIcon(
                count == 0 ? TMIconName.dash : TMIconName.check,
                size: 15,
                color: count == 0 ? AppColors.inkMuted : AppColors.accepted,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  count == 0
                      ? 'Nothing selected yet. Pick the blocks you could genuinely keep free — '
                          'a narrow, honest week produces far better matches than a wide, hopeful one.'
                      : '$count blocks a week: $summary.',
                  style: AppType.bodySmall.tone(
                    count == 0 ? AppColors.inkMuted : AppColors.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EditorCell extends StatelessWidget {
  const _EditorCell({
    required this.day,
    required this.part,
    required this.on,
    required this.theirs,
    required this.onTap,
  });

  final int day;
  final int part;
  final bool on;
  final bool theirs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label = '${Week.dayLong[day]}, ${Week.partLong[part]}';
    return TMFocusable(
      onTap: onTap,
      semanticLabel: label,
      semanticSelected: on,
      builder: (BuildContext context, TMState s) {
        return TMFocusRing(
          focused: s.focused,
          radius: 2,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.ease,
            constraints: const BoxConstraints(minHeight: Hit.min),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.accent
                  : theirs
                      ? AppColors.accentWash
                      : s.hovered
                          ? AppColors.paperSunken
                          : Colors.transparent,
              border: Border.all(
                color: on
                    ? AppColors.accent
                    : theirs
                        ? AppColors.accent
                        : s.hovered
                            ? AppColors.ruleStrong
                            : AppColors.rule,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
            child: Center(
              child: Text(
                Week.days[day].substring(0, 1),
                style: AppType.labelSmall.tone(
                  on ? AppColors.onAccent : AppColors.inkMuted,
                ).copyWith(fontWeight: on ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ),
        );
      },
    );
  }
}
