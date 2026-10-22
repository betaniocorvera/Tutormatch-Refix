// ─────────────────────────────────────────────────────────────────────────────
// The landing page — the one screen in the product that is allowed to be
// cinematic.
//
// Everything else here is an instrument; this page is the argument for the
// instrument. The opening is a single tall scroll region: a full-screen ink
// stage, the neighbour map inside it, and three sentences that arrive as the
// map assembles. Scrolling is the only input — no autoplay carousel, no looping
// video — and the arithmetic the product actually runs does the work.
//
// Scroll drives exactly two things:
//   • the damped progress handed to NeighborMap3D, where people travel from the
//     outer ring inward to the ring their rank earns, and
//   • which of the three stage sentences is on screen.
// The map owns its own repaints and the HUD owns its own, so the page itself
// never rebuilds while scrolling: the transform on the sticky stage is the only
// paint-time change per frame.
//
// Below the fold the page is paper again: how the ranking works, the subjects
// in the sample pool, and the way in. The ranked rows themselves live behind
// sign-in on the matches screen; this page never duplicates them.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/neighbor_map_3d.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

/// The hero stage swap. Long enough to read as a cut, short enough that the
/// sentence is never late for the scroll that asked for it.
const Duration _stageSwap = Duration(milliseconds: 450);

/// How far the page must travel before the top bar stops being transparent.
const double _solidAfter = 60;

/// The damped scroll. One constant, stated once: the map's arrival is a
/// weighted average, not a linear map of the scrollbar.
const double _damping = 0.085;

