// ─────────────────────────────────────────────────────────────────────────────
// The frame: page shell, masthead, nav, footer, section headings, and the
// ruled container the whole product is built out of.
//
// There are no cards in this app in the Material sense. There are entries:
// a surface one step lighter than the page, bounded by a 1 px rule, with a
// 3 px corner. Depth is expressed by the rule and by space, never by a shadow —
// the single exception is the request panel, which genuinely floats above the
// page on wide screens and says so with a soft offset shadow.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

/// Breakpoints computed from the window, since the shell is full-bleed and only
/// the content inside it is capped. One place, so a screen never guesses.
abstract final class TMLayout {
  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) =>
      widthOf(context) < AppBreakpoints.compact;
  static bool isNarrow(BuildContext context) => widthOf(context) < AppBreakpoints.medium;
  static bool isWide(BuildContext context) => widthOf(context) >= AppBreakpoints.medium;
  static bool isRoomy(BuildContext context) => widthOf(context) >= AppBreakpoints.wide;

  /// Page gutter. Grows with the viewport so a phone never feels cramped and a
  /// laptop never feels boxed in.
  static double gutter(BuildContext context) {
    final double w = widthOf(context);
    if (w < AppBreakpoints.compact) return 20;
    if (w < AppBreakpoints.medium) return 32;
    if (w < AppBreakpoints.wide) return 40;
    return 48;
  }

  /// Column widths for the recurring asymmetric splits.
  static const double railWidth = 268;
  static const double asideWidth = 340;
}

/// A ruled page. Every screen is one of these, which is what keeps the rhythm
/// identical from the landing page to the last tab of the requests screen.
class TMPage extends StatelessWidget {
  const TMPage({
    required this.child,
    this.navItems = const <TMNavItem>[],
    this.navTrailing,
    this.masthead = false,
    this.footer = true,
    this.maxWidth = AppBreakpoints.maxContent,
    super.key,
  });

  final Widget child;
  final List<TMNavItem> navItems;
  final Widget? navTrailing;

