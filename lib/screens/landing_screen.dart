// ─────────────────────────────────────────────────────────────────────────────
// The landing page.
//
// The argument is spatial before it is verbal: matching is a distance problem,
// so the hero is the neighbour map itself, with the ten closest sample tutors
// already orbiting. The words sit beside it, not on top of it. The proof below
// is a real result computed by the same ranker the product uses — not a
// testimonial and not a statistic.
//
// Asymmetry is the composition: a 6/5 hero, a 4/7 mechanism, one ink band at
// the close. No gradients, no glass, no three identical feature cards.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/depth_parallax.dart';
import 'package:tutormatch/widgets/match_card.dart';
import 'package:tutormatch/widgets/neighbor_map_3d.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_motion.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final GlobalKey _mechanismKey = GlobalKey();
  final GlobalKey _proofKey = GlobalKey();

  void _to(GlobalKey key) {
    final BuildContext? target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: Motion.respect(context, Motion.page),
      curve: Motion.ease,
      alignment: 0.04,
    );
  }

  void _start(Role role, {bool signIn = false}) {
    Navigator.of(context).pushNamed(
      signIn ? Routes.login : Routes.register,
      arguments: role,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);
    final bool stack = TMLayout.isCompact(context);
    final MatchResult specimen = landingSpecimen();
    final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
    final List<NeighborNode> neighbors = <NeighborNode>[
      for (final MatchResult r in ranked.take(10))
        NeighborNode(
          id: r.candidate.id,
          name: r.candidate.name,
          subject: r.candidate.subjects.first,
          score: r.score.total,
          tint: r.candidate.photoTint,
        ),
    ];

    final Widget map = _MapPanel(
      nodes: neighbors,
      onSelect: (NeighborNode _) => _start(Role.student),
    );

    final Widget opening = _Opening(
      onStart: _start,
      onProof: () => _to(_proofKey),
      onMechanism: () => _to(_mechanismKey),
    );

    return TMPage(
      masthead: true,
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'How matching works',
          onTap: () => _to(_mechanismKey),
        ),
      ],
      navTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TMButton(
            label: 'Sign in',
            variant: TMButtonVariant.quiet,
            minHeight: Hit.min,
            onPressed: () => _start(Role.student, signIn: true),
          ),
          const SizedBox(width: Space.sm),
          TMButton(
            label: 'Get started',
            variant: TMButtonVariant.primary,
            minHeight: Hit.min,
            onPressed: () => _start(Role.student),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: stack ? Space.xl : Space.xxl),

          // ── The map and the claim, on one field. ─────────────────────────
          //
          // Three planes share one pointer origin: the measured grid furthest
          // back, the neighbour map in the middle, the words and buttons
          // nearest. The grid is oversized by a gutter so its edges never
          // appear when the furthest plane travels.
          DepthParallax(
            maxShift: 10,
            scrollShift: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: -Space.xxxl,
                  right: -Space.xxxl,
                  top: -Space.xxxl,
                  bottom: -Space.xxxl,
                  child: const ParallaxLayer(
                    depth: 1,
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _HeroFieldPainter()),
                      ),
                    ),
                  ),
                ),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        flex: 6,
                        child: ParallaxLayer(depth: 0.28, child: opening),
                      ),
                      const SizedBox(width: Space.xxl),
                      Expanded(
                        flex: 5,
                        child: ParallaxLayer(depth: 0.9, child: map),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ParallaxLayer(depth: 0.28, child: opening),
                      SizedBox(height: Space.xxl),
                      ParallaxLayer(depth: 0.8, child: map),
                    ],
                  ),
              ],
            ),
          ),

          SizedBox(height: Space.band(TMLayout.widthOf(context))),

          // ── Three steps. Not three cards. ───────────────────────────────
          const _Steps(),

          SizedBox(height: Space.band(TMLayout.widthOf(context))),

          // ── The proof: the product's own card. ──────────────────────────
          Container(
            key: _proofKey,
            child: _Proof(
              result: specimen,
              onOpen: () => _start(Role.student),
            ),
          ),

          SizedBox(height: Space.band(TMLayout.widthOf(context))),

          // ── The mechanism, in full. ─────────────────────────────────────
          Container(key: _mechanismKey, child: const _Mechanism()),

          SizedBox(height: Space.band(TMLayout.widthOf(context))),

          const _Closing(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Opening
// ─────────────────────────────────────────────────────────────────────────────

class _Opening extends StatelessWidget {
  const _Opening({
    required this.onStart,
    required this.onProof,
    required this.onMechanism,
  });

  final void Function(Role role) onStart;
  final VoidCallback onProof;
  final VoidCallback onMechanism;

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);
    final bool compact = TMLayout.isCompact(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.xs + 1,
          ),
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.rule),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                'A working interface prototype · 16 sample tutors',
                style: AppType.micro.copyWith(fontSize: 9.5)
                    .tone(AppColors.inkSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        Text(
          'The tutor who is free on Tuesday at six.',
          style: AppType.heroAt(width),
        ),
        const SizedBox(height: Space.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            'Most tutoring sites rank on subject and price, then leave you to '
            'discover that nobody is free when you are. This one ranks on the '
            'five things that decide whether lessons actually happen — and shows '
            'you the arithmetic.',
            style: AppType.bodyLarge.quiet,
          ),
        ),
        SizedBox(height: compact ? Space.xl : Space.xxl),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: <Widget>[
            TMButton(
              label: 'Find my tutor',
              icon: TMIconName.arrowRight,
              onPressed: () => onStart(Role.student),
            ),
            TMButton(
              label: 'I teach instead',
              variant: TMButtonVariant.secondary,
              onPressed: () => onStart(Role.tutor),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.xs,
          children: <Widget>[
            TMTextLink(
              label: 'See a real result',
              icon: TMIconName.arrowRight,
              style: AppType.bodySmall,
              onTap: onProof,
            ),
            TMTextLink(
              label: 'How the ranking works',
              icon: TMIconName.compass,
              style: AppType.bodySmall,
              onTap: onMechanism,
            ),
          ],
        ),
      ],
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.nodes, required this.onSelect});

  final List<NeighborNode> nodes;
  final ValueChanged<NeighborNode> onSelect;

  @override
  Widget build(BuildContext context) {
    final bool compact = TMLayout.isCompact(context);
    return TMReveal(
      delay: const Duration(milliseconds: 120),
      offset: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NeighborMap3D(
            nodes: nodes,
            height: compact ? 340 : 500,
            userLabel: 'You',
            onSelect: onSelect,
          ),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: TMIcon(
                  TMIconName.target,
                  size: 13,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Every disc is a tutor in the sample pool. Distance is the fit '
                  'across five dimensions; drag to turn the field.',
                  style: AppType.bodySmall.copyWith(fontSize: 12).quieter,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Three steps
// ─────────────────────────────────────────────────────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps();

  static const List<(String, String, String)> _steps = <(String, String, String)>[
    (
      'Answer five things',
      'Subjects, how you like to work, the hours you keep, online or in a room, '
          'and what you can spend. Two minutes, and nothing is saved until you '
          'choose to keep it.',
      'book',
    ),
    (
      'Read the ranking',
      'Every tutor gets a score out of 100, three reasons in plain language, and '
          'a week grid showing the hours you both actually have free.',
      'target',
    ),
    (
      'Ask for the hour',
      'The request carries the day you chose and what the first lesson should '
          'cover. The conversation opens the moment they accept.',
      'send',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);
    final double width = TMLayout.widthOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMSectionHeading(
          title: 'Three steps, and the guesswork is gone.',
          lede: 'No browsing a directory. No messaging five people to discover '
              'their Tuesday is full. The list you see has already been checked '
              'against the hours you keep.',
          width: 520,
          scale: TMSectionScale.large,
        ),
        SizedBox(height: wide ? Space.xxl : Space.xl),
        Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _steps.length; i++) ...<Widget>[
              if (i > 0)
                SizedBox(
                  width: wide ? Space.xxl : 0,
                  height: wide ? 0 : Space.xl,
                ),
              Expanded(
                flex: wide ? 1 : 0,
                child: _Step(
                  number: i + 1,
                  title: _steps[i].$1,
                  body: _steps[i].$2,
                  icon: switch (_steps[i].$3) {
                    'book' => TMIconName.book,
                    'target' => TMIconName.target,
                    _ => TMIconName.send,
                  },
                  width: wide ? 0 : width,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
    required this.width,
  });

  final int number;
  final String title;
  final String body;
  final TMIconName icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Column(
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
            const Spacer(),
            TMIcon(icon, size: 18, color: AppColors.inkMuted),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(title, style: AppType.titleLarge),
        const SizedBox(height: Space.sm),
        SizedBox(
          width: width > 0 ? width : null,
          child: Text(body, style: AppType.body.quiet),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Proof
// ─────────────────────────────────────────────────────────────────────────────

class _Proof extends StatelessWidget {
  const _Proof({required this.result, required this.onOpen});

  final MatchResult result;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);

    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMSectionHeading(
          title: 'This is not a screenshot. It is the product.',
          lede: 'The card below was computed from the sample profiles, by the '
              'same function that will rank your list. The score, the three '
              'reasons and the shared hours are all live.',
          width: 420,
          scale: TMSectionScale.large,
        ),
        const SizedBox(height: Space.xl),
        _ProofPoint(
          icon: TMIconName.target,
          title: 'The score is itemised',
          body: 'Open any match to see what each of the five dimensions '
              'contributed, out of 40, 25, 15, 10 and 10.',
        ),
        const SizedBox(height: Space.lg),
        _ProofPoint(
          icon: TMIconName.clock,
          title: 'The week is counted',
          body: 'Filled cells are hours you are both free. No overlap is stated '
              'plainly rather than hidden behind a lower rank.',
        ),
        const SizedBox(height: Space.lg),
        _ProofPoint(
          icon: TMIconName.sparkle,
          title: 'The reasons change with you',
          body: 'They are the three highest-weighted dimensions for this pairing, '
              'not a fixed list of compliments.',
        ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 4, child: copy),
          const SizedBox(width: Space.huge),
          Expanded(
            flex: 7,
            child: MatchResultCard(
              result: result,
              rank: 1,
              total: sampleTutors.length,
              lead: true,
              onOpen: onOpen,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        copy,
        const SizedBox(height: Space.xxl),
        MatchResultCard(
          result: result,
          rank: 1,
          total: sampleTutors.length,
          lead: true,
          onOpen: onOpen,
        ),
      ],
    );
  }
}

class _ProofPoint extends StatelessWidget {
  const _ProofPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final TMIconName icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentWash,
            borderRadius: BorderRadius.circular(Radii.sharp - 3),
          ),
          child: TMIcon(icon, size: 15, color: AppColors.accent),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppType.label.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(body, style: AppType.bodySmall.quieter),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The mechanism
// ─────────────────────────────────────────────────────────────────────────────

class _Mechanism extends StatelessWidget {
  const _Mechanism();

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);

    const Widget heading = TMSectionHeading(
      title: 'Five numbers decide this. Nothing else is compared.',
      lede: 'This is the entire mechanism, stated once so you can hold it '
          'against the ranking later. Each dimension contributes a fixed share '
          'of the hundred points, and the share is printed on every score you '
          'open.',
      width: 400,
      scale: TMSectionScale.large,
    );

    final Widget rows = Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: Column(
        children: <Widget>[
          for (final MatchDimension dimension in MatchDimension.values)
            _DimensionRow(dimension: dimension),
        ],
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Expanded(flex: 4, child: heading),
          const SizedBox(width: Space.huge),
          Expanded(flex: 7, child: rows),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        heading,
        SizedBox(height: Space.xxl),
        rows,
      ],
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({required this.dimension});
  final MatchDimension dimension;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 54,
            child: Text(
              '${dimension.max}',
              style: AppType.scoreSmall.tone(AppColors.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(dimension.label, style: AppType.sectionTitle),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      'of 100',
                      style: AppType.micro.tone(AppColors.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    dimension.explainer,
                    style: AppType.body.quiet,
                  ),
                ),
                const SizedBox(height: Space.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    dimension.widening,
                    style: AppType.bodySmall.quieter,
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

// ─────────────────────────────────────────────────────────────────────────────
// The close
// ─────────────────────────────────────────────────────────────────────────────

class _Closing extends StatelessWidget {
  const _Closing();

  @override
  Widget build(BuildContext context) {
    final bool stack = TMLayout.isNarrow(context);

    return TMInkContext(
      onInk: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: Radii.softAll,
        ),
        child: Padding(
          padding: EdgeInsets.all(stack ? Space.xl : Space.xxxl),
          child: Flex(
            direction: stack ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: stack ? 0 : 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'A score you cannot argue with is a score you will not trust.',
                      style: AppType.pageTitle.copyWith(
                        color: AppColors.onAccent,
                        fontSize: stack ? 30 : 38,
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    SizedBox(
                      width: 420,
                      child: Text(
                        'So every point is itemised. Open any match and you get '
                        'the five dimensions, what each one contributed, and the '
                        'sentence that explains it.',
                        style: AppType.body.tone(AppColors.onInkQuiet),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: stack ? 0 : Space.xxxl,
                height: stack ? Space.xl : 0,
              ),
              Expanded(
                flex: stack ? 0 : 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Five questions. Then the list.',
                      style: AppType.titleLarge.tone(AppColors.onAccent),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      'Two minutes, and nothing is saved until you decide it '
                      'should be.',
                      style: AppType.bodySmall.tone(AppColors.onInkQuiet),
                    ),
                    const SizedBox(height: Space.xl),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.sm,
                      children: <Widget>[
                        TMButton(
                          label: 'Answer the five questions',
                          icon: TMIconName.arrowRight,
                          onPressed: () => Navigator.of(context).pushNamed(
                            Routes.register,
                            arguments: Role.student,
                          ),
                        ),
                        TMButton(
                          label: 'I teach instead',
                          variant: TMButtonVariant.onInk,
                          onPressed: () => Navigator.of(context).pushNamed(
                            Routes.register,
                            arguments: Role.tutor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The furthest plane of the hero: a measured field rather than a decoration.
/// One hairline every 56 px, with a single ink tick at every fourth crossing —
/// the same logic as the week grid, drawn large enough to read as place.
class _HeroFieldPainter extends CustomPainter {
  const _HeroFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const double gap = 56;
    final Paint line = Paint()
      ..color = AppColors.rule.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final Paint tick = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;

    int column = 0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      int row = 0;
      for (double y = 0; y < size.height; y += gap) {
        if (column % 4 == 0 && row % 4 == 0) {
          canvas.drawCircle(Offset(x, y), 1.8, tick);
        }
        row++;
      }
      column++;
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_HeroFieldPainter oldDelegate) => false;
}
