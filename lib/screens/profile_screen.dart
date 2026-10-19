// ─────────────────────────────────────────────────────────────────────────────
// The profile.
//
// This is not a settings page and it is not a resume. It is the list of answers
// the ranking actually reads, laid out in the order they weigh, each one
// editable where it is stated. A person who wonders "why am I seeing this
// tutor?" should be able to answer it from this screen without reading any help
// text — the five blocks below are the whole of the recommender's input.
//
// The sixth block, the goal, is deliberately outside the numbered list and
// labelled as not compared, because lying about what the algorithm uses is the
// one thing a matching product cannot afford to do.
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
import 'package:tutormatch/widgets/tm_status.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: AppStateScope.read(context).profile.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Profile p = state.profile;
    final bool wide = TMLayout.isWide(context);

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'Matches',
          onTap: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        TMNavItem(
          label: 'Requests',
          onTap: () => Navigator.of(context).pushNamed(Routes.requests),
        ),
        TMNavItem(label: 'Profile', selected: true),
      ],
      navTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                '${p.name} · ${p.role == Role.student ? 'Student' : 'Tutor'}',
                style: AppType.bodySmall.quieter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          TMButton(
            label: 'Sign out',
            variant: TMButtonVariant.quiet,
            minHeight: Hit.min,
            onPressed: () =>
                Navigator.of(context).popUntil((Route<void> r) => r.isFirst),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: Space.xxl),
          Text('Your profile', style: AppType.pageTitle),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'Five answers decide who appears in your list: subjects, the hours '
              'you keep free, how you like to work, whether you meet online or in '
              'person, and what you can pay. They are below in the order they '
              'count. Change one and the ranking changes with it — nothing is '
              'sent anywhere until you ask for a lesson.',
              style: AppType.bodyLarge.quiet,
            ),
          ),
          const SizedBox(height: Space.xxl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _answers(context, state)),
                const SizedBox(width: Space.xxl),
                SizedBox(
                  width: TMLayout.asideWidth,
                  child: _aside(context, state),
                ),
              ],
            )
          else ...<Widget>[
            _answers(context, state),
            SizedBox(height: Space.band(TMLayout.widthOf(context))),
            _aside(context, state),
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  // ── The five answers, in weight order ──────────────────────────────────────

  Widget _answers(BuildContext context, AppState state) {
    final Profile p = state.profile;
    final bool student = p.role == Role.student;
    final List<String> styles =
        student ? OnboardingOptions.studentStyles : OnboardingOptions.tutorStyles;
    final List<String> goals =
        student ? OnboardingOptions.studentGoals : OnboardingOptions.tutorGoals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('What the ranking uses'),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),

        const SizedBox(height: Space.xl),
        _Answer(
          number: 1,
          title: MatchDimension.subjects.label,
          note: '${MatchDimension.subjects.max} of 100 points. '
              '${MatchDimension.subjects.explainer}',
          child: TMTagPicker(
            options: OnboardingOptions.subjects,
            selected: p.subjects.toSet(),
            max: 4,
            maxReachedNote: 'Four is the limit here. A shorter list ranks you '
                'better than a long one: the recommender reads every subject you '
                'add as something you actually want to be taught.',
            onToggle: (String s) {
              final Set<String> next = <String>{...p.subjects};
              if (!next.remove(s)) next.add(s);
              state.profile = p.copyWith(subjects: next.toList());
            },
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 2,
          title: MatchDimension.time.label,
          note: '${MatchDimension.time.max} of 100 points, worked out cell by '
              'cell against the other person\'s week — so this is the answer '
              'that moves the list most when you change it.',
          child: AvailabilityEditor(
            value: p.availability,
            onChanged: (List<bool> next) =>
                state.profile = p.copyWith(availability: next),
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 3,
          title: MatchDimension.style.label,
          note: '${MatchDimension.style.max} of 100 points. '
              '${MatchDimension.style.explainer}',
          child: _Disclosure(
            summary: p.style,
            openLabel: 'Pick a different answer',
            closeLabel: 'Keep it as it is',
            child: TMChoiceList<String>(
              options: styles,
              selected: p.style,
              onSelect: (String s) => state.profile = p.copyWith(style: s),
              labelOf: (String s) => s,
            ),
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 4,
          title: MatchDimension.format.label,
          note: '${MatchDimension.format.max} of 100 points. '
              '${MatchDimension.format.explainer}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMSegmented<SessionMode>(
                options: const <SessionMode>[
                  SessionMode.online,
                  SessionMode.inPerson,
                  SessionMode.both,
                ],
                selected: p.mode,
                onSelect: (SessionMode m) => state.profile = p.copyWith(mode: m),
                labelOf: (SessionMode m) => m.label,
              ),
              const SizedBox(height: Space.sm),
              Text(
                p.mode == SessionMode.both
                    ? 'Both sides of the list are open to you. Every tutor who '
                        'teaches online counts, and so does the one who only '
                        'teaches in a room.'
                    : 'People who teach ${p.mode.counterLabel} still rank, they '
                        'just lose the ${MatchDimension.format.max} points this '
                        'dimension is worth — which is why they sort lower '
                        'instead of disappearing.',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 5,
          title: MatchDimension.budget.label,
          note: '${MatchDimension.budget.max} of 100 points. '
              '${MatchDimension.budget.explainer}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMBudgetScale(
                value: p.budget,
                onChanged: (int v) => state.profile = p.copyWith(budget: v),
              ),
              const SizedBox(height: Space.sm),
              Text(
                student
                    ? 'A ceiling, not a target. ${p.budget >= 80 ? 'Set to any price, so cost stops counting.' : 'Anyone above \$${p.budget} an hour still appears — the reason line says by how much.'}'
                    : 'Your going rate. Students whose ceiling is below it still '
                        'appear, with the gap stated as one of their reasons.',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: null,
          title: 'What you want out of it',
          note: 'Not one of the five. Nothing above changes because of this — it '
              'is here so that whoever reads your request knows what you are '
              'aiming at before they answer it.',
          child: _Disclosure(
            summary: p.goal,
            openLabel: 'Pick a different answer',
            closeLabel: 'Keep it as it is',
            child: TMChoiceList<String>(
              options: goals,
              selected: p.goal,
              onSelect: (String g) => state.profile = p.copyWith(goal: g),
              labelOf: (String g) => g,
            ),
          ),
        ),
      ],
    );
  }

  // ── Account and the way back to the list ───────────────────────────────────

  Widget _aside(BuildContext context, AppState state) {
    final Profile p = state.profile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Your account'),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        TMTextField(
          label: 'Name',
          controller: _name,
          reason: 'Shown on the requests you send, and on the profile a tutor '
              'opens. It is not compared against anybody.',
          textInputAction: TextInputAction.done,
          onChanged: (String v) {
            // An empty name is never written: the person is mid-edit, and the
            // rest of the product has already put their old name in a nav bar.
            if (v.trim().isEmpty) return;
            state.profile = p.copyWith(name: v);
          },
        ),
        const SizedBox(height: Space.xl),
        const TMMicroLabelText('I am here as'),
        const SizedBox(height: Space.md),
        TMSegmented<Role>(
          options: const <Role>[Role.student, Role.tutor],
          selected: p.role,
          onSelect: (Role r) => _switchRole(state, r),
          labelOf: (Role r) =>
              r == Role.student ? 'Looking for a tutor' : 'Offering tutoring',
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Switching swaps whose list you see. Style and goal are worded per '
          'side, so an answer that no longer exists on this side resets to the '
          'first option.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xxl),

        TMButton(
          label: 'Rank again with these answers',
          icon: TMIconName.arrowRight,
          expand: true,
          onPressed: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'The ranking uses your answers the moment you change them. This takes '
          'you to the result — ${state.pool.length} '
          '${p.role == Role.student ? 'tutors' : 'students'} in the pool.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xxl),

        const TMInlineNote(
          tone: StatusTone.neutral,
          title: 'None of this is saved',
          body: 'TutorMatch is an interface prototype with no accounts behind '
              'it. The answers above live in memory for as long as this tab is '
              'open, and reloading puts you back to the sample profile. Nothing '
              'is sent to a server, because there is no server.',
        ),
      ],
    );
  }

  /// Flips which side of the marketplace you are standing on. The role decides
  /// whose list you see, so it lives with the answers rather than in the
  /// navigation — and the two questions that are worded per side are reset only
  /// when their wording no longer exists.
  void _switchRole(AppState state, Role role) {
    if (role == state.profile.role) return;
    final List<String> styles = role == Role.student
        ? OnboardingOptions.studentStyles
        : OnboardingOptions.tutorStyles;
    final List<String> goals = role == Role.student
        ? OnboardingOptions.studentGoals
        : OnboardingOptions.tutorGoals;
    final Profile p = state.profile;
    state.role = role;
    state.profile = p.copyWith(
      role: role,
      style: styles.contains(p.style) ? null : styles.first,
      goal: goals.contains(p.goal) ? null : goals.first,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One numbered answer
// ─────────────────────────────────────────────────────────────────────────────

class _Answer extends StatelessWidget {
  const _Answer({
    required this.number,
    required this.title,
    required this.note,
    required this.child,
  });

  /// The position in the ranking's order of weight. Null for the answer that is
  /// not compared, which is marked with a rule instead of a figure.
  final int? number;
  final String title;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On a phone the number moves into the label rather than eating a gutter
    // out of the week grid, where every pixel is a 44 px tap target.
    final bool compact = TMLayout.isCompact(context);
    final String label = number == null
        ? title
        : compact
            ? '$number. $title'
            : title;

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        TMMicroLabelText(
          label,
          color: number == null ? AppColors.inkMuted : AppColors.inkSecondary,
        ),
        const SizedBox(height: Space.lg),
        child,
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(note, style: AppType.bodySmall.quieter),
        ),
      ],
    );

    if (compact || number == null) return body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: Space.lg - 2),
            child: Text(
              '$number',
              style: AppType.figure.tone(AppColors.inkMuted),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The disclosure
// ─────────────────────────────────────────────────────────────────────────────

/// The current answer, quoted, with the full choice list behind one link.
///
/// Style and goal are answered in whole sentences, and five sentences take a
/// screenful. Keeping them closed means the recap of the five answers stays the
/// dominant thing on this page — but the sentences are still the real control,
/// one tap away, not a summary that hides what was actually chosen.
class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.summary,
    required this.openLabel,
    required this.closeLabel,
    required this.child,
  });

  final String summary;
  final String openLabel;
  final String closeLabel;
  final Widget child;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text('“${widget.summary}”', style: AppType.quote),
        ),
        const SizedBox(height: Space.sm),
        _DisclosureLink(
          label: _open ? widget.closeLabel : widget.openLabel,
          open: _open,
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.lg),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Local rather than shared: this is the only link in the product whose mark
/// turns, because it is the only one where the mark's angle *is* the state.
class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticLabel: label,
      builder: (BuildContext context, TMState s) {
        final Color ink = s.hovered || s.focused ? AppColors.accent : AppColors.ink;
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
                    style: AppType.bodySmall.tone(ink).copyWith(
                          decoration: s.hovered || s.focused
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: ink,
                          decorationThickness: 1.2,
                        ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                TMRotatingIcon(
                  TMIconName.chevronDown,
                  turns: open ? 0.5 : 0,
                  size: 15,
                  color: ink,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
