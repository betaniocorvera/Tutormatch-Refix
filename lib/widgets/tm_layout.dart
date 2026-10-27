// ─────────────────────────────────────────────────────────────────────────────
// The frame: page shell, masthead, navigation, footer and the surfaces the
// product is built out of.
//
// Screens with three or more destinations get the application shell — a rail on
// a laptop, a bottom bar on a phone. Pages that are trying to persuade somebody
// (landing, sign-in) keep the conventional top bar. That split is the whole
// difference between a marketing page and the instrument you use afterwards.
//
// Depth comes from hairlines and one step of paper; shadows exist only for a
// surface that has physically lifted off the page.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/state/app_state.dart';
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
    if (w < AppBreakpoints.medium) return 28;
    if (w < AppBreakpoints.wide) return 36;
    return 44;
  }

  /// Column widths for the recurring asymmetric splits.
  static const double railWidth = 248;
  static const double asideWidth = 332;

  /// The shell becomes a side rail at this width. Below it, the same
  /// destinations become a bottom bar.
  static const double shellRail = 900;

  /// An aside can sit beside content only when there is still a readable
  /// measure left over.
  static const double asideBreakpoint = 1120;
}

/// A page. Every screen is one of these, which is what keeps the rhythm the same
/// from the landing page to the last tab of the requests screen.
class TMPage extends StatelessWidget {
  const TMPage({
    required this.child,
    this.navItems = const <TMNavItem>[],
    this.navTrailing,
    this.masthead = false,
    this.footer = true,
    this.maxWidth = AppBreakpoints.maxContent,
    this.aside,
    this.bottomBar,
    super.key,
  });

  final Widget child;
  final List<TMNavItem> navItems;
  final Widget? navTrailing;

  /// The rule across the very top, used only on the landing page.
  final bool masthead;
  final bool footer;
  final double maxWidth;

  /// A column that stays in view on a wide screen. On a phone it follows the
  /// content instead, because a sticky panel on a 390 px window is just a wall.
  final Widget? aside;

  /// A pinned strip above the bottom navigation, for the one action that must
  /// never be a scroll away. Shown below the rail breakpoint only.
  final Widget? bottomBar;

  bool get _shell => navItems.length >= 3;

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);
    final bool rail = _shell && width >= TMLayout.shellRail;
    final bool bottomNav = _shell && !rail;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: _shell ? _shellBody(context, rail: rail) : _simpleBody(context),
      ),
      bottomNavigationBar: (bottomNav || bottomBar != null)
          ? _bottomStack(context, showNav: bottomNav)
          : null,
    );
  }

  // ── Marketing / auth frame ─────────────────────────────────────────────────

  Widget _simpleBody(BuildContext context) {
    final double gutter = TMLayout.gutter(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (masthead)
          const SizedBox(height: 3, child: ColoredBox(color: AppColors.accent)),
        TMTopBar(navItems: navItems, trailing: navTrailing),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              primary: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
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
      ],
    );
  }

  // ── Application shell ──────────────────────────────────────────────────────

  Widget _shellBody(BuildContext context, {required bool rail}) {
    final double gutter = TMLayout.gutter(context);
    final bool asideBeside =
        aside != null && TMLayout.widthOf(context) >= TMLayout.asideBreakpoint;

    final Widget content = _content(context, gutter: gutter);

    final Widget scroller = Scrollbar(
      child: SingleChildScrollView(
        primary: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            content,
            if (aside != null && !asideBeside) ...<Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      Space.xxl,
                      gutter,
                      Space.xxxl,
                    ),
                    child: aside!,
                  ),
                ),
              ),
            ],
            SizedBox(height: rail ? Space.xxxl : Space.huge),
          ],
        ),
      ),
    );

    final Widget main = Column(
      children: <Widget>[
        if (!rail) _ShellTopBar(trailing: navTrailing),
        Expanded(
          child: asideBeside
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: scroller),
                    _AsidePanel(width: TMLayout.asideWidth, child: aside!),
                  ],
                )
              : scroller,
        ),
      ],
    );

    if (!rail) return main;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _NavRail(items: navItems, trailing: navTrailing),
        Expanded(child: main),
      ],
    );
  }

  Widget _content(BuildContext context, {required double gutter}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            TMLayout.isCompact(context) ? Space.xl : Space.xxl,
            gutter,
            0,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _bottomStack(BuildContext context, {required bool showNav}) {
    final Widget? action = bottomBar == null || MediaQuery.sizeOf(context).width >= TMLayout.shellRail
        ? null
        : DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.paperRaised,
              border: Border(top: BorderSide(color: AppColors.rule)),
            ),
            child: SafeArea(
              top: false,
              bottom: !showNav,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  TMLayout.gutter(context),
                  Space.md,
                  TMLayout.gutter(context),
                  Space.md,
                ),
                child: bottomBar,
              ),
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ?action,
        if (showNav) _BottomNav(items: navItems),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation items
