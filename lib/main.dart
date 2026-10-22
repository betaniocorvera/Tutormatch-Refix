// ─────────────────────────────────────────────────────────────────────────────
// TutorMatch A.I. — entry point.
//
// Interface only. There is no backend, no database, no network call and no real
// K-nearest-neighbours pass; every tutor, student, score and review comes from
// lib/data/mock_data.dart. Google sign-in and email/password both simply move to
// the next screen, which is the entire behaviour they are asked to have.
//
// Routing is one switch in [onGenerateRoute]. No router package: there are ten
// screens and they all take plain arguments.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/chat_screen.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/match_detail_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/messages_screen.dart';
import 'package:tutormatch/screens/onboarding_screen.dart';
import 'package:tutormatch/screens/profile_preview_screen.dart';
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
  static const String messages = '/messages';
  static const String chat = '/chat';
  static const String profile = '/profile';
  static const String profilePreview = '/profile/preview';
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
        // No fixed initialRoute: on the web this lets /#/matches and /#/chat
        // reach the guard instead of being replaced by the landing page.
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

  /// Every dashboard route. Landing, Login and Register are deliberately not
  /// in this set; onboarding is protected because it is the second half of
  /// registration and must not be reachable as a stranger.
  static bool _isProtected(String? name) =>
      name == Routes.matches ||
      name == Routes.matchDetail ||
      name == Routes.requests ||
      name == Routes.messages ||
      name == Routes.chat ||
      name == Routes.profile ||
      name == Routes.profilePreview ||
      name == Routes.onboarding;

  static bool _isAuthEntry(String? name) =>
      name == Routes.login || name == Routes.register;

  /// The only route gate in the app. Screens never check [AppState.isSignedIn]
  /// themselves: a named route either builds its page or is replaced by Login
  /// here, which is also what makes Back and a typed URL take the same path.
  Route<void> _route(RouteSettings settings) {
    final String? name = settings.name;
    final Object? args = settings.arguments;

    Route<void> build(Widget child, {String? name}) =>
        TMTransitions.page<void>(child, name: name ?? settings.name);

    if (!_state.isSignedIn && _isProtected(name)) {
      // Remember where the visitor was going, including a match result or a
      // conversation id. Onboarding is a registration step, not a destination,
      // so it is redirected without being remembered.
      if (name != Routes.onboarding) {
        _state.rememberDestination(name!, args);
      }
      return build(
        LoginScreen(initialRole: _state.role),
        name: Routes.login,
      );
    }

    if (_state.isSignedIn && _isAuthEntry(name)) {
      // A signed-in visitor has no business on the auth forms, and a stale
      // destination must not send them back to one after this.
      _state.clearPendingDestination();
      return build(const MatchesScreen(), name: Routes.matches);
    }

    switch (name) {
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
      case Routes.messages:
        return build(const MessagesScreen());
      case Routes.chat:
        // A conversation id, not a conversation: the chat reads the live one.
        final Object? id = args;
        if (id is String) return build(ChatScreen(conversationId: id));
        return build(const MessagesScreen());
      case Routes.profile:
        return build(const ProfileScreen());
      case Routes.profilePreview:
        return build(const ProfilePreviewScreen());
      case Routes.landing:
      default:
        return build(const LandingScreen());
    }
  }
}

/// The two navigation moves both sides of the auth boundary share.
abstract final class AuthFlow {
  /// Called after a successful sign-in or after the five answers at the end of
  /// registration. Returns to the page the visitor originally asked for, or the
  /// ranked list when they started at Login/Register directly.
  static void complete(BuildContext context) {
    final AppState state = AppStateScope.read(context);
    final PendingDestination destination = state.takePendingDestination() ??
        const PendingDestination(Routes.matches);
    Navigator.of(context).pushNamedAndRemoveUntil(
      destination.route,
      (Route<dynamic> route) => false,
      arguments: destination.arguments,
    );
  }

  /// Clear the session before replacing the whole stack, so neither a pop nor
  /// browser Back can reveal a dashboard route retained from the signed-in
  /// session.
  static void signOut(BuildContext context) {
    AppStateScope.read(context).signOut();
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.landing,
      (Route<dynamic> route) => false,
    );
  }
}
