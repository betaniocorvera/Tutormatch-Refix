// ─────────────────────────────────────────────────────────────────────────────
// Buttons, links, and the one focus/hover vocabulary every control shares.
//
// [TMFocusable] exists so that a button, a tag chip, a filter row and a single
// cell of the week grid all respond to hover, focus, press and disable in
// exactly the same way. Divergent hover behaviour between two controls on the
// same screen is the thing that makes an interface feel assembled.
//
// Keyboard: Tab moves through, Enter and Space activate, and the focus ring is
// a 2 px ink ring drawn OUTSIDE the control so it never shifts layout and never
// competes with the accent red — the accent means "this is the action", the
// ring means "the keyboard is here".
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

/// Everything a control needs to know about how it is being touched.
class TMState {
  const TMState({
    required this.focused,
    required this.hovered,
    required this.pressed,
    required this.enabled,
  });

  final bool focused;
  final bool hovered;
  final bool pressed;
  final bool enabled;

  bool get engaged => enabled && (hovered || focused);
}

class TMFocusable extends StatefulWidget {
  const TMFocusable({
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.mouseCursor = SystemMouseCursors.click,
    this.semanticLabel,
    this.semanticButton = true,
    this.semanticSelected,
    super.key,
  });

  final Widget Function(BuildContext context, TMState state) builder;
  final VoidCallback? onTap;
  final bool enabled;
  final MouseCursor mouseCursor;
  final String? semanticLabel;
  final bool semanticButton;

  /// True/false for a selectable control, null when selection is not a concept.
  /// Screen readers announce "selected" only when it means something.
  final bool? semanticSelected;

  @override
  State<TMFocusable> createState() => _TMFocusableState();
}

