// ─────────────────────────────────────────────────────────────────────────────
// Register.
//
// Four steps, one panel: account, details, recovery questions, consent. The
// values live in this State while the steps move, so Back never clears a field.
// The backend is still the authority: its 422 entries are mapped back onto the
// field that caused them, including each security answer.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/data/password_policy.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/auth_shell.dart';
import 'package:tutormatch/screens/privacy_notice_screen.dart';
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
  static const int _lastStep = 3;
  static const List<String> _stepLabels = <String>[
    'Account',
    'Details',
    'Security',
    'Consent',
  ];
  static const List<String> _stepTitles = <String>[
    'Who is signing up?',
    'What do you study or teach?',
    'Three questions for later.',
    'Before you create it.',
  ];

  late Role _role = widget.initialRole;
  int _step = 0;
  bool _busy = false;
  bool _consent = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final List<TextEditingController> _answers =
      List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
    growable: false,
  );

  final Set<String> _subjects = <String>{};
  String? _areaId;
  final List<String?> _questionIds = <String?>[null, null, null];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _phone.dispose();
    for (final TextEditingController controller in _answers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearError(String key) {
    if (_error == null && !_fieldErrors.containsKey(key)) return;
    setState(() {
      _error = null;
      final Map<String, String> next =
          Map<String, String>.from(_fieldErrors)..remove(key);
      _fieldErrors = next;
    });
  }

  void _clearErrors(Iterable<String> keys) {
    final List<String> present = <String>[
      for (final String key in keys)
        if (_fieldErrors.containsKey(key)) key,
    ];
    if (present.isEmpty && _error == null) return;
    setState(() {
      _error = null;
      final Map<String, String> next = Map<String, String>.from(_fieldErrors);
      for (final String key in present) {
        next.remove(key);
      }
      _fieldErrors = next;
    });
  }

  void _clearErrorWithoutNotify(String key) {
    if (!_fieldErrors.containsKey(key)) return;
    final Map<String, String> next =
        Map<String, String>.from(_fieldErrors)..remove(key);
    _fieldErrors = next;
  }

  void _clearErrorsWithoutNotify(Iterable<String> keys) {
    final Map<String, String> next = Map<String, String>.from(_fieldErrors);
    for (final String key in keys) {
      next.remove(key);
    }
    _fieldErrors = next;
  }

  void _next() {
    if (_busy) return;
    if (!_validateStep(_step)) return;
    if (_step < _lastStep) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_busy || _step == 0) return;
    setState(() => _step--);
  }

  bool _validateStep(int step) {
    final Map<String, String> errors = _errorsForStep(step);
    setState(() {
      _fieldErrors = errors;
      _error = null;
    });
    return errors.isEmpty;
  }

  Map<String, String> _errorsForStep(int step) {
    final Map<String, String> errors = <String, String>{};
    switch (step) {
      case 0:
        final String name = _name.text.trim();
        if (name.isEmpty) {
          errors['name'] = 'Enter your full name.';
        } else if (name.length < 2) {
          errors['name'] = 'Use at least 2 characters.';
        } else if (name.length > 80) {
          errors['name'] = 'Keep your name to 80 characters or fewer.';
        } else if (RegExp(r'[0-9]').hasMatch(name)) {
          errors['name'] =
              'Use letters, spaces, hyphens, apostrophes, and periods only.';
        }

        final String? emailError = validateEmail(_email.text);
        if (emailError != null) errors['email'] = emailError;

        final PasswordAssessment assessment = assessNewPassword(
          _password.text,
          email: _email.text,
          name: _name.text,
        );
        if (_password.text.isEmpty) {
          errors['password'] = 'Choose a password.';
        } else if (_password.text.length > 128) {
          errors['password'] = 'Keep the password to 128 characters or fewer.';
        } else if (assessment.error != null) {
          errors['password'] = assessment.error!;
        }

        if (_confirm.text.isEmpty) {
          errors['confirm'] = 'Repeat the password.';
        } else if (_confirm.text != _password.text) {
          errors['confirm'] = 'The two passwords do not match.';
        }
        break;

      case 1:
        if (_subjects.isEmpty) {
          errors['subjects'] = 'Choose at least one subject.';
        }
        if (_areaId == null || _areaId!.isEmpty) {
          errors['area_id'] = 'Choose the area you live or teach in.';
        }
        final String phone = _phone.text.trim();
        if (phone.isNotEmpty) {
          if (phone.length > 20) {
            errors['phone'] = 'Keep the phone number to 20 characters or fewer.';
          } else if (!RegExp(r'^[0-9+().\- ]+$').hasMatch(phone)) {
            errors['phone'] =
                'Use digits, spaces, +, -, ( ), and periods only.';
          } else if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
            errors['phone'] = 'Enter a phone number with at least 7 digits.';
          }
        }
        break;

      case 2:
        final String email = _email.text.trim().toLowerCase();
        final String localPart = email.split('@').first;
        final String name = _name.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
        final Set<String> nameTokens = <String>{
          for (final String token in name.split(RegExp(r"[\s\-'.]+")))
            if (token.length >= 3) token,
        };
        final Set<String> seenQuestions = <String>{};
        for (int i = 0; i < 3; i++) {
          final String? id = _questionIds[i];
          if (id == null) {
            errors['security_$i'] = 'Choose a question.';
          } else if (!seenQuestions.add(id)) {
            errors['security'] = 'Choose three different questions.';
          }

          final String answer = _answers[i].text.trim();
          final String normalized =
              answer.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (normalized.isEmpty) {
            errors['security_$i'] = 'Enter an answer.';
          } else if (normalized.length < 3) {
            errors['security_$i'] = 'Use at least 3 characters.';
          } else if (normalized.length > 128) {
            errors['security_$i'] =
                'Keep the answer to 128 characters or fewer.';
          } else if (normalized == email ||
              (localPart.length >= 3 && normalized == localPart) ||
              normalized == name ||
              nameTokens.contains(normalized)) {
            errors['security_$i'] =
                'Do not use your name or email as the answer.';
          }
        }
        if (!errors.containsKey('security')) {
          final bool hasAnswerError = errors.keys.any(
            (String key) => key.startsWith('security_'),
          );
          if (hasAnswerError) {
            errors['security'] = 'Check the three answers.';
          }
        }
        break;

      case 3:
        if (!_consent) {
          errors['privacy_consent'] =
              'Tick the box to agree to the Privacy Notice.';
        }
        break;
    }
    return errors;
  }

  Map<String, String> _mapServerErrors(Map<String, String> errors) {
    final Map<String, String> mapped = <String, String>{};
    errors.forEach((String key, String message) {
      if (key == 'subjects' || key.startsWith('subjects.')) {
        mapped['subjects'] = message;
      } else if (key == 'security_questions' ||
          key.startsWith('security_questions.')) {
        mapped['security'] = message;
        final List<String> parts = key.split('.');
        if (parts.length >= 3) {
          mapped['security_${parts[1]}'] = message;
        }
      } else if (key == 'display_name') {
        mapped['name'] = message;
      } else {
        mapped[key] = message;
      }
    });
    return mapped;
  }

  int _stepForErrors(Map<String, String> errors) {
    for (final String key in errors.keys) {
      if (key == 'email' ||
          key == 'password' ||
          key == 'confirm' ||
          key == 'name') {
        return 0;
      }
      if (key == 'subjects' || key == 'area_id' || key == 'phone') {
        return 1;
      }
      if (key.startsWith('security')) return 2;
      if (key == 'privacy_consent' || key == 'privacy_policy_version') {
        return 3;
      }
    }
    return _step;
  }

  Future<void> _submit() async {
    if (_busy) return;
    for (int step = 0; step <= _lastStep; step++) {
      if (!_validateStep(step)) {
        if (step != _step) {
          setState(() => _step = step);
        }
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });

    final AppState state = AppStateScope.read(context);
    try {
      await state.register(
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
        displayName: _name.text.trim(),
        phone: _phone.text.trim(),
        areaId: _areaId!,
        subjects: _subjects.toList(growable: false),
        securityQuestions: <SecurityAnswerInput>[
          for (int i = 0; i < 3; i++)
            SecurityAnswerInput(
              questionId: _questionIds[i]!,
              answer: _answers[i].text.trim(),
            ),
        ],
        privacyConsent: _consent,
        privacyPolicyVersion: PrivacyNoticeScreen.version,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        Routes.onboarding,
        arguments: _role,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      final Map<String, String> mapped = _mapServerErrors(error.fieldErrors);
      if (error.statusCode == 409) {
        mapped['email'] = error.message;
      }
      setState(() {
        _fieldErrors = mapped;
        _error = mapped.isEmpty ? error.message : null;
        if (mapped.isNotEmpty) {
          _step = _stepForErrors(mapped);
        }
      });
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

  String _questionText(AppState state, String id) {
    for (final SecurityQuestion question in state.securityQuestions) {
      if (question.id == id) return question.text;
    }
    return id;
  }

  List<SecurityQuestion> _questionOptions(AppState state, int index) {
    return <SecurityQuestion>[
      for (final SecurityQuestion question in state.securityQuestions)
        if (_questionIds.asMap().entries.every(
              (MapEntry<int, String?> entry) =>
                  entry.key == index || entry.value != question.id,
            ))
          question,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);

    return AuthShell(
      role: _role,
      onRoleChanged: (Role role) => setState(() => _role = role),
      title: 'Create your account',
      lede: 'Four short steps: your account, what you study or teach, three '
          'recovery questions, and the privacy consent. Your password and '
          'answers are hashed by the backend and never stored as text.',
      nextSteps: const <String>[
        'Your account details and a password only you know.',
        'Subjects, your area, and an optional phone number.',
        'Three different questions that can prove it is you later.',
        'A privacy consent you can read before you agree.',
      ],
      switchPrompt: 'Already have an account?',
      switchLabel: 'Sign in instead',
      onSwitch: () => Navigator.of(context).pushReplacementNamed(
        Routes.login,
        arguments: _role,
      ),
      formEyebrow: 'STEP ${_step + 1} OF 4',
      formTitle: _stepTitles[_step],
      form: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StepRail(current: _step, labels: _stepLabels),
            const SizedBox(height: Space.xl),
            _buildStep(state),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Space.lg),
              _FormBanner(message: _error!),
            ],
            const SizedBox(height: Space.xl),
            _buildNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(AppState state) {
    switch (_step) {
      case 0:
        return _accountStep();
      case 1:
        return _detailsStep(state);
      case 2:
        return _securityStep(state);
      default:
        return _consentStep();
    }
  }

  Widget _accountStep() {
    final PasswordAssessment assessment = assessNewPassword(
      _password.text,
      email: _email.text,
      name: _name.text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AuthRoleSwitch(
          role: _role,
          onChanged: (Role role) => setState(() => _role = role),
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
          label: 'Full name',
          reason: 'Shown on your profile. Your email and phone stay private.',
          controller: _name,
          hint: _role == Role.student ? 'Maya Chen' : 'Amara Okonkwo',
          error: _fieldErrors['name'],
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearError('name'),
        ),
        const SizedBox(height: Space.lg),
        TMTextField(
          label: 'Email',
          controller: _email,
          hint: 'you@school.example',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          error: _fieldErrors['email'],
          helper: 'Where the other side replies. Never shown on your public profile.',
          onChanged: (_) => _clearError('email'),
        ),
        const SizedBox(height: Space.lg),
        TMTextField(
          label: 'Password',
          controller: _password,
          hint: 'At least 10 characters',
          obscure: true,
          textInputAction: TextInputAction.next,
          error: _fieldErrors['password'],
          helper: 'At least 10 characters, upper and lower case, a digit, and a '
              'symbol. Stored as an Argon2id hash.',
          onChanged: (_) => _clearErrors(<String>['password', 'confirm']),
        ),
        if (_password.text.isNotEmpty) _PasswordMeter(assessment: assessment),
        const SizedBox(height: Space.lg),
        TMTextField(
          label: 'Confirm password',
          controller: _confirm,
          hint: 'Repeat the password',
          obscure: true,
          textInputAction: TextInputAction.done,
          error: _fieldErrors['confirm'],
          onChanged: (_) => _clearError('confirm'),
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _detailsStep(AppState state) {
    final String catalogMessage =
        state.catalogError ?? 'The catalogue could not be loaded.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TMFieldLabel(
          label: _role == Role.student
              ? 'Subjects you want help with'
              : 'Subjects you teach',
          reason: 'Choose up to four. The recommender reads every one.',
        ),
        const SizedBox(height: Space.md),
        if (state.subjects.isEmpty)
          _CatalogProblem(
            message: catalogMessage,
            onRetry: () => state.reloadCatalog(),
          )
        else
          TMTagPicker(
            options: state.subjects,
            selected: _subjects,
            max: 4,
            maxReachedNote: 'Four is the limit. Remove one to choose another.',
            onToggle: (String subject) => setState(() {
              if (!_subjects.remove(subject)) _subjects.add(subject);
              _clearErrorWithoutNotify('subjects');
            }),
          ),
        if (_fieldErrors['subjects'] != null)
          _InlineError(_fieldErrors['subjects']!),
        const SizedBox(height: Space.xl),
        if (state.places.isEmpty)
          _CatalogProblem(
            message: catalogMessage,
            onRetry: () => state.reloadCatalog(),
          )
        else
          TMDropdown<Place>(
            label: 'Area',
            value: state.placeById(_areaId),
            options: state.places,
            labelOf: (Place place) => place.label,
            hint: 'Choose an area',
            helper: 'Used for distance. Your public profile can show only the city.',
            onChanged: (Place place) => setState(() {
              _areaId = place.id;
              _clearErrorWithoutNotify('area_id');
            }),
          ),
        if (_fieldErrors['area_id'] != null)
          _InlineError(_fieldErrors['area_id']!),
        const SizedBox(height: Space.xl),
        TMTextField(
          label: 'Phone number',
          reason: 'Optional. Used for account contact; never shown publicly.',
          controller: _phone,
          hint: '+63 917 123 4567',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          error: _fieldErrors['phone'],
          onChanged: (_) => _clearError('phone'),
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _securityStep(AppState state) {
    if (state.securityQuestions.isEmpty) {
      return _CatalogProblem(
        message: state.catalogError ?? 'The security questions could not be loaded.',
        onRetry: () => state.reloadCatalog(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Pick three different questions. Answers are trimmed, lower-cased, '
          'and stored only as hashes; we never show them back to you or to '
          'anyone else.',
          style: AppType.bodySmall.tone(AppColors.inkSecondary),
        ),
        const SizedBox(height: Space.xl),
        for (int i = 0; i < 3; i++) ...<Widget>[
          TMDropdown<String>(
            label: 'Question ${i + 1}',
            value: _questionIds[i],
            options: <String>[
              for (final SecurityQuestion question in _questionOptions(state, i))
                question.id,
            ],
            labelOf: (String id) => _questionText(state, id),
            hint: 'Choose a question',
            onChanged: (String id) => setState(() {
              _questionIds[i] = id;
              _clearErrorsWithoutNotify(<String>['security_$i', 'security']);
            }),
          ),
          const SizedBox(height: Space.md),
          TMTextField(
            label: 'Answer ${i + 1}',
            controller: _answers[i],
            hint: 'Only you need to remember this',
            obscure: true,
            secretLabel: 'answer',
            textInputAction: i == 2 ? TextInputAction.done : TextInputAction.next,
            error: _fieldErrors['security_$i'],
            helper: i == 0
                ? 'At least 3 characters. Stored as a hash, never shown again.'
                : null,
            onChanged: (_) => _clearErrors(
              <String>['security_$i', 'security'],
            ),
            onSubmitted: i == 2 ? (_) => _next() : null,
          ),
          const SizedBox(height: Space.xl),
        ],
        if (_fieldErrors['security'] != null)
          _InlineError(_fieldErrors['security']!),
      ],
    );
  }

  Widget _consentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'TutorMatch collects the details you have entered, the profile you '
          'build, and the messages you send. The Privacy Notice explains what '
          'is collected, why, who can see it, how long it is kept, and your '
          'rights to access, correct, and delete it under RA 10173.',
          style: AppType.bodySmall.tone(AppColors.inkSecondary),
        ),
        const SizedBox(height: Space.xl),
        TMCheckbox(
          value: _consent,
          onChanged: (bool value) => setState(() {
            _consent = value;
            _clearErrorWithoutNotify('privacy_consent');
          }),
          label: 'I have read and agree to the Privacy Notice',
          helper: 'We record your consent, the time, and policy version '
              '${PrivacyNoticeScreen.version}.',
          error: _fieldErrors['privacy_consent'],
        ),
        const SizedBox(height: Space.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TMTextLink(
            label: 'Read the Privacy Notice',
            icon: TMIconName.arrowRight,
            color: AppColors.accent,
            minHeight: Hit.min,
            onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
          ),
        ),
        if (_fieldErrors['privacy_policy_version'] != null)
          _InlineError(_fieldErrors['privacy_policy_version']!),
      ],
    );
  }

  Widget _buildNavigation() {
    if (_step == 0) {
      return TMButton(
        label: 'Continue',
        expand: true,
        busy: _busy,
        busyLabel: 'Creating your account…',
        icon: TMIconName.arrowRight,
        onPressed: _busy ? null : _next,
      );
    }

    final bool last = _step == _lastStep;
    return Row(
      children: <Widget>[
        Expanded(
          child: TMButton(
            label: 'Back',
            variant: TMButtonVariant.quiet,
            icon: TMIconName.arrowLeft,
            iconLeading: true,
            onPressed: _busy ? null : _back,
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          flex: 2,
          child: TMButton(
            label: last ? 'Create account' : 'Continue',
            expand: true,
            busy: _busy,
            busyLabel: 'Creating your account…',
            icon: last ? TMIconName.check : TMIconName.arrowRight,
            onPressed: _busy ? null : (last ? _submit : _next),
          ),
        ),
      ],
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.current, required this.labels});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < labels.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: Space.xs),
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= current ? AppColors.accent : AppColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < current
                            ? AppColors.accent
                            : i == current
                                ? AppColors.accentWash
                                : AppColors.paperSunken,
                        shape: BoxShape.circle,
                        border: i == current
                            ? Border.all(color: AppColors.accent)
                            : null,
                      ),
                      child: i < current
                          ? const TMIcon(
                              TMIconName.check,
                              size: 13,
                              color: AppColors.onAccent,
                              strokeWidth: 2,
                            )
                          : Text(
                              '${i + 1}',
                              style: AppType.micro.tone(
                                i == current
                                    ? AppColors.accent
                                    : AppColors.inkMuted,
                              ),
                            ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro.tone(
                        i == current ? AppColors.ink : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PasswordMeter extends StatelessWidget {
  const _PasswordMeter({required this.assessment});

  final PasswordAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final Color color = assessment.score >= 3
        ? AppColors.accent
        : assessment.score == 2
            ? AppColors.amber
            : AppColors.alert;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: Space.sm),
        Row(
          children: <Widget>[
            for (int i = 0; i < 4; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: Space.xs),
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < assessment.score
                        ? color
                        : AppColors.paperSunken,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(assessment.label, style: AppType.bodySmall.tone(color)),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Text(
        message,
        style: AppType.bodySmall.tone(AppColors.alert),
      ),
    );
  }
}

class _FormBanner extends StatelessWidget {
  const _FormBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.alert.withValues(alpha: 0.07),
        border: Border.all(color: AppColors.alert.withValues(alpha: 0.35)),
        borderRadius: Radii.sharpAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const TMIcon(
            TMIconName.warning,
            size: 16,
            color: AppColors.alert,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              message,
              style: AppType.bodySmall.tone(AppColors.alert),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogProblem extends StatelessWidget {
  const _CatalogProblem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.paperSunken,
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: AppType.bodySmall.tone(AppColors.inkSecondary),
          ),
          const SizedBox(height: Space.sm),
          TMTextLink(
            label: 'Try again',
            color: AppColors.accent,
            minHeight: Hit.min,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
