// ─────────────────────────────────────────────────────────────────────────────
// Sign in.
//
// Same frame as register, so the two screens cannot drift apart. The honest
// difference: this one offers the demo account, because a reviewer who has to
// invent an email address to see the product will invent a bad one and then
// wonder whether the form works.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/auth_shell.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.initialRole, super.key});

  final Role initialRole;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late Role _role = widget.initialRole;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final String? emailError = validateEmail(_email.text);
    final String? passwordError = validatePassword(_password.text, isNew: false);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) return;

    setState(() => _busy = true);
    AppStateScope.read(context).role = _role;
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(Routes.matches);
    });
  }

  void _useDemoAccount() {
    final AppState state = AppStateScope.read(context);
    state.role = _role;
    state.profile = _role == Role.student ? demoStudentProfile : demoTutorProfile;
    state.profileAnswered = true;
    Navigator.of(context).pushReplacementNamed(Routes.matches);
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      role: _role,
      onRoleChanged: (Role r) => setState(() => _role = r),
      title: 'Sign in',
      lede: 'Pick up your list where you left it. In this prototype there is '
          'nothing to pick up yet — any valid-looking email and a password of '
          'eight characters will let you through.',
      nextSteps: const <String>[
        'Your ranked list and your filters, as you left them.',
        'Any requests you have sent, with their answers.',
        'Nothing is stored. Signing out is the same as reloading.',
      ],
      switchPrompt: 'No account yet?',
      switchLabel: 'Create one in two fields',
      onSwitch: () => Navigator.of(context).pushReplacementNamed(
        Routes.register,
        arguments: _role,
      ),
      form: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthRoleSwitch(role: _role, onChanged: (Role r) => setState(() => _role = r)),
            const SizedBox(height: Space.xl),
            TMButton(
              label: 'Continue with Google',
              variant: TMButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: Space.xl),
            const AuthDivider(label: 'or sign in with an email'),
            const SizedBox(height: Space.xl),
            TMTextField(
              label: 'Email',
              controller: _email,
              hint: 'you@school.example',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              error: _emailError,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.lg),
            TMTextField(
              label: 'Password',
              controller: _password,
              hint: 'at least 8 characters',
              obscure: true,
              textInputAction: TextInputAction.done,
              error: _passwordError,
              helper: 'Forgotten it? There is nothing to reset here — no password '
                  'is being checked against anything.',
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.xl),
            TMButton(
              label: 'Sign in',
              expand: true,
              busy: _busy,
              busyLabel: 'Finding your list…',
              icon: TMIconName.arrowRight,
              onPressed: _submit,
            ),
            const SizedBox(height: Space.xl),
            const AuthDivider(label: 'or skip the form'),
            const SizedBox(height: Space.lg),
            TMButton(
              label: _role == Role.student
                  ? 'Open the demo student account'
                  : 'Open the demo tutor account',
              variant: TMButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : _useDemoAccount,
            ),
            const SizedBox(height: Space.md),
            Text(
              _role == Role.student
                  ? 'Maya Chen, Year 12 — calculus and physics, weekday evenings, '
                      'up to \$${demoStudentProfile.budget} an hour.'
                  : 'Amara Okonkwo — calculus and statistics, online, weekday '
                      'evenings and Saturday mornings.',
              style: AppType.bodySmall.quieter,
            ),
          ],
        ),
      ),
    );
  }
}
