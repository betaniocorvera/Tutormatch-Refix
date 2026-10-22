// ─────────────────────────────────────────────────────────────────────────────
// Shared frame for register and sign in.
//
// A split page with two different jobs. The ink half is the argument: who you
// are in this exchange, what the five signals are, and what happens after this
// form. The paper half is the work: choose a side, prove you are a person, step
// through. Neither half is a centred card floating in a void.
//
// On a phone the argument cannot sit above the form in full or nobody reaches
// the fields. The title and the consequence stay; the three steps follow the
// form as a short receipt.
//
// Both screens are honest about being a prototype: nothing is created, nothing
// is stored, and anything that looks like a valid email will work.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    required this.role,
    required this.onRoleChanged,
    required this.title,
    required this.lede,
    required this.nextSteps,
    required this.form,
    required this.switchPrompt,
    required this.switchLabel,
    required this.onSwitch,
    this.formEyebrow = 'YOUR DETAILS',
    this.formTitle = 'Your details, then the questions.',
    super.key,
  });

  final Role role;
  final ValueChanged<Role> onRoleChanged;
  final String title;
  final String lede;
  final List<String> nextSteps;
  final Widget form;
  final String switchPrompt;
  final String switchLabel;
  final String formEyebrow;
  final String formTitle;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final bool split = TMLayout.isWide(context);
    final bool compact = TMLayout.isCompact(context);

    final Widget intro = _AuthIntro(
      role: role,
      title: title,
      lede: lede,
      nextSteps: nextSteps,
      compact: compact,
      showNextSteps: split,
    );

    final Widget formPanel = _AuthFormPanel(
      eyebrow: formEyebrow,
      title: formTitle,
      switchPrompt: switchPrompt,
      switchLabel: switchLabel,
      onSwitch: onSwitch,
      child: form,
    );

    return TMPage(
      maxWidth: 1180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: compact ? Space.xl : Space.xxl),
          ClipRRect(
            borderRadius: Radii.softAll,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.paperRaised,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.rule),
                ),
              ),
              child: split
                  // A Stack, not IntrinsicHeight: the two panels keep their
                  // natural heights, while the split ground behind them fills
                  // whichever side is taller. IntrinsicHeight under-measures
                  // text fields and left the login form 21 px over its box.
                  ? Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Expanded(
                                flex: 5,
                                child: ColoredBox(color: AppColors.ink),
                              ),
                              const Expanded(
                                flex: 6,
                                child: ColoredBox(color: AppColors.paperRaised),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 5, child: intro),
                            Expanded(flex: 6, child: formPanel),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        intro,
                        formPanel,
                        _NextStepsReceipt(steps: nextSteps),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The argument
