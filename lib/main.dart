// ─────────────────────────────────────────────────────────────────────────────
// TutorMatch A.I. — entry point.
//
// Interface only. There is no backend, no database, no network call and no real
// K-nearest-neighbours pass; every tutor, student, score and review comes from
// lib/data/mock_data.dart. Google sign-in and email/password both simply move to
// the next screen, which is the entire behaviour they are asked to have.
//
// Routing is one switch in [onGenerateRoute]. No router package: there are eight
// screens and they all take plain arguments.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/match_detail_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/onboarding_screen.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/screens/register_screen.dart';
import 'package:tutormatch/screens/requests_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

void main() => runApp(const TutorMatchApp());

/// Route names, in one place so a typo is a compile error rather than a blank
/// screen. Arguments are the only state passed between pages.
abstract final class Routes {
  static const String landing = '/';
  static const String register = '/register';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String matches = '/matches';
  static const String matchDetail = '/match';
  static const String requests = '/requests';
  static const String profile = '/profile';
}

class TutorMatchApp extends StatefulWidget {
  const TutorMatchApp({super.key});

  @override
  State<TutorMatchApp> createState() => _TutorMatchAppState();
}

class _TutorMatchAppState extends State<TutorMatchApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _state,
      child: MaterialApp(
        title: 'TutorMatch A.I.',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: Routes.landing,
        onGenerateRoute: _route,
        // Keyboard order follows reading order, which matters most on the
        // onboarding form where every answer is a control.
        builder: (BuildContext context, Widget? child) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  Route<void> _route(RouteSettings settings) {
    final Object? args = settings.arguments;

    Route<void> build(Widget child) =>
        TMTransitions.page<void>(child, name: settings.name);

    switch (settings.name) {
      case Routes.register:
        final Role role = args is Role ? args : Role.student;
        return build(RegisterScreen(initialRole: role));
      case Routes.login:
        final Role role = args is Role ? args : Role.student;
        return build(LoginScreen(initialRole: role));
      case Routes.onboarding:
        final Role role = args is Role ? args : Role.student;
        return build(OnboardingScreen(role: role));
      case Routes.matches:
        return build(const MatchesScreen());
      case Routes.matchDetail:
        if (args is MatchResult) return build(MatchDetailScreen(result: args));
        return build(const MatchesScreen());
      case Routes.requests:
        return build(const RequestsScreen());
      case Routes.profile:
        return build(const ProfileScreen());
      case Routes.landing:
      default:
        return build(const LandingScreen());
    }
  }
}