// ─────────────────────────────────────────────────────────────────────────────

class TMNavItem {
  const TMNavItem({
    required this.label,
    this.onTap,
    this.selected = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final TMIconName? icon;
}

TMIconName _iconFor(String label, TMIconName? given) {
  if (given != null) return given;
  return switch (label.toLowerCase()) {
    'matches' => TMIconName.compass,
    'requests' => TMIconName.inbox,
    'messages' => TMIconName.chats,
    'profile' => TMIconName.user,
    _ => TMIconName.dots,
  };
}

int _messagesWaiting(BuildContext context) {
  final AppState state = AppStateScope.of(context);
  return state.conversations
      .where((Conversation c) =>
          c.status == RequestStatus.pending && !c.requestedByMe)
      .length;
}

void _goHome(BuildContext context) {
  Navigator.of(context).popUntil((Route<void> r) => r.isFirst);
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: () => _goHome(context),
      semanticButton: false,
      semanticLabel: 'TutorMatch, go to the start',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(right: Space.sm, bottom: 7),
                decoration: const BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                'TutorMatch',
                style: compact ? AppType.sectionTitle : AppType.wordmark,
              ),
              Text(
                '.ai',
                style: (compact ? AppType.sectionTitle : AppType.wordmark).tone(
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

class _NavRail extends StatelessWidget {
  const _NavRail({required this.items, this.trailing});

  final List<TMNavItem> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final int waiting = _messagesWaiting(context);

    return Container(
      width: TMLayout.railWidth,
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        border: Border(right: BorderSide(color: AppColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.lg, Space.xl),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Wordmark(compact: true),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.xl),
            child: TMMicroLabelText('Your desk'),
          ),
          const SizedBox(height: Space.sm),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              children: <Widget>[
                for (final TMNavItem item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _RailLink(
                      item: item,
                      icon: _iconFor(item.label, item.icon),
                      badge: item.label.toLowerCase() == 'messages' ? waiting : 0,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.rule)),
              ),
              child: trailing,
            ),
        ],
      ),
    );
  }
}

class _RailLink extends StatelessWidget {
  const _RailLink({required this.item, required this.icon, required this.badge});

