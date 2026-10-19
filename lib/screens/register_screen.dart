// ─────────────────────────────────────────────────────────────────────────────
// Register.
//
// Three fields, because three is what the rest of the product needs. Signing up
// with Google and signing up with an email are presented as equal alternatives
// rather than one primary and one afterthought, and both do the same thing:
// move to onboarding. There is no account, because there is no server.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/auth_shell.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.initialRole, super.key});

  final Role initialRole;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late Role _role = widget.initialRole;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final String? emailError = validateEmail(_email.text);
    final String? passwordError = validatePassword(_password.text, isNew: true);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) return;

    setState(() => _busy = true);
    _complete();
  }

  void _complete() {
    final AppState state = AppStateScope.read(context);
    state.role = _role;
    final String trimmed = _name.text.trim();
    if (trimmed.isNotEmpty) {
      state.profile = state.profile.copyWith(name: trimmed);
    }
    state.profileAnswered = false;
    // A real sign-up is a round trip. Held for a beat so the busy state is a
    // state and not a flash, and so the label has time to be read.
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        Routes.onboarding,
        arguments: _role,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      role: _role,
      onRoleChanged: (Role r) => setState(() => _role = r),
      title: 'Create your account',
      lede: 'Two things, then five questions. Nothing you type here is stored, '
          'sent or checked against anything.',
      nextSteps: const <String>[
        'Five questions about subjects, how you like to work, and the hours you actually keep free.',
        'A ranked list, with the score, three reasons, and the hours you both have open.',
        'Nothing is saved. Reload the page and you are back at the start.',
      ],
      switchPrompt: 'Already have an account?',
      switchLabel: 'Sign in instead',
      onSwitch: () => Navigator.of(context).pushReplacementNamed(
        Routes.login,
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
              onPressed: _busy ? null : _complete,
            ),
            const SizedBox(height: Space.xl),
            const AuthDivider(label: 'or use an email address'),
            const SizedBox(height: Space.xl),
            TMTextField(
              label: 'Your name',
              reason: 'Shown on your profile. Only tutors you contact can see it.',
              controller: _name,
              hint: _role == Role.student ? 'Maya Chen' : 'Amara Okonkwo',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Space.lg),
            TMTextField(
              label: 'Email',
              controller: _email,
              hint: 'you@school.example',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              error: _emailError,
              helper: 'Where a tutor would reply. Never shown on your profile.',
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
              helper: 'Eight characters or more. This is not sent anywhere.',
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.xl),
            TMButton(
              label: 'Create account and answer five questions',
              expand: true,
              busy: _busy,
              busyLabel: 'Creating your account…',
              icon: TMIconName.arrowRight,
              onPressed: _submit,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'By continuing you would normally agree to terms of service. There '
              'are none in this prototype — nothing here leaves the page.',
              style: AppType.bodySmall.quieter,
            ),
          ],
        ),
      ),
    );
  }
}