class _TMFocusableState extends State<TMFocusable> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  bool get _live => widget.enabled && widget.onTap != null;

  void _activate() {
    if (!_live) return;
    widget.onTap!.call();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor: _live ? widget.mouseCursor : SystemMouseCursors.basic,
      onFocusChange: (bool v) => setState(() => _focused = v),
      onShowHoverHighlight: (bool v) => setState(() => _hovered = v),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent _) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: widget.semanticButton,
        enabled: widget.enabled,
        selected: widget.semanticSelected,
        inMutuallyExclusiveGroup: widget.semanticSelected == null ? null : true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _live ? _activate : null,
          onTapDown: _live ? (TapDownDetails _) => setState(() => _pressed = true) : null,
          onTapUp: _live ? (TapUpDetails _) => setState(() => _pressed = false) : null,
          onTapCancel: _live ? () => setState(() => _pressed = false) : null,
          child: widget.builder(
            context,
            TMState(
              focused: _focused,
              hovered: _hovered,
              pressed: _pressed && _live,
              enabled: widget.enabled,
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring. Drawn over the control's bounds, offset 3 px outwards, so turning
/// it on and off never moves a single pixel of the page.
///
/// On the ink band an ink ring would be invisible, so [TMInkContext] swaps it
/// for paper. That is the only reason the ring colour is contextual at all.
class TMFocusRing extends StatelessWidget {
  const TMFocusRing({
    required this.focused,
    required this.radius,
    required this.child,
    super.key,
  });

  final bool focused;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color ring =
        TMInkContext.of(context) ? AppColors.onAccent : AppColors.focusRing;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: focused ? 1 : 0,
              duration: Motion.fast,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: ring, width: 2),
                  borderRadius: BorderRadius.circular(radius + 3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Marks everything below it as sitting on the ink ground, so shared controls
/// invert themselves without every call site remembering to say so.
class TMInkContext extends InheritedWidget {
  const TMInkContext({required this.onInk, required super.child, super.key});

  final bool onInk;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TMInkContext>()?.onInk ?? false;

  @override
  bool updateShouldNotify(TMInkContext oldWidget) => oldWidget.onInk != onInk;
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

enum TMButtonVariant {
  /// One per screen. The action the screen exists for.
  primary,

  /// Everything else that does something.
  secondary,

  /// Navigation and third-order actions. Never a bordered box.
  quiet,

  /// For use on the ink panel, where the paper ground is inverted.
  onInk,
}

class TMButton extends StatelessWidget {
  const TMButton({
    required this.label,
    this.onPressed,
    this.variant = TMButtonVariant.primary,
    this.busy = false,
    this.busyLabel,
    this.icon,
    this.iconLeading = false,
    this.expand = false,
    this.minHeight = 48,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final TMButtonVariant variant;

  /// While busy the label is replaced with [busyLabel] — a real sentence about
  /// what is happening, never a spinner in the middle of a word.
  final bool busy;
  final String? busyLabel;
  final TMIconName? icon;
  final bool iconLeading;
  final bool expand;
  final double minHeight;
  final String? tooltip;

  bool get _enabled => onPressed != null && !busy;

  @override
  Widget build(BuildContext context) {
    final String text = busy ? (busyLabel ?? label) : label;

    return TMFocusable(
      enabled: _enabled,
      onTap: onPressed,
      semanticLabel: tooltip ?? label,
      builder: (BuildContext context, TMState state) {
        final _Paint paint = _paintFor(state);
        final Widget content = AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.ease,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.symmetric(
            horizontal: variant == TMButtonVariant.quiet ? Space.md : Space.xl,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: paint.fill,
            borderRadius: Radii.sharpAll,
            border: paint.border == null ? null : Border.all(color: paint.border!),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null && iconLeading) ...<Widget>[
                TMIcon(icon!, size: 18, color: paint.text),
                const SizedBox(width: Space.sm),
              ],
              Flexible(
                child: Text(
                  text,
                  style: AppType.button.tone(paint.text),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ),
              if (icon != null && !iconLeading) ...<Widget>[
                const SizedBox(width: Space.sm),
                TMIcon(icon!, size: 18, color: paint.text),
              ],
            ],
          ),
        );

        return TMFocusRing(
          focused: state.focused,
          radius: Radii.sharp,
          child: tooltip == null
              ? content
              : Tooltip(message: tooltip!, child: content),
        );
      },
    );
  }

  _Paint _paintFor(TMState s) {
    if (!_enabled && !busy) {
      return switch (variant) {
        TMButtonVariant.primary =>
          const _Paint(fill: AppColors.paperSunken, text: AppColors.inkMuted),
        TMButtonVariant.secondary =>
          const _Paint(fill: AppColors.paperSunken, text: AppColors.inkMuted),
        TMButtonVariant.quiet => const _Paint(fill: null, text: AppColors.inkMuted),
        TMButtonVariant.onInk =>
          const _Paint(fill: null, text: Color(0x66FFFCF6), border: Color(0x33FFFCF6)),
      };
    }
    return switch (variant) {
      TMButtonVariant.primary => _Paint(
          fill: s.pressed || s.hovered ? AppColors.accentPressed : AppColors.accent,
          text: AppColors.onAccent,
        ),
      TMButtonVariant.secondary => _Paint(
          fill: s.pressed ? AppColors.rule : (s.hovered ? AppColors.paperSunken : AppColors.paperRaised),
          text: AppColors.ink,
          border: AppColors.ruleStrong,
        ),
      TMButtonVariant.quiet => _Paint(
          fill: s.pressed ? AppColors.rule : (s.hovered ? AppColors.paperSunken : null),
          text: s.hovered ? AppColors.accent : AppColors.inkSecondary,
        ),
      TMButtonVariant.onInk => _Paint(
          fill: s.pressed
              ? const Color(0x33FFFCF6)
              : (s.hovered ? const Color(0x1FFFFCF6) : null),
          text: AppColors.onAccent,
          border: AppColors.onAccent,
        ),
    };
  }
}

class _Paint {
  const _Paint({required this.fill, required this.text, this.border});
  final Color? fill;
  final Color text;
  final Color? border;
}

/// An inline text action inside a sentence. Underlined on hover, always
/// keyboard reachable, never styled as a button.
class TMTextLink extends StatelessWidget {
  const TMTextLink({
    required this.label,
    required this.onTap,
    this.style,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final TextStyle? style;
  final TMIconName? icon;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = style ?? AppType.label;
    return TMFocusable(
      enabled: onTap != null,
      onTap: onTap,
      semanticButton: false,
      semanticLabel: label,
      builder: (BuildContext context, TMState s) {
        final Color ink = onTap == null
            ? AppColors.inkMuted
            : s.hovered || s.focused
                ? AppColors.accent
                : AppColors.ink;
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base.tone(ink).copyWith(
                          decoration: s.hovered || s.focused
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: ink,
                          decorationThickness: 1.2,
                        ),
                  ),
                ),
                if (icon != null) ...<Widget>[
                  const SizedBox(width: Space.sm),
                  TMIcon(icon!, size: 16, color: ink),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