  final TMNavItem item;
  final TMIconName icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: item.onTap,
      enabled: item.onTap != null || item.selected,
      semanticButton: false,
      semanticSelected: item.selected,
      semanticLabel: item.label,
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.ease,
          height: 48,
          decoration: BoxDecoration(
            color: item.selected
                ? AppColors.accentWash
                : s.hovered
                    ? AppColors.paperSunken
                    : Colors.transparent,
            borderRadius: Radii.sharpAll,
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: Motion.base,
                curve: Motion.ease,
                width: 3,
                height: item.selected ? 22 : 0,
                margin: const EdgeInsets.only(left: 1),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(Radii.pill)),
                ),
              ),
              const SizedBox(width: Space.md),
              TMIcon(
                icon,
                size: 19,
                color: item.selected ? AppColors.accent : AppColors.inkMuted,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.tone(
                    item.selected ? AppColors.ink : AppColors.inkSecondary,
                  ).copyWith(
                    fontWeight: item.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (badge > 0)
                Container(
                  margin: const EdgeInsets.only(right: Space.md),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: AppType.figure.copyWith(
                      fontSize: 11,
                      color: AppColors.onAmber,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: TMLayout.gutter(context)),
          child: SizedBox(
            height: 60,
            child: Row(
              children: <Widget>[
                const _Wordmark(compact: true),
                if (trailing != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing!,
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

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.items});

  final List<TMNavItem> items;

  @override
  Widget build(BuildContext context) {
    final int waiting = _messagesWaiting(context);

    return DecoratedBox(
      key: const Key('tm-bottom-nav'),
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          // A fixed touch band, plus the device's own bottom inset. The
          // Scaffold reserves this entire height for the body above it.
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Row(
              children: <Widget>[
                for (final TMNavItem item in items)
                  Expanded(
                    child: _BottomLink(
                      item: item,
                      icon: _iconFor(item.label, item.icon),
                      badge: item.label.toLowerCase() == 'messages' ? waiting : 0,
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

class _BottomLink extends StatelessWidget {
  const _BottomLink({
    required this.item,
    required this.icon,
    required this.badge,
  });

  final TMNavItem item;
  final TMIconName icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: item.onTap,
      enabled: item.onTap != null || item.selected,
      semanticButton: false,
      semanticSelected: item.selected,
      semanticLabel: item.label,
      builder: (BuildContext context, TMState s) => Stack(
        // Fill the whole slot, then centre the icon and label inside it. Without
        // this the loose Stack shrank to the label's intrinsic width and pinned
        // every item to the left of its slot, clipping "Matches" at the edge.
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: 0,
            left: 18,
            right: 18,
            child: AnimatedContainer(
              duration: Motion.respect(context, Motion.base),
              curve: Motion.ease,
              height: 2,
              decoration: BoxDecoration(
                color: item.selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
          AnimatedContainer(
            duration: Motion.respect(context, Motion.base),
            curve: Motion.ease,
            color: s.hovered && !item.selected
                ? AppColors.paperSunken.withValues(alpha: 0.6)
                : Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    TMIcon(
                      icon,
                      size: 21,
                      color: item.selected ? AppColors.accent : AppColors.inkMuted,
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -7,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 15),
                          height: 15,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(color: AppColors.paperRaised, width: 1.5),
                          ),
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: AppType.micro.copyWith(
                              fontSize: 8.5,
                              height: 1,
                              color: AppColors.onAmber,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppType.micro.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0.3,
                    ).tone(item.selected ? AppColors.accent : AppColors.inkMuted),
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

class _AsidePanel extends StatelessWidget {
  const _AsidePanel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width + TMLayout.gutter(context) + 20,
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(left: BorderSide(color: AppColors.rule)),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.fromLTRB(
            Space.xl,
            Space.xxl,
            TMLayout.gutter(context),
            Space.xxxl,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The marketing top bar
// ─────────────────────────────────────────────────────────────────────────────

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

    // On a phone the wordmark and the menu share the first line, and the auth
    // actions get a line of their own. Trying to fit brand, two actions and the
    // menu into 360 px only ever ends one way: a clipped primary button.
    final Widget menuButton = TMFocusable(
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
              color: s.hovered || _open ? AppColors.paperSunken : Colors.transparent,
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
    );

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
                  height: narrow ? 60 : 76,
                  child: narrow
                      ? Row(
                          children: <Widget>[
                            const _Wordmark(compact: true),
                            const Spacer(),
                            if (hasNav) menuButton,
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const _Wordmark(),
                            if (hasNav || widget.trailing != null)
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
                                    if (widget.trailing != null)
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: widget.trailing!,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                if (narrow && widget.trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: widget.trailing!,
                    ),
                  ),
                AnimatedSize(
                  duration: Motion.respect(context, Motion.base),
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
            padding: EdgeInsets.symmetric(horizontal: block ? Space.md : Space.md),
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
                AnimatedContainer(
                  duration: Motion.respect(context, Motion.fast),
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

// ─────────────────────────────────────────────────────────────────────────────
// Footer and section furniture
// ─────────────────────────────────────────────────────────────────────────────

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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: Space.sm, bottom: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text('TutorMatch.ai', style: AppType.sectionTitle),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        width: 380,
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
                Container(
                  constraints: const BoxConstraints(maxWidth: 310),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paperRaised,
                    border: Border.all(color: AppColors.ruleStrong),
                    borderRadius: Radii.sharpAll,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: Space.sm),
                        child: TMIcon(
                          TMIconName.warning,
                          size: 14,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Interface prototype. People, scores and messages come '
                          'from the TutorMatch API.',
                          style: AppType.bodySmall.quieter,
                        ),
                      ),
                    ],
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

/// The surface the product is built from: one step lighter than the page, a
/// hairline, and a 12 px corner. Depth is expressed by the rule and by space;
/// shadow is reserved for something that genuinely floats.
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
  final bool floating;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget surface = AnimatedContainer(
      duration: Motion.respect(context, Motion.fast),
      curve: Motion.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ??
            (selected ? AppColors.accentWash : AppColors.paperRaised),
        borderRadius: Radii.sharpAll,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.rule,
        ),
        boxShadow: floating ? TMShadows.floating : null,
      ),
      child: child,
    );

    if (onTap == null) return surface;

    return TMFocusable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: AnimatedContainer(
          duration: Motion.respect(context, Motion.fast),
          curve: Motion.ease,
          transform: Matrix4.translationValues(0, s.hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: Radii.sharpAll,
            boxShadow: s.hovered ? TMShadows.floating : null,
          ),
          child: surface,
        ),
      ),
    );
  }
}
