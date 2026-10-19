// ─────────────────────────────────────────────────────────────────────────────
// Shared frame for register and sign in.
//
// Asymmetric on purpose: the left column says what will happen and the right
// column is the form. A centred login card floating in a void tells a person
// nothing about what they are signing up to, and this product asks for unusual
// things — weekly hours, budget, teaching style — so the page has to say so
// before the fields do.
//
// Both screens are honest about being a prototype: nothing is created, nothing
// is stored, and anything that looks like a valid email will work.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
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
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);
    final String audience = role == Role.student
        ? 'You will see tutors.'
        : 'You will see students.';

    final Widget aside = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 400, child: Text(title, style: AppType.pageTitle)),
        const SizedBox(height: Space.lg),
        SizedBox(width: 400, child: Text(lede, style: AppType.bodyLarge.quiet)),
        const SizedBox(height: Space.xl),
        // States the consequence of the choice immediately rather than after.
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.xs + 1,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentWash,
                border: Border.all(color: AppColors.accent),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                audience,
                style: AppType.micro.tone(AppColors.accent),
              ),
            ),
          ],
        ),
        SizedBox(height: Space.xxl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        const TMMicroLabelText('What happens next'),
        const SizedBox(height: Space.lg),
        for (int i = 0; i < nextSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}',
                    style: AppType.figure.tone(AppColors.accent),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    width: 340,
                    child: Text(
                      nextSteps[i],
                      style: AppType.body.tone(AppColors.inkSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: Space.xl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        SizedBox(
          width: 380,
          child: Text(
            'This is an interface prototype. No account is created, no email is '
            'sent, and nothing typed into this form leaves the page.',
            style: AppType.bodySmall.quieter,
          ),
        ),
      ],
    );

    return TMPage(
      maxWidth: 1120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: TMLayout.isCompact(context) ? Space.xl : Space.xxl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: aside),
                const SizedBox(width: Space.huge),
                Expanded(flex: 6, child: form),
              ],
            )
          else ...<Widget>[
            aside,
            SizedBox(height: Space.xxl),
            form,
          ],
          const SizedBox(height: Space.huge),
          Row(
            children: <Widget>[
              Flexible(child: Text(switchPrompt, style: AppType.bodySmall.quieter)),
              const SizedBox(width: Space.sm),
              TMTextLink(label: switchLabel, onTap: onSwitch, style: AppType.bodySmall),
            ],
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
/// after it.
class AuthRoleSwitch extends StatelessWidget {
  const AuthRoleSwitch({required this.role, required this.onChanged, super.key});

  final Role role;
  final ValueChanged<Role> onChanged;

  @override
  Widget build(BuildContext context) {
    return AuthField(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const TMFieldLabel(
            label: 'I am signing up as',
            reason: 'This decides whose list you see next. It does not change '
                'what we ask you, only who gets ranked.',
          ),
          const SizedBox(height: Space.md),
          TMSegmented<Role>(
            options: const <Role>[Role.student, Role.tutor],
            selected: role,
            onSelect: onChanged,
            labelOf: (Role r) => r == Role.student ? 'A student' : 'A tutor',
          ),
        ],
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
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Text(
                label,
                style: AppType.bodySmall.quieter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