/// The bar's own height, including the device's top inset. Used by the hero
/// stage and by anchor scrolling, so a jumped-to heading never lands under it.
double _topBarHeight(BuildContext context) =>
    (TMLayout.widthOf(context) >= TMLayout.shellRail ? 72 : 60) +
    MediaQuery.paddingOf(context).top;

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// The stage's translation, in pixels. Follows the scroll exactly: the pin
  /// must not lag, or the stage visibly smears against the page.
  final ValueNotifier<double> _heroOffset = ValueNotifier<double>(0);

  /// The damped 0–1 progress handed to the map and the HUD.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// Which of the three sentences is on screen, derived from the damped value.
  final ValueNotifier<int> _stage = ValueNotifier<int>(0);

  /// Whether the top bar has left the hero behind.
  final ValueNotifier<bool> _solid = ValueNotifier<bool>(false);

  final GlobalKey _howKey = GlobalKey();
  final GlobalKey _subjectsKey = GlobalKey();

  late final Ticker _ticker = createTicker(_damp);

  /// Where the damped value is heading. Set on scroll, read by the ticker.
  double _target = 0;

  /// The distance the sticky stage travels inside its own scroll region.
  double _pin = 0;

  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _progress.addListener(_syncStage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.reduced(context);
    if (_reduced && _progress.value != 1) {
      _target = 1;
      _progress.value = 1;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _ticker.dispose();
    _scroll.dispose();
    _progress.removeListener(_syncStage);
    _heroOffset.dispose();
    _progress.dispose();
    _stage.dispose();
    _solid.dispose();
    super.dispose();
  }

  void _syncStage() {
    final double p = _progress.value;
    final int next = p < 0.33 ? 0 : (p < 0.67 ? 1 : 2);
    if (next != _stage.value) _stage.value = next;
  }

  void _onScroll() {
    final double offset = _scroll.offset;

    final bool solid = offset > _solidAfter;
    if (solid != _solid.value) _solid.value = solid;

    if (_pin <= 0) return;
    _heroOffset.value = offset.clamp(0.0, _pin);

    // Reduced motion gets the finished state and no scrub: the stage still
    // pins, because pinning is layout rather than animation, but nothing about
    // it moves with the scrollbar.
    if (_reduced) return;
    _target = (offset / _pin).clamp(0.0, 1.0);
    if (!_ticker.isActive && (_target - _progress.value).abs() > 0.0005) {
      _ticker.start();
    }
  }

  void _damp(Duration _) {
    final double next = _progress.value + (_target - _progress.value) * _damping;
    if ((_target - next).abs() < 0.0008) {
      _progress.value = _target;
      _ticker.stop();
      return;
    }
    _progress.value = next;
  }

  void _to(GlobalKey key) {
    final BuildContext? target = key.currentContext;
    if (target == null || !_scroll.hasClients) return;

    final RenderObject? object = target.findRenderObject();
    if (object is! RenderBox || !object.attached) return;

    // `ensureVisible(alignment: 0)` would put the heading exactly under the
    // fixed bar. Keep the bar's height plus a breath of air out of the jump.
    final double top = object.localToGlobal(Offset.zero).dy + _scroll.offset;
    final double destination = (top - _topBarHeight(context) - Space.lg)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      destination,
      duration: Motion.respect(context, Motion.page),
      curve: Motion.emphasized,
    );
  }

  void _toTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: Motion.respect(context, Motion.page),
      curve: Motion.emphasized,
    );
  }

  void _open(String route, [Object? arguments]) {
    Navigator.of(context).pushNamed(route, arguments: arguments);
  }

  void _start(Role role, {bool signIn = false}) {
    // Starting a fresh auth flow from the landing page supersedes any page a
    // previous guard redirect was holding on to.
    AppStateScope.read(context).clearPendingDestination();
    _open(signIn ? Routes.login : Routes.register, role);
  }

  /// The three sentences, in order. Built here because each one needs its own
  /// destination and this is the only place that knows all of them.
  List<_StageCopy> _copies(BuildContext context) => <_StageCopy>[
    _StageCopy(
      eyebrow: '16 sample tutors · one shared week',
      title: 'The tutor who is free on Tuesday at six.',
      body: 'Most tutoring sites rank on subject and price, then leave you to '
          'discover that nobody is free when you are. This one ranks the five '
          'things that decide whether lessons actually happen.',
      primary: 'Find my tutor',
      secondary: 'I teach instead',
      onPrimary: () => _start(Role.student),
      onSecondary: () => _start(Role.tutor),
    ),
    _StageCopy(
      eyebrow: 'Five dimensions · one hundred points',
      title: 'Five numbers decide this. Nothing else is compared.',
      body: 'Subjects, style, format, budget and shared time each carry a fixed '
          'share of the hundred points. Time weighs the same as the rest, so a '
          'strong subject match cannot hide a week that never lines up.',
      primary: 'See how it works',
      secondary: 'Read a result',
      onPrimary: () => _to(_howKey),
      onSecondary: () => _start(Role.student, signIn: true),
    ),
    _StageCopy(
      eyebrow: 'Your week, counted first',
      title: 'Ask for the hour. Keep the conversation.',
      body: 'The request carries the day you chose and what the first lesson '
          'should cover. The moment they accept, the thread opens — and every '
          'score you opened stays itemised.',
      primary: 'Create account',
      secondary: 'Sign in',
      onPrimary: () => _start(Role.student),
      onSecondary: () => _start(Role.student, signIn: true),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);
    final bool wide = width >= TMLayout.shellRail;
    final double gutter = TMLayout.gutter(context);

    final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
    final Map<String, MatchResult> byId = <String, MatchResult>{
      for (final MatchResult r in ranked) r.candidate.id: r,
    };
    final List<NeighborNode> nodes = <NeighborNode>[
      for (final MatchResult r in ranked.take(10))
        NeighborNode(
          id: r.candidate.id,
          name: r.candidate.name,
          subject: r.candidate.subjects.first,
          score: r.score.total,
          tint: r.candidate.photoTint,
        ),
    ];

    // The pool, counted by subject. Ties are broken by name so the four cards
    // do not reshuffle between builds.
    final Map<String, List<Candidate>> bySubject = <String, List<Candidate>>{};
    for (final Candidate tutor in sampleTutors) {
      for (final String subject in tutor.subjects) {
        bySubject.putIfAbsent(subject, () => <Candidate>[]).add(tutor);
      }
    }
    final List<_SubjectStat> subjects = <_SubjectStat>[
      for (final MapEntry<String, List<Candidate>> entry in bySubject.entries)
        _SubjectStat(subject: entry.key, tutors: entry.value),
    ]..sort((a, b) {
        final int byCount = b.tutors.length.compareTo(a.tutors.length);
        return byCount != 0 ? byCount : a.subject.compareTo(b.subject);
      });

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double viewport = constraints.maxHeight;
                // The scroll the hero is worth: three screens on a laptop, a
                // little over two on a phone, where thumb travel is expensive.
                final double span = viewport * (wide ? 3.0 : 2.2);
                _pin = math.max(0, span - viewport);

                return Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _heroRegion(
                          viewport: viewport,
                          span: span,
                          wide: wide,
                          nodes: nodes,
                          gutter: gutter,
                          onNode: (NeighborNode node) {
                            final MatchResult? match = byId[node.id];
                            if (match == null) {
                              _start(Role.student);
                              return;
                            }
                            _open(Routes.matchDetail, match);
                          },
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppBreakpoints.maxContent,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: gutter),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  SizedBox(height: Space.band(width)),

                                  // ── How it works ─────────────────────────────
                                  Container(
                                    key: _howKey,
                                    child: _About(wide: wide, onStart: _start),
                                  ),

                                  SizedBox(height: Space.band(width)),

                                  // ── The pool, by subject ─────────────────────
                                  _SubjectsCarousel(
                                    key: _subjectsKey,
                                    wide: wide,
                                    subjects: subjects
                                        .take(4)
                                        .toList(growable: false),
                                    onOpenTutors: () => _start(Role.student),
                                  ),

                                  SizedBox(
                                    height: Space.band(width) + Space.xl,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── The close ──────────────────────────────────────
                        _CtaBand(wide: wide, onStart: _start),
                        _LandingFooter(
                          wide: wide,
                          onHome: _toTop,
                          onHow: () => _to(_howKey),
                          onTutors: () => _start(Role.student),
                          onSubjects: () => _to(_subjectsKey),
                          onSignIn: () => _start(Role.student, signIn: true),
                          onStart: () => _start(Role.student),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _LandingHeader(
              solid: _solid,
              wide: wide,
              onHome: _toTop,
              onHow: () => _to(_howKey),
              onTutors: () => _start(Role.student),
              onSubjects: () => _to(_subjectsKey),
              onSignIn: () => _start(Role.student, signIn: true),
              onStart: () => _start(Role.student),
            ),
          ),
        ],
      ),
    );
  }

  /// The tall region the hero lives in. The stage is one viewport high and is
  /// translated by exactly the scroll it has absorbed, so it holds still for
  /// [span] pixels and is then carried away by the page like any other band.
  Widget _heroRegion({
    required double viewport,
    required double span,
    required bool wide,
    required List<NeighborNode> nodes,
    required double gutter,
    required ValueChanged<NeighborNode> onNode,
  }) {
    return SizedBox(
      height: span,
      // A tight height of [span] here would force the viewport-tall stage to
      // stretch to the whole region. Align hands the stage loose constraints,
      // so it can stay exactly one viewport high and be carried down by the
      // transform as the page scrolls.
      child: Align(
        alignment: Alignment.topCenter,
        child: ValueListenableBuilder<double>(
          valueListenable: _heroOffset,
          builder: (BuildContext context, double offset, Widget? child) =>
              Transform.translate(
            offset: Offset(0, _reduced ? _pin : offset),
            child: child,
          ),
          child: SizedBox(
            width: double.infinity,
            height: viewport,
            child: _HeroStage(
              wide: wide,
              gutter: gutter,
              nodes: nodes,
              progress: _progress,
              stage: _stage,
              copies: _copies(context),
              onNode: onNode,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The hero stage
// ─────────────────────────────────────────────────────────────────────────────

/// One sentence's worth of hero: what it says and where its two buttons go.
class _StageCopy {
  const _StageCopy({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.primary,
    required this.secondary,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String primary;
  final String secondary;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
}

/// The full-screen ink stage: measured field, neighbour map, one sentence, and
/// the instrument strip at the bottom. Built once; only the copy switcher, the
/// HUD and the map itself ever rebuild.
class _HeroStage extends StatelessWidget {
  const _HeroStage({
    required this.wide,
    required this.gutter,
    required this.nodes,
    required this.progress,
    required this.stage,
    required this.copies,
    required this.onNode,
  });

  final bool wide;
  final double gutter;
  final List<NeighborNode> nodes;
  final ValueListenable<double> progress;
  final ValueListenable<int> stage;
  final List<_StageCopy> copies;
  final ValueChanged<NeighborNode> onNode;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final double barBand = _topBarHeight(context);
    final double hudBand = 40 + safe.bottom;

    final Widget map = RepaintBoundary(
      child: NeighborMap3D(
        nodes: nodes,
        height: 560,
        userLabel: 'You',
        background: AppColors.ink,
        showLegend: false,
        progress: progress,
        onSelect: onNode,
      ),
    );

    return ColoredBox(
      color: AppColors.ink,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _StageField())),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: barBand, bottom: hudBand),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              gutter,
                              Space.xl,
                              Space.xxl,
                              Space.xl,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: _HeroCopySwitcher(
                                  stage: stage,
                                  copies: copies,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              Space.lg,
                              Space.xl,
                              Space.md,
                              0,
                            ),
                            // Mouse only: on a touch screen the map must not
                            // swallow the drag that is meant to scroll the page.
                            child: map,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            Space.lg,
                            gutter,
                            0,
                          ),
                          child: _HeroCopySwitcher(stage: stage, copies: copies),
                        ),
                        const SizedBox(height: Space.lg),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: gutter),
                            child: _MapOrnament(child: map),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Positioned(
            left: gutter,
            right: gutter,
            bottom: safe.bottom + Space.md,
            child: _HeroHud(progress: progress),
          ),
        ],
      ),
    );
  }
}

