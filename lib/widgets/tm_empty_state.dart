// ─────────────────────────────────────────────────────────────────────────────
// The empty state.
//
// An empty list is the most informative screen in a recommender, and the one
// most products waste. "No results found" tells a person nothing and blames
// them for it. This one names the exact condition that removed everybody, says
// how many people it removed, and offers the smallest change that would bring
// them back — one button, one filter, reversible.
//
// A caller may hand it an illustration — the results screen gives it the same
// neighbour map the landing page uses — and a row of suggestions. Both are
// optional, so the quiet ruled version remains the default.
//
// The copy is generated in mock_data.dart from the filters that actually fired,
// so it cannot drift out of date when the filters change.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class TMEmptyState extends StatelessWidget {
  const TMEmptyState({
    required this.headline,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.filters = const <Widget>[],
    this.filtersLabel,
    this.illustration,
    this.suggestionsLabel,
    this.suggestions = const <Widget>[],
    super.key,
  });

  /// Names the condition, e.g. "No tutor in your results is free on your
  /// evenings." Written as a statement of fact, never as an apology.
  final String headline;
  final String body;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// The active filters, each removable. This is the "way to adjust it".
  final List<Widget> filters;
  final String? filtersLabel;

  /// A live drawing of the space the filters left empty, when the caller has one.
  final Widget? illustration;

  /// Shortcuts back into the pool: subjects that do have people behind them.
  final String? suggestionsLabel;
  final List<Widget> suggestions;

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);

    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (illustration == null)
          Row(
            children: <Widget>[
              for (final double w in <double>[56, 40, 24])
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: SizedBox(
                    width: w,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.ruleStrong,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (illustration == null) const SizedBox(height: Space.xl),
        SizedBox(
          width: 520,
          child: Text(headline, style: AppType.titleLarge),
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          width: 560,
          child: Text(body, style: AppType.bodyLarge.quiet),
        ),
        if (suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.xl),
          TMMicroLabelText(suggestionsLabel ?? 'Try one of these instead'),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: suggestions),
        ],
        if (filters.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.xl),
          const TMRule(),
          const SizedBox(height: Space.lg),
          TMMicroLabelText(filtersLabel ?? "What you're filtering on"),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: filters),
        ],
        if (primaryLabel != null) ...<Widget>[
          const SizedBox(height: Space.xxl),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TMButton(
                label: primaryLabel!,
                icon: TMIconName.arrowRight,
                onPressed: onPrimary,
                minHeight: Hit.min,
              ),
              if (secondaryLabel != null)
                TMButton(
                  label: secondaryLabel!,
                  variant: TMButtonVariant.quiet,
                  onPressed: onSecondary,
                  minHeight: Hit.min,
                ),
            ],
          ),
        ],
      ],
    );

    final Widget content;
    if (illustration == null) {
      content = copy;
    } else if (wide) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 6, child: copy),
          const SizedBox(width: Space.xxl),
          Expanded(flex: 5, child: illustration!),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          illustration!,
          const SizedBox(height: Space.xl),
          copy,
        ],
      );
    }

    return TMEntry(
      padding: EdgeInsets.all(wide ? Space.xxl : Space.xl),
      child: content,
    );
  }
}

/// An active filter, with the way out attached to it. One tap removes one
/// condition, which is the only honest size for this action.
class TMFilterTag extends StatelessWidget {
  const TMFilterTag({
    required this.label,
    this.onRemove,
    this.removeLabel,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final String label;
  final VoidCallback? onRemove;
  final String? removeLabel;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(tone);
    return TMFocusable(
      onTap: onRemove,
      enabled: onRemove != null,
      semanticLabel: removeLabel ?? 'Remove filter: $label',
      builder: (BuildContext context, TMState s) {
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.pill,
          child: AnimatedContainer(
            duration: Motion.respect(context, Motion.fast),
            curve: Motion.ease,
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.only(
              left: Space.md,
              right: Space.sm,
              top: Space.xs,
              bottom: Space.xs,
            ),
            decoration: BoxDecoration(
              color: s.hovered ? AppColors.paperSunken : wash,
              border: Border.all(color: ink),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: AppType.bodySmall.tone(ink)),
                if (onRemove != null) ...<Widget>[
                  const SizedBox(width: Space.sm),
                  TMIcon(TMIconName.close, size: 13, color: ink),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
