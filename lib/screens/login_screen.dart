// ─────────────────────────────────────────────────────────────────────────────
// Sign in.
//
// Same frame as register, so the two screens cannot drift apart. The demo
// account is a real seeded account on the backend: pressing it performs the same
// POST /auth/login as typing the email and password by hand.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
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
  String? _error;
  bool _busy = false;

  static const String _demoPassword = 'TutorMatch123!';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({String? email, String? password}) async {
    final String candidateEmail = email ?? _email.text;
    final String candidatePassword = password ?? _password.text;
    final String? emailError = validateEmail(candidateEmail);
    final String? passwordError =
        validatePassword(candidatePassword, isNew: false);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _error = null;
    });
    if (emailError != null || passwordError != null) return;

    setState(() => _busy = true);
    final AppState state = AppStateScope.read(context);
    try {
      final UserAccount user = await state.login(
        email: candidateEmail.trim(),
        password: candidatePassword,
      );
      if (!mounted) return;
      if (user.role != _role) {
        state.signOut();
        setState(() {
          _error = 'That is a ${user.role.name} account. '
              'Switch the role above and sign in again.';
        });
        return;
      }
      AuthFlow.complete(context);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useDemoAccount() {
    final String email = _role == Role.student
        ? 'maya@tutormatch.local'
        : 'amara@tutormatch.local';
    _email.text = email;
    _password.text = _demoPassword;
    _submit(email: email, password: _demoPassword);
  }

  void _googleUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Google sign-in is not configured. Use an email account or the seeded demo account.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      role: _role,
      onRoleChanged: (Role r) => setState(() => _role = r),
      title: 'Sign in',
      lede: 'Pick up your ranked list, your requests and your conversations. '
          'The account role decides whose list you see.',
      formEyebrow: 'YOUR ACCOUNT',
      formTitle: 'Sign in, and pick up the list.',
      nextSteps: const <String>[
        'Your ranked list and your filters, as you left them.',
        'Any requests you have sent, with their answers.',
        'Your conversations and unread messages.',
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
            AuthRoleSwitch(
              role: _role,
              label: 'I am signing in as',
              reason: 'The account itself owns its role. This selection chooses '
                  'the demo account and catches a mismatch before the dashboard.',
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
              label: 'Sign in',
              expand: true,
              busy: _busy,
              busyLabel: 'Finding your list…',
              icon: TMIconName.arrowRight,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: Space.xl),
            const AuthDivider(label: 'or use a seeded account'),
            const SizedBox(height: Space.lg),
            TMButton(
              label: _role == Role.student
                  ? 'Open the seeded student account'
                  : 'Open the seeded tutor account',
              variant: TMButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : _useDemoAccount,
            ),
            const SizedBox(height: Space.md),
            Text(
              _role == Role.student
                  ? 'maya@tutormatch.local · $_demoPassword\n'
                      'Maya Chen, Year 12 — calculus and physics, weekday evenings.'
                  : 'amara@tutormatch.local · $_demoPassword\n'
                      'Amara Okonkwo — calculus and statistics, online, weekday '
                      'evenings and Saturday mornings.',
              style: AppType.bodySmall.quieter,
            ),
          ],
        ),
      ),
    );
  }
}