/// On a phone the map is scenery: the drag that would orbit it belongs to the
/// page. Taps are disabled with it, because a tour of the pool is three scrolls
/// away and one button below.
class _MapOrnament extends StatelessWidget {
  const _MapOrnament({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(ignoring: true, child: child);
}

class _HeroCopySwitcher extends StatelessWidget {
  const _HeroCopySwitcher({required this.stage, required this.copies});

  final ValueListenable<int> stage;
  final List<_StageCopy> copies;

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);

    return ValueListenableBuilder<int>(
      valueListenable: stage,
      builder: (BuildContext context, int index, Widget? _) {
        // Each sentence has a different number of lines. Letting the block
        // resize with the cut keeps the centred copy from snapping after the
        // outgoing sentence is removed.
        return AnimatedSize(
          duration: Motion.respect(context, _stageSwap),
          curve: Motion.emphasized,
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: Motion.respect(context, _stageSwap),
            switchInCurve: Motion.emphasized,
            switchOutCurve: Motion.ease,
            layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
              alignment: Alignment.topLeft,
              children: <Widget>[
                ...previous,
                ?current,
              ],
            ),
            transitionBuilder: (Widget child, Animation<double> animation) =>
                FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            // Text is never dimmed: the stage sentence is at full opacity at
            // rest and only crosses over during the 450 ms cut.
            child: KeyedSubtree(
              key: ValueKey<int>(index),
              child: SizedBox(
                width: double.infinity,
                child: _HeroCopy(copy: copies[index], width: width),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.copy, required this.width});

  final _StageCopy copy;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool compact = width < AppBreakpoints.compact;

    return TMInkContext(
      onInk: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.eyebrow.toUpperCase(),
            style: AppType.micro
                .copyWith(fontSize: 10, letterSpacing: 1.8)
                .tone(AppColors.amber),
          ),
          SizedBox(height: compact ? Space.md : Space.lg),
          Text(copy.title, style: AppType.heroAt(width).tone(AppColors.onAccent)),
          SizedBox(height: compact ? Space.md : Space.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              copy.body,
              style: (compact ? AppType.body : AppType.bodyLarge)
                  .tone(AppColors.onInkQuiet),
            ),
          ),
          SizedBox(height: compact ? Space.lg : Space.xxl),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            children: <Widget>[
              TMButton(
                label: copy.primary,
                icon: TMIconName.arrowRight,
                onPressed: copy.onPrimary,
              ),
              TMButton(
                label: copy.secondary,
                variant: TMButtonVariant.onInk,
                onPressed: copy.onSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The instrument strip: who this pool is on the left, which of the three
/// sentences you are reading on the right. Each stage owns a hairline that
/// fills as its sentence is consumed — 15% before it starts, 100% as it ends —
/// so the strip reads as a position, not as a pagination widget.
class _HeroHud extends StatelessWidget {
  const _HeroHud({required this.progress});

  final ValueListenable<double> progress;

  static const List<double> _starts = <double>[0, 0.33, 0.67];
  static const List<double> _ends = <double>[0.33, 0.67, 1.0];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (BuildContext context, double p, Widget? _) {
        final int active = p < 0.33 ? 0 : (p < 0.67 ? 1 : 2);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            ExcludeSemantics(
              child: Text(
                'STUDENTS + TUTORS',
                style: AppType.micro
                    .copyWith(fontSize: 9, letterSpacing: 1.6)
                    .tone(AppColors.onInkFaint),
              ),
            ),
            const Spacer(),
            Semantics(
              label: 'Stage ${active + 1} of 3',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < 3; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: Space.lg),
                      _StageTick(
                        index: i,
                        active: i == active,
                        fill: i < active
                            ? 1
                            : i > active
                                ? 0.15
                                : 0.15 +
                                    0.85 *
                                        ((p - _starts[i]) /
                                                (_ends[i] - _starts[i]))
                                            .clamp(0.0, 1.0),
                      ),
                    ],
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

class _StageTick extends StatelessWidget {
  const _StageTick({
    required this.index,
    required this.active,
    required this.fill,
  });

  final int index;
  final bool active;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final Color tone = active ? AppColors.amber : AppColors.onInkFaint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '0${index + 1}',
          style: AppType.figure.copyWith(
            fontSize: 12,
            color: tone,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 34,
          height: 2,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.onInkFaint.withValues(alpha: 0.22),
                ),
              ),
              // The fill needs an explicit height: a bare ColoredBox under
              // loose constraints collapses to zero and the strip loses its
              // only sign of progress.
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 34 * fill.clamp(0.0, 1.0),
                  height: 2,
                  child: ColoredBox(color: tone),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The furthest plane of the hero. Cool paper on ink: a measured grid, marked
/// every fourth crossing, at the edge of visibility. It is a place, not a
/// decoration — the same logic as the week grid, drawn large enough to read as
/// territory.
class _StageField extends CustomPainter {
  const _StageField();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const double gap = 64;

    final Paint line = Paint()
      ..color = AppColors.onAccent.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    final Paint mark = Paint()
      ..color = AppColors.amber.withValues(alpha: 0.14);

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (double x = 0; x < size.width; x += gap * 4) {
      for (double y = 0; y < size.height; y += gap * 4) {
        canvas.drawCircle(Offset(x, y), 1.6, mark);
      }
    }
  }

  @override
  bool shouldRepaint(_StageField oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// The top bar
// ─────────────────────────────────────────────────────────────────────────────

/// One bar for the whole page. Transparent and paper-coloured over the ink
/// hero, then solid paper with a hairline and a blur once the page has left it.
class _LandingHeader extends StatelessWidget {
  const _LandingHeader({
    required this.solid,
    required this.wide,
    required this.onHome,
    required this.onHow,
    required this.onTutors,
    required this.onSubjects,
    required this.onSignIn,
    required this.onStart,
  });

  final ValueListenable<bool> solid;
  final bool wide;
  final VoidCallback onHome;
  final VoidCallback onHow;
  final VoidCallback onTutors;
  final VoidCallback onSubjects;
  final VoidCallback onSignIn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final double gutter = TMLayout.gutter(context);

    return ValueListenableBuilder<bool>(
      valueListenable: solid,
      builder: (BuildContext context, bool isSolid, Widget? _) {
        final Color ink = isSolid ? AppColors.ink : AppColors.onAccent;
        final Color quiet = isSolid ? AppColors.inkMuted : AppColors.onInkQuiet;
        final Color hover = isSolid ? AppColors.accent : AppColors.amber;

        Widget background = AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.ease,
          color: isSolid
              ? AppColors.paperRaised.withValues(alpha: 0.9)
              : Colors.transparent,
        );
        if (isSolid) {
          background = ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: background,
            ),
          );
        }

        final Widget row = SizedBox(
          height: wide ? 72 : 60,
          child: Row(
            children: <Widget>[
              _Wordmark(color: ink, accent: quiet, onTap: onHome),
              if (wide) ...<Widget>[
                const SizedBox(width: Space.xxl),
                for (final (String, VoidCallback) item in <(String, VoidCallback)>[
                  ('How it works', onHow),
                  ('Tutors', onTutors),
                  ('Subjects', onSubjects),
                ])
                  _HeaderLink(
                    label: item.$1,
                    color: quiet,
                    hover: hover,
                    onTap: item.$2,
                  ),
              ],
              const Spacer(),
              TMTextLink(
                label: 'Sign in',
                color: quiet,
                hoverColor: hover,
                minHeight: Hit.min,
                onTap: onSignIn,
              ),
              const SizedBox(width: Space.sm),
              TMButton(
                label: wide ? 'Get started' : 'Start',
                minHeight: Hit.min,
                variant: isSolid
                    ? TMButtonVariant.primary
                    : TMButtonVariant.secondary,
                onPressed: onStart,
              ),
            ],
          ),
        );

        return TMInkContext(
          onInk: !isSolid,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: background),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: row,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: isSolid ? AppColors.rule : Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.color,
    required this.accent,
    required this.onTap,
  });

  final Color color;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticLabel: 'TutorMatch, back to the top',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Space.sm,
            horizontal: Space.xxs,
          ),
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
              Text('TutorMatch', style: AppType.wordmark.tone(color)),
              Text(
                '.ai',
                style: AppType.wordmark.tone(
                  s.hovered || s.focused ? accent : color.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({
    required this.label,
    required this.color,
    required this.hover,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color hover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticLabel: label,
      builder: (BuildContext context, TMState s) {
        final bool lit = s.hovered || s.focused;
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: AppType.label.tone(lit ? hover : color)),
                const SizedBox(height: Space.xs),
                AnimatedContainer(
                  duration: Motion.respect(context, Motion.fast),
                  curve: Motion.ease,
                  height: 2,
                  width: lit ? 18 : 0,
                  color: lit ? hover : Colors.transparent,
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
// Section furniture shared by everything below the hero
// ─────────────────────────────────────────────────────────────────────────────

/// One mechanism for "it arrived when you looked at it".
///
/// The page is a Column inside one scroll view, so a controller that starts on
/// mount animates the whole page at once — most of it off screen. This checks
/// its own render object against the window instead, on each scroll frame until
/// it has fired once, then unhooks itself. Reduced motion renders at 1 and
/// never listens at all.
class _InView extends StatefulWidget {
  const _InView({
    required this.builder,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
  });

  final Widget Function(BuildContext context, double t) builder;
  final Duration delay;
  final Duration duration;

  @override
  State<_InView> createState() => _InViewState();
}

class _InViewState extends State<_InView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  ScrollPosition? _position;
  Timer? _timer;
  double _screen = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context).height;

    // Ask for the vertical scrollable explicitly. The subject row is itself a
    // horizontal scrollable, and listening to that one would mean these
    // reveals never hear the page move.
    final ScrollPosition? next =
        Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_check);
      _position = next;
      _position?.addListener(_check);
    }
    if (!_started) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  void _check() {
    if (_started || !mounted) return;
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return;

    final double top = object.localToGlobal(Offset.zero).dy;
    final double bottom = top + object.size.height;
    if (top > _screen * 0.9 || bottom < 0) return;

    _started = true;
    _position?.removeListener(_check);

    if (Motion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _position?.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final double t = Motion.ease.transform(_controller.value);
        return IgnorePointer(
          ignoring: t < 0.9,
          child: widget.builder(context, t),
        );
      },
    );
  }
}

/// A block that rises 24 px into place the first time it is looked at.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return _InView(
      delay: delay,
      duration: const Duration(milliseconds: 720),
      builder: (BuildContext context, double t) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 24),
          child: child,
        ),
      ),
    );
  }
}