// ─────────────────────────────────────────────────────────────────────────────

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({
    required this.role,
    required this.title,
    required this.lede,
    required this.nextSteps,
    required this.compact,
    required this.showNextSteps,
  });

  final Role role;
  final String title;
  final String lede;
  final List<String> nextSteps;
  final bool compact;
  final bool showNextSteps;

  @override
  Widget build(BuildContext context) {
    final double pad = compact ? Space.xl : Space.xxl + 8;
    final bool student = role == Role.student;

    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                'TUTORMATCH · BEFORE YOU BEGIN',
                style: AppType.micro.tone(AppColors.onInkFaint),
              ),
            ],
          ),
          SizedBox(height: compact ? Space.xl : Space.xxxl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              title,
              style: AppType.pageTitle.copyWith(
                fontSize: compact ? 34 : 44,
                height: 1.04,
                letterSpacing: -1.4,
                color: AppColors.onAccent,
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              lede,
              style: AppType.bodyLarge.copyWith(
                color: AppColors.onInkQuiet,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          _AudienceTag(role: role, student: student),
          if (showNextSteps) ...<Widget>[
            const SizedBox(height: Space.xxxl),
            Container(
              height: 1,
              color: AppColors.onInkFaint.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'WHAT HAPPENS NEXT',
              style: AppType.micro.tone(AppColors.onInkFaint),
            ),
            const SizedBox(height: Space.lg),
            for (int i = 0; i < nextSteps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 30,
                      child: Text(
                        '0${i + 1}',
                        style: AppType.figure.tone(AppColors.amber),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        nextSteps[i],
                        style: AppType.body.copyWith(
                          color: AppColors.onInkQuiet,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...<Widget>[
            const SizedBox(height: Space.lg),
            // The five signals fit on one line on a phone because they are the
            // reason the form is worth filling in; the full steps follow below.
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: <Widget>[
                for (final String signal in const <String>[
                  'Subject',
                  'Hours',
                  'Style',
                  'Format',
                  'Budget',
                ])
                  _InkTag(signal),
              ],
            ),
          ],
          const SizedBox(height: Space.xl),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.onInkFaint.withValues(alpha: 0.35),
              ),
              borderRadius: Radii.sharpAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: Space.sm),
                  child: TMIcon(
                    TMIconName.warning,
                    size: 14,
                    color: AppColors.onInkFaint,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Interface prototype. No account is created, no email is '
                    'sent, and nothing typed here leaves the page.',
                    style: AppType.bodySmall.copyWith(
                      color: AppColors.onInkFaint,
                      height: 1.5,
                    ),
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

class _AudienceTag extends StatelessWidget {
  const _AudienceTag({required this.role, required this.student});

  final Role role;
  final bool student;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.amber,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TMIcon(
            student ? TMIconName.graduation : TMIconName.teach,
            size: 14,
            color: AppColors.onAmber,
          ),
          const SizedBox(width: Space.sm),
          Text(
            student ? 'You will see tutors' : 'You will see students',
            style: AppType.labelSmall.copyWith(
              color: AppColors.onAmber,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InkTag extends StatelessWidget {
  const _InkTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.onInkFaint.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(label, style: AppType.micro.tone(AppColors.onInkQuiet)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The work
// ─────────────────────────────────────────────────────────────────────────────

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({
    required this.eyebrow,
    required this.title,
    required this.child,
    required this.switchPrompt,
    required this.switchLabel,
    required this.onSwitch,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final String switchPrompt;
  final String switchLabel;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final bool compact = TMLayout.isCompact(context);

    return Container(
      color: AppColors.paperRaised,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.xl : Space.xxl + 8,
        vertical: compact ? Space.xl : Space.xxl,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(eyebrow, style: AppType.micro.tone(AppColors.inkMuted)),
              const SizedBox(height: Space.xs + 2),
              Text(title, style: AppType.sectionTitle),
              const SizedBox(height: Space.lg),
              child,
              const SizedBox(height: Space.xl),
              const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(switchPrompt, style: AppType.bodySmall.quieter),
                  TMTextLink(
                    label: switchLabel,
                    onTap: onSwitch,
                    style: AppType.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// On a phone the three steps arrive after the form: the form first, then the
/// receipt. Numbered rules, not three cards.
class _NextStepsReceipt extends StatelessWidget {
  const _NextStepsReceipt({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('WHAT HAPPENS NEXT', style: AppType.micro.tone(AppColors.inkMuted)),
          const SizedBox(height: Space.md),
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Space.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: Text(
                      '0${i + 1}',
                      style: AppType.figure.tone(AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: AppType.bodySmall.tone(AppColors.inkSecondary),
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

/// The one place a control is full width: a form column. Everything else sizes
/// itself to its content.
class AuthField extends StatelessWidget {
  const AuthField({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: child);
}

/// The role switch, asked once, at the top, because it changes every screen
/// after it. Two doors, not a toggle: the consequence is written inside each.
class AuthRoleSwitch extends StatelessWidget {
  const AuthRoleSwitch({
    required this.role,
    required this.onChanged,
    this.label = 'I am signing up as',
    this.reason = 'This decides whose list you see next. It does not change '
        'what we ask you, only who gets ranked.',
    super.key,
  });

  final Role role;
  final ValueChanged<Role> onChanged;
  final String label;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return AuthField(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TMFieldLabel(label: label, reason: reason),
          const SizedBox(height: Space.md),
          // The outer split layout is intrinsic, so a stretched Row needs its
          // own finite height here; without this the doors receive infinity.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _RoleDoor(
                    selected: role == Role.student,
                    icon: TMIconName.graduation,
                    title: 'Student',
                    caption: 'Looking for a tutor',
                    onTap: () => onChanged(Role.student),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _RoleDoor(
                    selected: role == Role.tutor,
                    icon: TMIconName.teach,
                    title: 'Tutor',
                    caption: 'Taking on students',
                    onTap: () => onChanged(Role.tutor),
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

class _RoleDoor extends StatelessWidget {
  const _RoleDoor({
    required this.selected,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final bool selected;
  final TMIconName icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticLabel: title,
      semanticButton: false,
      semanticSelected: selected,
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: AnimatedContainer(
          duration: Motion.respect(context, Motion.base),
          curve: Motion.ease,
          transform: Motion.reduced(context)
              ? null
              : (Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..translateByDouble(
                    0,
                    selected ? -2 : 0,
                    selected ? 14 : -10,
                    1,
                  )),
          constraints: const BoxConstraints(minHeight: 116),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentWash : AppColors.paper,
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : s.hovered
                      ? AppColors.ruleStrong
                      : AppColors.rule,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: Radii.sharpAll,
            boxShadow: selected || s.hovered ? TMShadows.floating : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent : AppColors.paperSunken,
                      borderRadius: BorderRadius.circular(Radii.sharp - 3),
                    ),
                    child: TMIcon(
                      icon,
                      size: 18,
                      color: selected ? AppColors.onAccent : AppColors.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (selected)
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const TMIcon(
                        TMIconName.check,
                        size: 11,
                        color: AppColors.onAccent,
                        strokeWidth: 2,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                title,
                style: AppType.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.accent : AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: AppType.bodySmall.quieter,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The divider between the two ways in, with a plain label rather than a rule
/// and a floating word.
class AuthDivider extends StatelessWidget {
  const AuthDivider({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return AuthField(
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider(height: 1, color: AppColors.rule)),
          // The label measures itself; only the rules flex. Making the label a
          // flex child split the row into thirds and ellipsised a two-word
          // sentence that had room to spare.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Text(
              label,
              style: AppType.bodySmall.quieter,
              maxLines: 1,
            ),
          ),
          const Expanded(child: Divider(height: 1, color: AppColors.rule)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation
// ─────────────────────────────────────────────────────────────────────────────

/// Field-level checks, written so the message says what to do rather than what
/// went wrong. There is no server, so these are the only errors in the product
/// and they have to carry their weight.
String? validateEmail(String? raw) {
  final String value = (raw ?? '').trim();
  if (value.isEmpty) {
    return 'Enter the email address you want to use — it is the only way back into your account.';
  }
  final int at = value.indexOf('@');
  if (at < 1 || !value.substring(at).contains('.') || value.endsWith('.') || value.endsWith('@')) {
    final String hint = at < 1
        ? 'There is no @ in it yet.'
        : 'The part after the @ does not look like a domain.';
    return '$hint Check it against the address your school or your inbox uses.';
  }
  if (value.contains(' ')) {
    return 'There is a space in there. Email addresses never contain spaces.';
  }
  return null;
}

String? validatePassword(String? raw, {required bool isNew}) {
  final String value = raw ?? '';
  if (value.isEmpty) {
    return isNew
        ? 'Choose a password. Eight characters is the minimum.'
        : 'Enter your password to continue.';
  }
  if (value.length < 8) {
    final int missing = 8 - value.length;
    return isNew
        ? 'That is ${value.length} characters. Add $missing more — three unrelated '
            'words is easier to remember than one complicated one.'
        : 'That is ${value.length} characters and passwords here are at least 8. '
            'If you have forgotten it, use the reset link instead of guessing.';
  }
  return null;
}
