// ─────────────────────────────────────────────────────────────────────────────
// Onboarding.
//
// One form, five questions, and every question is a value the recommender
// actually consumes. There is no name field, no photo, no bio, no phone number:
// if a question does not move the ranking, it is not asked. The right-hand rail
// says so, and names the dimension each question feeds.
//
// Built as a printed registration form rather than a wizard: a contents list on
// the left that you can go back through, one question dominant in the middle,
// and a single Continue. Answers live in this widget until the last step —
// nothing is saved before then, and the copy says so.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.role, super.key});

  final Role role;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  final Set<String> _subjects = <String>{};
  String? _style;
  List<bool> _week = List<bool>.filled(Week.cells, false);
  SessionMode _mode = SessionMode.both;
  int _rate = 45;
  String? _goal;
  bool _busy = false;

  bool get _isStudent => widget.role == Role.student;

  List<String> get _stepTitles => _isStudent
      ? const <String>['Subjects', 'How you learn', 'Your week', 'Where and how much', 'What you want out of it']
      : const <String>['Subjects', 'How you teach', 'Your week', 'Where and how much', 'Who you want to teach'];

  /// Which ranking dimension each question feeds. Printed in the rail so a
  /// person can see the form is not gathering anything decorative.
  List<String> get _stepDimensions => const <String>[
        'Subjects · 40 of 100',
        'Style · 15 of 100',
        'Available time · 25 of 100',
        'Format and budget · 20 of 100',
        'Context, not scored',
      ];

  /// What is missing at this step, in the words of the control rather than the
  /// field name. Shown next to a disabled Continue, so the button is never
  /// simply dead.
  String? get _blocker => switch (_step) {
        0 when _subjects.isEmpty => 'Choose at least one subject. Two or three gives the ranking more to work with.',
        1 when _style == null => 'Pick the description closest to how you actually work.',
        2 when !_week.contains(true) => 'Tick the blocks you could genuinely keep free. One is enough.',
        4 when _goal == null => 'Choose what you are aiming at, or the closest thing to it.',
        _ => null,
      };

  bool get _canContinue => _blocker == null;

  void _next() {
    if (!_canContinue) return;
    if (_step < 4) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    final AppState state = AppStateScope.read(context);
    state.role = widget.role;
    state.profile = Profile(
      role: widget.role,
      name: state.profile.name,
      subjects: _subjects.toList(),
      style: _style!,
      mode: _mode,
      budget: _rate,
      availability: _week,
      goal: _goal!,
    );
    // This is the one moment the "based on your profile" tag is honest: the
    // ranking below was produced from answers given seconds ago.
    state.profileAnswered = true;
    state.clearFilters();
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(Routes.matches);
    });
  }

  void _useDemo() {
    final AppState state = AppStateScope.read(context);
    state.role = widget.role;
    state.profile = _isStudent ? demoStudentProfile : demoTutorProfile;
    state.profileAnswered = true;
    state.clearFilters();
    Navigator.of(context).pushReplacementNamed(Routes.matches);
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);

    final Widget rail = _Rail(
      titles: _stepTitles,
      dimensions: _stepDimensions,
      current: _step,
      onJump: (int i) => setState(() => _step = i),
      onDemo: _useDemo,
      role: widget.role,
    );

    final Widget question = _Question(
      step: _step,
      title: _stepTitles[_step],
      dimension: _stepDimensions[_step],
      blocker: _blocker,
      busy: _busy,
      last: _step == 4,
      role: widget.role,
      onBack: _step == 0 ? null : () => setState(() => _step--),
      onNext: _canContinue ? _next : null,
      child: _control(),
    );

    return TMPage(
      maxWidth: 1120,
      footer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: TMLayout.isCompact(context) ? Space.xl : Space.xxl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: TMLayout.railWidth, child: rail),
                const SizedBox(width: Space.huge),
                Expanded(child: question),
              ],
            )
          else ...<Widget>[
            _CompactProgress(
              step: _step,
              titles: _stepTitles,
              dimensions: _stepDimensions,
            ),
            SizedBox(height: Space.xl),
            question,
            SizedBox(height: Space.xxl),
            rail,
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  Widget _control() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TMTagPicker(
              options: OnboardingOptions.subjects,
              selected: _subjects,
              max: 4,
              onToggle: (String s) => setState(() {
                if (_subjects.contains(s)) {
                  _subjects.remove(s);
                } else if (_subjects.length < 4) {
                  _subjects.add(s);
                }
              }),
            ),
            const SizedBox(height: Space.lg),
            Text(
              _subjects.length >= 4
                  ? 'Four is the most the ranking can use without the subject score '
                      'going flat. Remove one before adding another.'
                  : 'Up to four. ${4 - _subjects.length} left.',
              style: AppType.bodySmall.quieter,
            ),
          ],
        );

      case 1:
        return TMChoiceList<String>(
          options: _isStudent
              ? OnboardingOptions.studentStyles
              : OnboardingOptions.tutorStyles,
          selected: _style,
          onSelect: (String s) => setState(() => _style = s),
          labelOf: (String s) => s,
        );

      case 2:
        return AvailabilityEditor(
          value: _week,
          onChanged: (List<bool> next) => setState(() => _week = next),
        );

      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const TMFieldLabel(
              label: 'Where lessons happen',
              reason: 'Online widens the list more than any other single answer on '
                  'this form. It is the one compromise worth considering early.',
            ),
            const SizedBox(height: Space.md),
            TMSegmented<SessionMode>(
              options: const <SessionMode>[
                SessionMode.online,
                SessionMode.inPerson,
                SessionMode.both,
              ],
              selected: _mode,
              onSelect: (SessionMode m) => setState(() => _mode = m),
              labelOf: (SessionMode m) => m.label,
            ),
            const SizedBox(height: Space.xxl),
            TMFieldLabel(
              label: _isStudent ? 'What you can spend an hour' : 'What you charge an hour',
              reason: _isStudent
                  ? 'A ceiling, not a preference. A five-dollar gap is usually one '
                      'session a month rather than a decision about quality.'
                  : 'Charged per hour of teaching. The ranking compares this against '
                      'what the other side can spend.',
            ),
            const SizedBox(height: Space.md),
            TMBudgetScale(
              value: _rate,
              onChanged: (int v) => setState(() => _rate = v),
            ),
          ],
        );

      default:
        return TMChoiceList<String>(
          options: _isStudent ? OnboardingOptions.studentGoals : OnboardingOptions.tutorGoals,
          selected: _goal,
          onSelect: (String s) => setState(() => _goal = s),
          labelOf: (String s) => s,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The contents rail
// ─────────────────────────────────────────────────────────────────────────────

class _Rail extends StatelessWidget {
  const _Rail({
    required this.titles,
    required this.dimensions,
    required this.current,
    required this.onJump,
    required this.onDemo,
    required this.role,
  });

  final List<String> titles;
  final List<String> dimensions;
  final int current;
  final ValueChanged<int> onJump;
  final VoidCallback onDemo;
  final Role role;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Registration form'),
        const SizedBox(height: Space.lg),
        for (int i = 0; i < titles.length; i++)
          _RailItem(
            index: i,
            title: titles[i],
            dimension: dimensions[i],
            current: i == current,
            reached: i <= current,
            onTap: i <= current ? () => onJump(i) : null,
          ),
        const SizedBox(height: Space.xl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        SizedBox(
          width: TMLayout.railWidth - 20,
          child: Text(
            'Nothing on this form is saved. Reload the page and every answer is '
            'gone — there is no account holding them.',
            style: AppType.bodySmall.quieter,
          ),
        ),
        const SizedBox(height: Space.lg),
        TMTextLink(
          label: 'Or skip this and use the demo profile',
          onTap: onDemo,
          style: AppType.bodySmall,
        ),
        const SizedBox(height: Space.xs),
        SizedBox(
          width: TMLayout.railWidth - 20,
          child: Text(
            role == Role.student
                ? 'Maya Chen, Year 12: calculus, physics and algebra, weekday '
                    'evenings, online or in person, up to \$50 an hour.'
                : 'Amara Okonkwo: calculus and statistics, online, weekday evenings '
                    'and Saturday mornings, \$46 an hour.',
            style: AppType.bodySmall.quieter,
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.index,
    required this.title,
    required this.dimension,
    required this.current,
    required this.reached,
    required this.onTap,
  });

  final int index;
  final String title;
  final String dimension;
  final bool current;
  final bool reached;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      enabled: onTap != null,
      semanticButton: false,
      semanticSelected: current,
      semanticLabel: 'Step ${index + 1}, $title',
      builder: (BuildContext context, TMState s) {
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: Container(
            constraints: const BoxConstraints(minHeight: Hit.min),
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 26,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: reached && !current
                        ? const TMIcon(TMIconName.check, size: 14, color: AppColors.accepted)
                        : Text(
                            '${index + 1}',
                            style: AppType.figure.tone(
                              current ? AppColors.accent : AppColors.inkMuted,
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppType.label.tone(
                          current
                              ? AppColors.ink
                              : reached
                                  ? AppColors.inkSecondary
                                  : AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(dimension, style: AppType.micro.copyWith(fontSize: 10).tone(AppColors.inkMuted)),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// The question
// ─────────────────────────────────────────────────────────────────────────────

class _Question extends StatelessWidget {
  const _Question({
    required this.step,
    required this.title,
    required this.dimension,
    required this.blocker,
    required this.busy,
    required this.last,
    required this.role,
    required this.onBack,
    required this.onNext,
    required this.child,
  });

  final int step;
  final String title;
  final String dimension;
  final String? blocker;
  final bool busy;
  final bool last;
  final Role role;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The step number is real information here: it is a form with five
        // parts and you are on one of them.
        Text(
          'Question ${step + 1} of 5'.toUpperCase(),
          style: AppType.micro.tone(AppColors.accent),
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(_headline(step, role), style: AppType.pageTitle),
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(_sub(step, role), style: AppType.bodyLarge.quiet),
        ),
        SizedBox(height: Space.xxl),
        child,
        SizedBox(height: Space.xxl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TMButton(
              label: last ? 'See my matches' : 'Continue',
              icon: TMIconName.arrowRight,
              busy: busy,
              busyLabel: 'Ranking everyone against your answers…',
              onPressed: onNext,
            ),
            if (onBack != null)
              TMButton(
                label: 'Back',
                variant: TMButtonVariant.quiet,
                icon: TMIconName.arrowLeft,
                iconLeading: true,
                onPressed: busy ? null : onBack,
              ),
            if (blocker != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(blocker!, style: AppType.bodySmall.tone(AppColors.alert)),
              ),
          ],
        ),
      ],
    );
  }

  static String _headline(int step, Role role) => switch (step) {
        0 => role == Role.student ? 'What do you need help with?' : 'What do you teach?',
        1 => role == Role.student ? 'How do you actually learn?' : 'How do you actually teach?',
        2 => 'Which hours could you keep free?',
        3 => role == Role.student
            ? 'Where, and what can you spend?'
            : 'Where, and what do you charge?',
        _ => role == Role.student ? 'What are you aiming at?' : 'Who do you want to teach?',
      };

  static String _sub(int step, Role role) => switch (step) {
        0 => 'Pick up to four. This carries the most weight of anything on this '
            'form — 40 of the 100 points.',
        1 => 'Pick the closest description. It is worth 15 points, and it is the '
            'one dimension where a mismatch is felt in every session.',
        2 => 'Tick the blocks you could genuinely keep free in a normal week, not '
            'the ones you would like to. This is worth 25 points and it empties '
            'more lists than any other answer.',
        3 => role == Role.student
            ? 'Format and budget together are worth 20 points: 10 each. Budget is a '
                'ceiling rather than a preference, which is why it is scored gently.'
            : 'Format and budget together are worth 20 points: 10 each. Your rate is '
                'compared against what each student can spend, and a small gap is '
                'stated in their reasons rather than hidden.',
        _ => 'This does not change the ranking. It is here so the reasons you read '
            'later are written against what you are actually trying to do.',
      };
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({
    required this.step,
    required this.titles,
    required this.dimensions,
  });

  final int step;
  final List<String> titles;
  final List<String> dimensions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < titles.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == titles.length - 1 ? 0 : 4),
                  child: AnimatedContainer(
                    duration: Motion.base,
                    curve: Motion.ease,
                    height: 3,
                    color: i <= step ? AppColors.accent : AppColors.rule,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Question ${step + 1} of 5 · ${dimensions[step]}'.toUpperCase(),
          style: AppType.micro.tone(AppColors.inkMuted),
        ),
      ],
    );
  }
}
