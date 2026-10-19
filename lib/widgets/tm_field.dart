// ─────────────────────────────────────────────────────────────────────────────
// Form controls.
//
// These are built to read like a printed registration form: a label set in
// small uppercase letterspaced sans, a field with a hairline rule, and choices
// presented as a list of ruled rows you tick — not as a cluster of floating
// pills. Everything is at least 44 px tall, keyboard reachable, and announces
// its selected state to a screen reader.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

/// The small uppercase caption that sits above a field or a column of data.
/// It labels; it never introduces a heading (no eyebrow kickers in this app).
class TMMicroLabel extends StatelessWidget {
  const TMMicroLabel(this.text, {this.color = AppColors.inkMuted, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppType.micro.tone(color));
}

/// A field label, with an optional "why we ask" line that a person can ignore
/// until they wonder.
class TMFieldLabel extends StatelessWidget {
  const TMFieldLabel({required this.label, this.reason, this.optional = false, super.key});

  final String label;

  /// Plain-language justification. Shown, not hidden behind a "?".
  final String? reason;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(child: Text(label, style: AppType.label)),
            if (optional) ...<Widget>[
              const SizedBox(width: Space.sm),
              Text('optional', style: AppType.micro.tone(AppColors.inkMuted)),
            ],
          ],
        ),
        if (reason != null) ...<Widget>[
          const SizedBox(height: Space.xs),
          SizedBox(
            width: 420,
            child: Text(reason!, style: AppType.bodySmall.tone(AppColors.inkMuted)),
          ),
        ],
      ],
    );
  }
}

