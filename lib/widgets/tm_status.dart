// ─────────────────────────────────────────────────────────────────────────────
// Status, notes and the one loading indicator.
//
// Status is never the accent. Accepted, pending and rejected each have their own
// wash and their own ink, and a symbol that is a drawn tick, a dash or a cross —
// so the state of a request is legible from the shape alone, without relying on
// colour.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

class TMStatusPill extends StatelessWidget {
  const TMStatusPill({
    required this.tone,
    required this.label,
    this.icon,
    this.dense = false,
    super.key,
  });

  final StatusTone tone;
  final String label;
  final TMIconName? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(tone);
    final TMIconName? mark = icon ??
        switch (tone) {
          StatusTone.accepted => TMIconName.check,
          StatusTone.pending => TMIconName.dash,
          StatusTone.declined => TMIconName.cross,
          StatusTone.neutral => null,
        };

    return Semantics(
      label: '$label status',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? Space.sm : Space.md,
          vertical: dense ? 3 : Space.xs + 1,
        ),
        decoration: BoxDecoration(
          color: wash,
          border: Border.all(color: ink, width: 1),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (mark != null) ...<Widget>[
              TMIcon(mark, size: dense ? 11 : 13, color: ink, strokeWidth: 2),
              const SizedBox(width: Space.xs + 1),
            ],
            Text(
              label,
              style: AppType.micro.copyWith(fontSize: dense ? 10 : 11).tone(ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loading rule. Two pixels of accent crossing a hairline track exactly
/// once: the work is finite, and a rule that loops would claim it is not. When
/// the platform asks for stillness, the rule is a fixed 32% mark instead.
class TMProgressRule extends StatefulWidget {
  const TMProgressRule({this.width = 220, super.key});

  final double width;

  @override
  State<TMProgressRule> createState() => _TMProgressRuleState();
}

class _TMProgressRuleState extends State<TMProgressRule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _still = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = Motion.reduced(context);
    if (!_still) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ranking in progress',
      child: SizedBox(
        width: widget.width,
        height: 2,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.rule),
          child: _still
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.32,
                    heightFactor: 1,
                    child: ColoredBox(color: AppColors.accent),
                  ),
                )
              : AnimatedBuilder(
                  animation: _c,
                  builder: (BuildContext context, Widget? child) {
                    final double t = Motion.emphasized.transform(_c.value);
                    return Align(
                      alignment: Alignment(-1 + 2 * t, 0),
                      child: FractionallySizedBox(
                        widthFactor: 0.32,
                        heightFactor: 1,
                        child: const ColoredBox(color: AppColors.accent),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// A note attached to something. Never a left border — the tone carries through
/// the fill and a single hairline, and the rule stays the same weight as every
/// other rule in the product.
class TMInlineNote extends StatelessWidget {
  const TMInlineNote({
    required this.tone,
    required this.title,
    this.body,
    this.actions = const <Widget>[],
    super.key,
  });

  final StatusTone tone;
  final String title;
  final String? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(tone);
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: wash,
        border: Border.all(color: ink),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1, right: Space.sm),
                child: TMIcon(
                  switch (tone) {
                    StatusTone.accepted => TMIconName.check,
                    StatusTone.pending => TMIconName.dash,
                    StatusTone.declined => TMIconName.cross,
                    StatusTone.neutral => TMIconName.dash,
                  },
                  size: 16,
                  color: ink,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppType.label.tone(ink)),
                    if (body != null) ...<Widget>[
                      const SizedBox(height: Space.xs),
                      SizedBox(
                        width: 560,
                        child: Text(
                          body!,
                          style: AppType.bodySmall.tone(
                            // Tinted from the note's own hue, never grey.
                            Color.lerp(ink, AppColors.ink, 0.35)!,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.md, runSpacing: Space.sm, children: actions),
          ],
        ],
      ),
    );
  }
}