/// A number that counts to itself once, when the viewer arrives. The label
/// under it always says where the number came from.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.label,
    this.suffix = '',
    this.delay = Duration.zero,
  });

  final int value;
  final String label;
  final String suffix;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return _InView(
      delay: delay,
      duration: const Duration(milliseconds: 780),
      builder: (BuildContext context, double t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '${(value * t).round()}',
                style: AppType.score.copyWith(
                  fontSize: 34,
                  letterSpacing: -1.4,
                  color: AppColors.accent,
                ),
              ),
              if (suffix.isNotEmpty) ...<Widget>[
                const SizedBox(width: Space.xs),
                Text(suffix, style: AppType.figureLarge.tone(AppColors.inkMuted)),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(label, style: AppType.bodySmall.quieter),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// How it works
// ─────────────────────────────────────────────────────────────────────────────

class _About extends StatelessWidget {
  const _About({required this.wide, required this.onStart});

  final bool wide;
  final void Function(Role role) onStart;

  static const List<(String, String, String, TMIconName)> _steps =
      <(String, String, String, TMIconName)>[
    (
      'Register',
      'Answer five things',
      'Subjects, how you like to work, the hours you keep, online or in a room, '
          'and what you can spend. Two minutes, and nothing is saved until you '
          'choose to keep it.',
      TMIconName.book,
    ),
    (
      'Search',
      'Read the ranking',
      'Every tutor gets a score out of 100, three reasons in plain language, '
          'and a week grid showing the hours you both actually have free.',
      TMIconName.target,
    ),
    (
      'Chat',
      'Ask for the hour',
      'The request carries the day you chose and what the first lesson should '
          'cover. The conversation opens the moment they accept.',
      TMIconName.send,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const Widget heading = TMSectionHeading(
      title: 'Three steps, and the guesswork is gone.',
      lede: 'No browsing a directory. No messaging five people to find out '
          'their Tuesday is full. This is the whole path from a cold start to a '
          'booked hour.',
      width: 460,
      scale: TMSectionScale.large,
    );

    final Widget aside = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'The five dimensions are subjects, style, format, budget and shared '
            'time. Each one carries a fixed share of the hundred points, and the '
            'share is printed on every score you open.',
            style: AppType.body.quiet,
          ),
        ),
        const SizedBox(height: Space.lg),
        TMTextLink(
          label: 'Start with the first step',
          icon: TMIconName.arrowRight,
          style: AppType.label,
          color: AppColors.accent,
          minHeight: Hit.min,
          onTap: () => onStart(Role.student),
        ),
      ],
    );

    final Widget steps = Column(
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++)
          _Reveal(
            delay: Duration(milliseconds: Motion.stagger.inMilliseconds * i),
            child: _Step(
              number: i + 1,
              label: _steps[i].$1,
              title: _steps[i].$2,
              body: _steps[i].$3,
              icon: _steps[i].$4,
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Reveal(child: heading),
        SizedBox(height: wide ? Space.huge : Space.xl),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 4, child: aside),
              const SizedBox(width: Space.huge),
              Expanded(flex: 5, child: steps),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              aside,
              SizedBox(height: Space.xxl),
              steps,
            ],
          ),
        SizedBox(height: wide ? Space.vast : Space.huge),
        const _CounterStrip(),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.label,
    required this.title,
    required this.body,
    required this.icon,
  });

  final int number;
  final String label;
  final String title;
  final String body;
  final TMIconName icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.lg),
          Row(
            children: <Widget>[
              Text(
                '0$number',
                style: AppType.figureLarge.tone(AppColors.accent),
              ),
              const SizedBox(width: Space.md),
              Text(
                label.toUpperCase(),
                style: AppType.micro.tone(AppColors.inkMuted),
              ),
              const Spacer(),
              TMIcon(icon, size: 18, color: AppColors.inkMuted),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(title, style: AppType.titleLarge),
          const SizedBox(height: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(body, style: AppType.body.quiet),
          ),
        ],
      ),
    );
  }
}