class TMTextField extends StatefulWidget {
  const TMTextField({
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.helper,
    this.reason,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLines = 1,
    this.semanticHint,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? error;
  final String? helper;
  final String? reason;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int maxLines;
  final String? semanticHint;

  @override
  State<TMTextField> createState() => _TMTextFieldState();
}

class _TMTextFieldState extends State<TMTextField> {
  late final FocusNode _node = FocusNode(debugLabel: widget.label);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() => _focused = _node.hasFocus));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool bad = widget.error != null;
    final Color line = bad
        ? AppColors.alert
        : _focused
            ? AppColors.ink
            : AppColors.ruleStrong;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMFieldLabel(label: widget.label, reason: widget.reason),
        const SizedBox(height: Space.sm),
        TextField(
          focusNode: _node,
          controller: widget.controller,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          autofocus: widget.autofocus,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          style: AppType.body,
          cursorWidth: 1.5,
          cursorRadius: const Radius.circular(1),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.paperRaised,
            hintText: widget.hint,
            hintStyle: AppType.body.tone(AppColors.inkMuted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.lg,
            ),
            constraints: const BoxConstraints(minHeight: Hit.min),
            border: OutlineInputBorder(
              borderRadius: Radii.sharpAll,
              borderSide: BorderSide(color: line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: Radii.sharpAll,
              borderSide: BorderSide(color: line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: Radii.sharpAll,
              borderSide: BorderSide(color: bad ? AppColors.alert : AppColors.ink, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: Radii.sharpAll,
              borderSide: const BorderSide(color: AppColors.alert),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: Radii.sharpAll,
              borderSide: const BorderSide(color: AppColors.alert, width: 2),
            ),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        if (widget.error != null || widget.helper != null) ...<Widget>[
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (bad) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 3, right: Space.sm),
                  child: TMIcon(TMIconName.dash, size: 14, color: AppColors.alert),
                ),
              ],
              Flexible(
                child: Text(
                  widget.error ?? widget.helper!,
                  style: AppType.bodySmall.tone(
                    bad ? AppColors.alert : AppColors.inkMuted,
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

// ─────────────────────────────────────────────────────────────────────────────
// Choices
// ─────────────────────────────────────────────────────────────────────────────

/// A single-select list, drawn as ruled rows on a printed ballot. Used wherever
/// the options are sentences rather than words — which is most of this product.
class TMChoiceList<T> extends StatelessWidget {
  const TMChoiceList({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.labelOf,
    super.key,
  });

  final List<T> options;
  final T? selected;
  final ValueChanged<T> onSelect;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: Radii.sharpAll,
        border: Border.all(color: AppColors.rule),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < options.length; i++)
            _ChoiceRow<T>(
              value: options[i],
              label: labelOf(options[i]),
              selected: selected == options[i],
              onSelect: onSelect,
              divider: i > 0,
            ),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.divider,
  });

  final T value;
  final String label;
  final bool selected;
  final ValueChanged<T> onSelect;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: () => onSelect(value),
      semanticLabel: label,
      semanticButton: false,
      semanticSelected: selected,
      builder: (BuildContext context, TMState s) {
        return Column(
          children: <Widget>[
            if (divider) const Divider(height: 1, thickness: 1, color: AppColors.rule),
            TMFocusRing(
              focused: s.focused,
              radius: 0,
              child: AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.ease,
                constraints: const BoxConstraints(minHeight: Hit.min),
                color: selected
                    ? AppColors.accentWash
                    : s.hovered
                        ? AppColors.paperSunken
                        : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _TickMark(selected: selected),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          label,
                          style: AppType.body.tone(
                            selected ? AppColors.ink : AppColors.inkSecondary,
                          ).copyWith(
                                fontWeight:
                                    selected ? FontWeight.w600 : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A square tick, not a round radio. The product's geometry is ruled and
/// orthogonal, and a printed form is ticked with a square.
class _TickMark extends StatelessWidget {
  const _TickMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hidden: true,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.ease,
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.ruleStrong,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(Radii.sharp - 1),
        ),
        child: selected
            ? const Padding(
                padding: EdgeInsets.all(2),
                child: TMIcon(TMIconName.check, size: 12, color: AppColors.onAccent),
              )
            : null,
      ),
    );
  }
}

/// Multi-select tags. Selected tags fill with the accent wash and take the
/// accent rule; they never become solid accent blocks, because an accent block
/// means "this is the action" everywhere else in the app.
class TMTagPicker extends StatelessWidget {
  const TMTagPicker({
    required this.options,
    required this.selected,
    required this.onToggle,
    this.max,
    this.maxReachedNote,
    super.key,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  /// When set, further options disable themselves and [maxReachedNote] explains
  /// why, rather than silently refusing the tap.
  final int? max;
  final String? maxReachedNote;

  @override
  Widget build(BuildContext context) {
    final bool full = max != null && selected.length >= max!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: <Widget>[
            for (final String option in options)
              _Tag(
                label: option,
                selected: selected.contains(option),
                disabled: full && !selected.contains(option),
                onTap: () => onToggle(option),
              ),
          ],
        ),
        // When a limit is reached, the reason is stated where the refusal
        // happens, rather than leaving the remaining tags dead with no word why.
        if (full && maxReachedNote != null) ...<Widget>[
          const SizedBox(height: Space.sm),
          Text(maxReachedNote!, style: AppType.bodySmall.quieter),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      enabled: !disabled,
      semanticLabel: label,
      semanticButton: false,
      semanticSelected: selected,
      builder: (BuildContext context, TMState s) {
        final Color line = disabled
            ? AppColors.rule
            : selected
                ? AppColors.accent
                : s.hovered
                    ? AppColors.ruleStrong
                    : AppColors.rule;
        final Color ground = disabled
            ? AppColors.paperSunken
            : selected
                ? AppColors.accentWash
                : s.hovered
                    ? AppColors.paperSunken
                    : AppColors.paperRaised;
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.ease,
            constraints: const BoxConstraints(minHeight: Hit.min),
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            decoration: BoxDecoration(
              color: ground,
              borderRadius: Radii.sharpAll,
              border: Border.all(color: line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (selected) ...<Widget>[
                  const TMIcon(TMIconName.check, size: 14, color: AppColors.accent),
                  const SizedBox(width: Space.sm),
                ],
                Text(
                  label,
                  style: AppType.labelSmall.tone(
                    disabled
                        ? AppColors.inkMuted
                        : selected
                            ? AppColors.accent
                            : AppColors.inkSecondary,
                  ).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Two to four mutually exclusive options in one ruled strip.
class TMSegmented<T> extends StatelessWidget {
  const TMSegmented({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.labelOf,
    this.expand = true,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final String Function(T) labelOf;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      for (final T option in options)
        Expanded(
          flex: expand ? 1 : 0,
          child: _Segment(
            label: labelOf(option),
            selected: option == selected,
            onTap: () => onSelect(option),
          ),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.sharpAll,
        border: Border.all(color: AppColors.ruleStrong),
        color: AppColors.paperRaised,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sharp - 1),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0)
                const SizedBox(
                  height: Hit.min,
                  child: VerticalDivider(width: 1, thickness: 1, color: AppColors.ruleStrong),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticLabel: label,
      semanticButton: false,
      semanticSelected: selected,
      builder: (BuildContext context, TMState s) {
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.ease,
          constraints: const BoxConstraints(minHeight: Hit.min),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
          color: selected
              ? AppColors.accent
              : s.hovered
                  ? AppColors.paperSunken
                  : Colors.transparent,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppType.labelSmall.tone(
              selected ? AppColors.onAccent : AppColors.inkSecondary,
            ).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
          ),
        );
      },
    );
  }
}

/// A single-select row of tags. The counterpart to [TMTagPicker] for the cases
/// where only one answer is allowed — format, day part, sort order.
class TMTagRow<T> extends StatelessWidget {
  const TMTagRow({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.labelOf,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: <Widget>[
        for (final T option in options)
          _Tag(
            label: labelOf(option),
            selected: selected == option,
            disabled: false,
            onTap: () => onSelect(option),
          ),
      ],
    );
  }
}

/// A rate or budget chosen from a fixed ladder of prices, drawn as a measured
/// scale rather than a slider. Cheaper to use with a keyboard, and it reads
/// like a price list instead of a volume knob.
class TMBudgetScale extends StatelessWidget {
  const TMBudgetScale({
    required this.value,
    required this.onChanged,
    this.steps = const <int>[25, 30, 35, 40, 45, 50, 60, 80],
    this.ceiling = 80,
    this.unitSuffix = '/hr',
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final List<int> steps;

  /// The value that means "no limit".
  final int ceiling;
  final String unitSuffix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: <Widget>[
        for (final int step in steps)
          _Tag(
            label: step == ceiling ? 'Any price' : '\$$step$unitSuffix',
            selected: value == step,
            disabled: false,
            onTap: () => onChanged(step),
          ),
      ],
    );
  }
}