  /// The 3 px rule across the very top, used only on the landing page. It is
  /// the one place the product raises its voice.
  final bool masthead;
  final bool footer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final double gutter = TMLayout.gutter(context);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Scrollbar(
          child: SingleChildScrollView(
            primary: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (masthead)
                  const SizedBox(
                    height: 3,
                    child: ColoredBox(color: AppColors.ink),
                  ),
                TMTopBar(navItems: navItems, trailing: navTrailing),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      child: child,
                    ),
                  ),
                ),
                if (footer) ...<Widget>[
                  SizedBox(height: Space.band(TMLayout.widthOf(context))),
                  const TMFooter(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TMNavItem {
  const TMNavItem({required this.label, this.onTap, this.selected = false});
  final String label;
  final VoidCallback? onTap;
  final bool selected;
}

class TMTopBar extends StatefulWidget {
  const TMTopBar({this.navItems = const <TMNavItem>[], this.trailing, super.key});

  final List<TMNavItem> navItems;
  final Widget? trailing;

  @override
  State<TMTopBar> createState() => _TMTopBarState();
}

class _TMTopBarState extends State<TMTopBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bool narrow = TMLayout.isNarrow(context);
    final double gutter = TMLayout.gutter(context);
    final bool hasNav = widget.navItems.isNotEmpty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: narrow ? 60 : 72,
                  child: Row(
                    // Wordmark hard left, navigation and account hard right.
                    // A Spacer only does that when the right-hand side exactly
                    // fills its share of the free space; the moment the nav and
                    // the account are narrower than that share — which is most
                    // of the time on a desktop — the slack lands after them and
                    // the account drifts in from the edge. spaceBetween keeps
                    // the slack in the middle, where it reads as margin.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _Wordmark(onTap: () => _home(context)),
                      if (!narrow && (hasNav || widget.trailing != null))
                        Flexible(
                          fit: FlexFit.loose,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (hasNav)
                                for (final TMNavItem item in widget.navItems)
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: _NavLink(item: item),
                                  ),
                              if (hasNav && widget.trailing != null)
                                const SizedBox(width: Space.lg),
                              // Loose, so a long name compresses what is beside
                              // it rather than striping the bar.
                              if (widget.trailing != null)
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: widget.trailing!,
                                ),
                            ],
                          ),
                        ),
                      if (narrow && hasNav)
                        TMFocusable(
                          onTap: () => setState(() => _open = !_open),
                          semanticLabel: _open ? 'Close menu' : 'Open menu',
                          builder: (BuildContext context, TMState s) => TMFocusRing(
                            focused: s.focused,
                            radius: Radii.sharp,
                            child: SizedBox(
                              width: Hit.min,
                              height: Hit.min,
                              child: AnimatedContainer(
                                duration: Motion.fast,
                                decoration: BoxDecoration(
                                  color: s.hovered || _open
                                      ? AppColors.paperSunken
                                      : Colors.transparent,
                                  borderRadius: Radii.sharpAll,
                                ),
                                child: Center(
                                  child: TMIcon(
                                    _open ? TMIconName.close : TMIconName.menu,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // The mobile menu expands in place rather than covering the page.
                // Nothing is hidden and the keyboard order stays honest.
                AnimatedSize(
                  duration: Motion.base,
                  curve: Motion.ease,
                  alignment: Alignment.topCenter,
                  child: _open && narrow && hasNav
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (final TMNavItem item in widget.navItems)
                                _NavLink(item: item, block: true),
                              if (widget.trailing != null) ...<Widget>[
                                const SizedBox(height: Space.md),
                                widget.trailing!,
                              ],
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _home(BuildContext context) {
    Navigator.of(context).popUntil((Route<void> r) => r.isFirst);
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticLabel: 'TutorMatch, go to the start',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('TutorMatch', style: AppType.wordmark),
              Text(
                '.ai',
                style: AppType.wordmark.tone(
                  s.hovered || s.focused ? AppColors.accent : AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.item, this.block = false});
  final TMNavItem item;
  final bool block;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: item.onTap,
      enabled: item.onTap != null,
      semanticButton: false,
      semanticSelected: item.selected,
      semanticLabel: item.label,
      builder: (BuildContext context, TMState s) {
        final Color ink = item.selected
            ? AppColors.accent
            : s.hovered || s.focused
                ? AppColors.ink
                : AppColors.inkSecondary;
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: Container(
            width: block ? double.infinity : null,
            constraints: const BoxConstraints(minHeight: Hit.min),
            alignment: block ? Alignment.centerLeft : Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: block ? Space.sm : Space.md,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
                  block ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.label,
                  style: AppType.labelSmall.tone(ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                // The current page is marked with a rule, the way a printed
                // contents page marks where you are.
                AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.ease,
                  height: 2,
                  width: item.selected ? (block ? 40 : 18) : 0,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TMFooter extends StatelessWidget {
  const TMFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final double gutter = TMLayout.gutter(context);
    final bool narrow = TMLayout.isNarrow(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paperSunken,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: gutter,
              vertical: Space.xxl,
            ),
            child: Flex(
              direction: narrow ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment:
                  narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  flex: narrow ? 0 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('TutorMatch.ai', style: AppType.sectionTitle),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        width: 360,
                        child: Text(
                          'Matching by K-nearest neighbours over five dimensions: '
                          'subjects, available time, style, format and budget. '
                          'Every score can be opened and read.',
                          style: AppType.bodySmall.quieter,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: narrow ? 0 : Space.xxxl,
                  height: narrow ? Space.xl : 0,
                ),
                // Said plainly, in the product, where a person can see it.
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.ruleStrong),
                    borderRadius: Radii.sharpAll,
                  ),
                  child: Text(
                    'Interface prototype. Every tutor, student, score and review '
                    'on this site is sample data.',
                    style: AppType.bodySmall.quieter,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline with an optional caption sitting on it. The caption labels the
/// block underneath — it is a column header, never an eyebrow above a heading.
class TMRule extends StatelessWidget {
  const TMRule({this.label, this.top = 0, super.key});

  final String? label;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label != null) ...<Widget>[
            TMMicroLabelText(label!),
            const SizedBox(height: Space.sm),
          ],
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        ],
      ),
    );
  }
}

/// Kept separate so [TMRule] can stay const-friendly.
class TMMicroLabelText extends StatelessWidget {
  const TMMicroLabelText(this.text, {this.color = AppColors.inkMuted, super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppType.micro.tone(color));
}

/// A section heading with space above it and very little below. The asymmetry
/// is the point: it is what makes a page read as edited rather than stacked.
class TMSectionHeading extends StatelessWidget {
  const TMSectionHeading({
    required this.title,
    this.lede,
    this.width = 640,
    this.scale = TMSectionScale.normal,
    super.key,
  });

  final String title;
  final String? lede;
  final double width;
  final TMSectionScale scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: width + 80,
          child: Text(
            title,
            style: switch (scale) {
              TMSectionScale.normal => AppType.titleLarge,
              TMSectionScale.large => AppType.pageTitle,
            },
          ),
        ),
        if (lede != null) ...<Widget>[
          const SizedBox(height: Space.md),
          SizedBox(
            width: width,
            child: Text(lede!, style: AppType.bodyLarge.quiet),
          ),
        ],
      ],
    );
  }
}

enum TMSectionScale { normal, large }

/// The ruled container the product is built from. A card in everything but the
/// shadow, the radius and the padding.
class TMEntry extends StatelessWidget {
  const TMEntry({
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.selected = false,
    this.floating = false,
    this.onTap,
    this.backgroundColor,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  /// Declares a real offset shadow. Used for the request panel and anything
  /// that genuinely sits above the page — nowhere else.
  final bool floating;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget box = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ??
            (selected ? AppColors.accentWash : AppColors.paperRaised),
        borderRadius: Radii.sharpAll,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.rule,
        ),
        boxShadow: floating
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1417130E),
                  offset: Offset(0, 6),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap == null) return box;

    box = TMFocusable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.ease,
          transform: Matrix4.translationValues(0, s.hovered ? -1 : 0, 0),
          child: box,
        ),
      ),
    );
    return box;
  }
}