/// Four numbers, counted from the sample pool, with the caption that keeps them
/// honest. Nothing here is a market statistic: the pool is sixteen people in a
/// prototype.
class _CounterStrip extends StatelessWidget {
  const _CounterStrip();

  static const List<(int, String, String)> _counters = <(int, String, String)>[
    (16, 'sample tutors in the pool', ''),
    (5, 'dimensions compared', ''),
    (100, 'points on the scale', ''),
    (2, 'minutes to answer five questions', 'min'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Row(
          children: <Widget>[
            const TMMicroLabelText('Sample data'),
            const Spacer(),
            Flexible(
              child: Text(
                'Counted from this prototype\'s own pool',
                style: AppType.bodySmall.quieter,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 860;
            final int perRow = wide ? 4 : 2;
            final double cell =
                (constraints.maxWidth - (perRow - 1) * Space.xl) / perRow;

            return Wrap(
              spacing: Space.xl,
              runSpacing: Space.xxl,
              children: <Widget>[
                for (int i = 0; i < _counters.length; i++)
                  SizedBox(
                    width: cell,
                    child: _CountUp(
                      value: _counters[i].$1,
                      label: _counters[i].$2,
                      suffix: _counters[i].$3,
                      delay: Duration(
                        milliseconds: Motion.stagger.inMilliseconds * i,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The pool, by subject
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectStat {
  const _SubjectStat({required this.subject, required this.tutors});

  final String subject;
  final List<Candidate> tutors;
}

class _SubjectsCarousel extends StatefulWidget {
  const _SubjectsCarousel({
    required this.wide,
    required this.subjects,
    required this.onOpenTutors,
    super.key,
  });

  final bool wide;
  final List<_SubjectStat> subjects;
  final VoidCallback onOpenTutors;

  @override
  State<_SubjectsCarousel> createState() => _SubjectsCarouselState();
}

class _SubjectsCarouselState extends State<_SubjectsCarousel> {
  final ScrollController _row = ScrollController();

  /// One card plus one gutter. Set during layout, used by the buttons.
  double _step = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _row.addListener(_onScroll);
  }

  @override
  void dispose() {
    _row.removeListener(_onScroll);
    _row.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_step <= 0) return;
    final int next =
        (_row.offset / _step).round().clamp(0, widget.subjects.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  void _move(int delta) {
    if (!_row.hasClients || _step <= 0) return;
    final int next =
        (_index + delta).clamp(0, widget.subjects.length - 1);
    _row.animateTo(
      (next * _step).clamp(0.0, _row.position.maxScrollExtent),
      duration: Motion.respect(context, Motion.page),
      curve: Motion.emphasized,
    );
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final int total = widget.subjects.length;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Reveal(
          child: const TMSectionHeading(
            title: 'What this pool actually teaches.',
            lede: 'Counted from the sixteen sample tutors, not from a market '
                'report. Each card opens registration for that subject.',
            width: 480,
            scale: TMSectionScale.large,
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double card = widget.wide
                ? 320.0
                : math
                    .min(constraints.maxWidth - 40, 320.0)
                    .clamp(220.0, 320.0);
            _step = card + Space.xl;

            return SingleChildScrollView(
              controller: _row,
              scrollDirection: Axis.horizontal,
              // The row must not cut the shadow off a card that has been
              // lifted, so it clips nothing and carries 56 px of air top and
              // bottom for the shadow to fall into.
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < total; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.xl),
                      child: SizedBox(
                        width: card,
                        child: _Reveal(
                          delay: Duration(
                            milliseconds: Motion.stagger.inMilliseconds * i,
                          ),
                          child: _SubjectCard(
                            stat: widget.subjects[i],
                            onFind: widget.onOpenTutors,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Row(
          children: <Widget>[
            Text(
              '${(_index + 1).toString().padLeft(2, '0')} / '
              '${total.toString().padLeft(2, '0')}',
              style: AppType.figure.copyWith(color: AppColors.inkMuted),
            ),
            const Spacer(),
            _CarouselButton(
              icon: TMIconName.arrowLeft,
              label: 'Previous subject',
              onTap: _index > 0 ? () => _move(-1) : null,
            ),
            const SizedBox(width: Space.sm),
            _CarouselButton(
              icon: TMIconName.arrowRight,
              label: 'Next subject',
              onTap: _index < total - 1 ? () => _move(1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CarouselButton extends StatelessWidget {
  const _CarouselButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final TMIconName icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool live = onTap != null;

    return TMFocusable(
      onTap: onTap,
      enabled: live,
      semanticLabel: label,
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.pill,
        child: Opacity(
          // A dead end has to look like one. The buttons keep their 44 px
          // target and simply stop inviting the tap.
          opacity: live ? 1 : 0.4,
          child: AnimatedContainer(
            duration: Motion.respect(context, Motion.fast),
            curve: Motion.ease,
            width: Hit.min,
            height: Hit.min,
            decoration: BoxDecoration(
              color: s.hovered && live
                  ? AppColors.paperSunken
                  : AppColors.paperRaised,
              shape: BoxShape.circle,
              border: Border.all(
                color: s.hovered && live
                    ? AppColors.ruleStrong
                    : AppColors.rule,
              ),
            ),
            child: Center(
              child: TMIcon(
                icon,
                size: 18,
                color: live ? AppColors.ink : AppColors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One subject and the people who teach it. The card carries a resting shadow —
/// it is the one surface on this page that floats rather than sits — and the
/// row it lives in is built not to cut that shadow off.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.stat, required this.onFind});

  final _SubjectStat stat;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final List<Candidate> shown =
        stat.tutors.take(3).toList(growable: false);
    final int more = stat.tutors.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: Radii.sharpAll,
        border: Border.all(color: AppColors.rule),
        boxShadow: TMShadows.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  stat.subject,
                  style: AppType.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(
                '${stat.tutors.length}',
                style: AppType.figureLarge.tone(AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            stat.tutors.length == 1
                ? '1 tutor in the sample pool'
                : '${stat.tutors.length} tutors in the sample pool',
            style: AppType.bodySmall.quieter,
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              for (int i = 0; i < shown.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Space.sm),
                TMAvatar(shown[i].name, size: 28, tint: shown[i].photoTint),
              ],
              if (more > 0) ...<Widget>[
                const SizedBox(width: Space.sm),
                Text(
                  '+$more',
                  style: AppType.figure
                      .copyWith(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.xl),
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.sm),
          TMTextLink(
            label: 'Find a tutor',
            icon: TMIconName.arrowRight,
            style: AppType.labelSmall,
            color: AppColors.accent,
            minHeight: Hit.min,
            onTap: onFind,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The close, and the small print
// ─────────────────────────────────────────────────────────────────────────────

class _CtaBand extends StatelessWidget {
  const _CtaBand({required this.wide, required this.onStart});

  final bool wide;
  final void Function(Role role) onStart;

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);
    final double gutter = TMLayout.gutter(context);

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'START HERE',
          style: AppType.micro
              .copyWith(fontSize: 10, letterSpacing: 1.8)
              .tone(AppColors.amber),
        ),
        const SizedBox(height: Space.lg),
        Text(
          'Find your tutor.',
          style: AppType.heroAt(width).tone(AppColors.onAccent),
        ),
      ],
    );

    final Widget action = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Two minutes of questions, then a ranked list with the arithmetic '
            'showing. This is an interface prototype: nothing is charged, and '
            'nothing is stored.',
            style: AppType.body.tone(AppColors.onInkQuiet),
          ),
        ),
        const SizedBox(height: Space.xl),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          children: <Widget>[
            TMButton(
              label: 'Create account',
              icon: TMIconName.arrowRight,
              onPressed: () => onStart(Role.student),
            ),
            TMButton(
              label: 'Sign in',
              variant: TMButtonVariant.onInk,
              onPressed: () => onStart(Role.student),
            ),
          ],
        ),
      ],
    );

    return TMInkContext(
      onInk: true,
      child: ColoredBox(
        color: AppColors.ink,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.maxContent,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: wide ? Space.vast : Space.huge,
              ),
              // Center + a max-width box give their child loose width. Without
              // this the stacked column shrink-wraps and floats in the middle
              // of the ink band instead of sitting on the page's left edge.
              child: SizedBox(
                width: double.infinity,
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(flex: 6, child: heading),
                          const SizedBox(width: Space.huge),
                          Expanded(flex: 4, child: action),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          heading,
                          const SizedBox(height: Space.xl),
                          action,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small print. Links first, then the one sentence this whole prototype
/// keeps having to say: everybody on it is sample data.
class _LandingFooter extends StatelessWidget {
  const _LandingFooter({
    required this.wide,
    required this.onHome,
    required this.onHow,
    required this.onTutors,
    required this.onSubjects,
    required this.onSignIn,
    required this.onStart,
  });

  final bool wide;
  final VoidCallback onHome;
  final VoidCallback onHow;
  final VoidCallback onTutors;
  final VoidCallback onSubjects;
  final VoidCallback onSignIn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final double gutter = TMLayout.gutter(context);

    final Widget brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Wordmark(
          color: AppColors.ink,
          accent: AppColors.inkMuted,
          onTap: onHome,
        ),
        const SizedBox(height: Space.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            'Matching by K-nearest neighbours over five dimensions: subjects, '
            'available time, style, format and budget. Every score can be '
            'opened and read.',
            style: AppType.bodySmall.quieter,
          ),
        ),
      ],
    );

    final Widget links = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('PRODUCT', style: AppType.micro.tone(AppColors.inkMuted)),
              const SizedBox(height: Space.sm),
              TMTextLink(
                label: 'How it works',
                style: AppType.bodySmall,
                color: AppColors.inkSecondary,
                minHeight: Hit.min,
                onTap: onHow,
              ),
              TMTextLink(
                label: 'Tutors',
                style: AppType.bodySmall,
                color: AppColors.inkSecondary,
                minHeight: Hit.min,
                onTap: onTutors,
              ),
              TMTextLink(
                label: 'Subjects',
                style: AppType.bodySmall,
                color: AppColors.inkSecondary,
                minHeight: Hit.min,
                onTap: onSubjects,
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('ACCOUNT', style: AppType.micro.tone(AppColors.inkMuted)),
              const SizedBox(height: Space.sm),
              TMTextLink(
                label: 'Sign in',
                style: AppType.bodySmall,
                color: AppColors.inkSecondary,
                minHeight: Hit.min,
                onTap: onSignIn,
              ),
              TMTextLink(
                label: 'Create account',
                style: AppType.bodySmall,
                color: AppColors.inkSecondary,
                minHeight: Hit.min,
                onTap: onStart,
              ),
            ],
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paperSunken,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.maxContent,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: gutter,
              vertical: Space.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 5, child: brand),
                      const SizedBox(width: Space.xxxl),
                      Expanded(flex: 4, child: links),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      brand,
                      const SizedBox(height: Space.xxl),
                      links,
                    ],
                  ),
                const SizedBox(height: Space.xl),
                const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
                const SizedBox(height: Space.md),
                if (wide)
                  Row(
                    children: <Widget>[
                      Text(
                        '© 2026 TutorMatch A.I.',
                        style: AppType.bodySmall.quieter,
                      ),
                      const SizedBox(width: Space.xl),
                      Flexible(
                        child: Text(
                          'Interface prototype — every tutor, student, score and '
                          'review on this site is sample data.',
                          style: AppType.bodySmall.quieter,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '© 2026 TutorMatch A.I.',
                        style: AppType.bodySmall.quieter,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Interface prototype — every tutor, student, score and '
                        'review on this site is sample data.',
                        style: AppType.bodySmall.quieter,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
