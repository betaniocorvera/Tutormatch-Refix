// ─────────────────────────────────────────────────────────────────────────────
// Register.
//
// Three fields, then the five answers. The account is created by the backend;
// the password is hashed there and never kept in the client.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/api_client.dart';
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
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String? emailError = validateEmail(_email.text);
    final String? passwordError = validatePassword(_password.text, isNew: true);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _error = null;
    });
    if (emailError != null || passwordError != null) return;

    setState(() => _busy = true);
    final AppState state = AppStateScope.read(context);
    try {
      await state.register(
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
        displayName: _name.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        Routes.onboarding,
        arguments: _role,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _googleUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Google sign-up is not configured. Create an email account instead.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      role: _role,
      onRoleChanged: (Role r) => setState(() => _role = r),
      title: 'Create your account',
      lede: 'Two things, then five questions. The account is real: your password '
          'is hashed by the backend and the session survives a reload.',
      nextSteps: const <String>[
        'Five questions about subjects, how you like to work, and the hours you actually keep free.',
        'A ranked list, with the score, three reasons, and the hours you both have open.',
        'Your answers are saved, so signing out does not throw them away.',
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
            AuthRoleSwitch(
              role: _role,
              onChanged: (Role r) => setState(() => _role = r),
            ),
            const SizedBox(height: Space.xl),
            TMButton(
              label: 'Continue with Google',
              variant: TMButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : _googleUnavailable,
            ),
            const SizedBox(height: Space.xl),
            const AuthDivider(label: 'or use an email address'),
            const SizedBox(height: Space.xl),
            TMTextField(
              label: 'Your name',
              reason: 'Shown on your profile. Only people you contact can see it.',
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
              helper: 'Where the other side replies. Never shown on your public profile.',
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
              helper: 'Eight characters or more. Stored as a hash, never as text.',
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Space.md),
              Text(
                _error!,
                style: AppType.bodySmall.tone(AppColors.alert),
              ),
            ],
            const SizedBox(height: Space.xl),
            TMButton(
              label: 'Create account and answer five questions',
              expand: true,
              busy: _busy,
              busyLabel: 'Creating your account…',
              icon: TMIconName.arrowRight,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'By continuing you agree to keep the conversation useful and '
              'respectful. The backend validates every field before it stores it.',
              style: AppType.bodySmall.quieter,
            ),
          ],
        ),
      ),
    );
  }
}
