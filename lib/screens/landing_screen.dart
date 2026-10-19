// ─────────────────────────────────────────────────────────────────────────────
// The landing page.
//
// Persuade surface. The dominant element is not a headline and not a hero
// image: it is a real match result, rendered by the same widget the product
// uses, scored by the same function, with its reasons and its week grid
// showing. A visitor should be able to decide whether they believe this thing
// before they have clicked anything — so the proof is above the fold on a
// laptop, and the explanation of the mechanism comes second.
//
// The page is asymmetric on purpose: a 7/5 hero, a 4/7 mechanism, and one inset
// ink band near the end to give the scroll a floor. No gradient, no glass, no
// three identical icon columns, no "welcome to the future".
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/match_card.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final GlobalKey _mechanismKey = GlobalKey();

  void _toMechanism() {
    final BuildContext? target = _mechanismKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: Motion.slow,
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

    return TMPage(
      masthead: true,
      navItems: <TMNavItem>[
        TMNavItem(label: 'How matching works', onTap: _toMechanism),
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
            variant: TMButtonVariant.secondary,
            minHeight: Hit.min,
            onPressed: () => _start(Role.student),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: stack ? Space.xxxl : Space.huge),

          // ── The opening. ─────────────────────────────────────────────────
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 7, child: _Opening(onStart: _start)),
                const SizedBox(width: Space.huge),
                Expanded(
                  flex: 5,
                  child: _Specimen(result: specimen, onOpen: () => _start(Role.student)),
                ),
              ],
            )
          else ...<Widget>[
            _Opening(onStart: _start),
            SizedBox(height: Space.xxxl),
            _Specimen(result: specimen, onOpen: () => _start(Role.student)),
          ],

          SizedBox(height: Space.band(TMLayout.widthOf(context))),

          // ── The mechanism, in words a person would use. ──────────────────
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
  const _Opening({required this.onStart});
  final void Function(Role role) onStart;

  @override
  Widget build(BuildContext context) {
    final double width = TMLayout.widthOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // No eyebrow above it. The heading carries its own weight.
        SizedBox(
          width: 640,
          child: Text('The tutor who is free on Tuesday at six.', style: AppType.heroAt(width)),
        ),
        const SizedBox(height: Space.xl),
        SizedBox(
          width: 520,
          child: Text(
            'Most tutoring sites rank on subject and price, then leave you to '
            'discover that nobody is free when you are. This one ranks on the '
            'five things that decide whether lessons actually happen, and shows '
            'you the working.',
            style: AppType.bodyLarge.quiet,
          ),
        ),
        SizedBox(height: Space.xxl),
        _RoleEntry(
          primary: true,
          title: 'I need a tutor',
          body: 'Answer five questions, get a ranked list of tutors with a score, '
              'three reasons each, and the hours you both have free.',
          actionLabel: 'Start as a student',
          onTap: () => onStart(Role.student),
        ),
        const SizedBox(height: Space.md),
        _RoleEntry(
          primary: false,
          title: 'I teach',
          body: 'Same five questions, asked the other way round. You will see '
              'students ranked by how well they fit how you actually work.',
          actionLabel: 'Start as a tutor',
          onTap: () => onStart(Role.tutor),
        ),
      ],
    );
  }
}

/// Two ruled entries rather than two identical cards. The student path is
/// heavier because a student is who this product is built for first.
class _RoleEntry extends StatelessWidget {
  const _RoleEntry({
    required this.primary,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  final bool primary;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: primary ? 2 : 1,
          child: ColoredBox(color: primary ? AppColors.ink : AppColors.rule),
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          width: 460,
          child: Text(title, style: AppType.titleLarge),
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          width: 460,
          child: Text(body, style: AppType.bodySmall.quieter),
        ),
        const SizedBox(height: Space.lg),
        TMButton(
          label: actionLabel,
          variant: primary ? TMButtonVariant.primary : TMButtonVariant.secondary,
          icon: TMIconName.arrowRight,
          onPressed: onTap,
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The specimen
// ─────────────────────────────────────────────────────────────────────────────

class _Specimen extends StatelessWidget {
  const _Specimen({required this.result, required this.onOpen});
  final MatchResult result;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MatchResultCard(
          result: result,
          rank: 1,
          total: sampleTutors.length,
          lead: true,
          onOpen: onOpen,
        ),
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1, right: Space.md),
              child: TMMicroLabelText('Fig. 1'),
            ),
            Flexible(
              child: SizedBox(
                width: 400,
                child: Text(
                  'The top-ranked tutor for a Year 12 student who needs calculus, '
                  'has weekday evenings free, and can spend up to \$${demoStudentProfile.budget} '
                  'an hour. The score, the reasons and the week grid are computed '
                  'from the profiles in this prototype — they are not a picture.',
                  style: AppType.bodySmall.quieter,
                ),
              ),
            ),
          ],
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

    final Widget rows = Column(
      children: <Widget>[
        for (int i = 0; i < MatchDimension.values.length; i++)
          _DimensionRow(dimension: MatchDimension.values[i], first: i == 0),
      ],
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
  const _DimensionRow({required this.dimension, required this.first});
  final MatchDimension dimension;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!first) const SizedBox(height: Space.xl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 46,
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
                      Text('of 100', style: AppType.micro.tone(AppColors.inkMuted)),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    width: 520,
                    child: Text(dimension.explainer, style: AppType.body.quiet),
                  ),
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    width: 520,
                    child: Text(dimension.widening, style: AppType.bodySmall.quieter),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
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
          borderRadius: Radii.sharpAll,
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
                    SizedBox(
                      width: 420,
                      child: Text(
                        'A score you cannot argue with is a score you will not trust.',
                        style: AppType.titleLarge.tone(AppColors.onAccent),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    SizedBox(
                      width: 420,
                      child: Text(
                        'So every point is itemised. Open any match and you get '
                        'the five dimensions, what each one contributed, and the '
                        'sentence that explains it. When a tutor is wrong for you, '
                        'the reason is written down rather than hidden behind a '
                        'lower rank.',
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
                      'Five questions, then a ranked list',
                      style: AppType.sectionTitle.tone(AppColors.onAccent),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      'Subjects, style, the hours you actually have, online or in '
                      'person, and what you can spend. Two minutes, and nothing '
                      'is saved until you decide it should be.',
                      style: AppType.bodySmall.tone(AppColors.onInkQuiet),
                    ),
                    const SizedBox(height: Space.xl),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.sm,
                      children: <Widget>[
                        TMButton(
                          label: 'Answer the five questions',
                          variant: TMButtonVariant.primary,
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
