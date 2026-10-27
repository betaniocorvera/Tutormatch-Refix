// ─────────────────────────────────────────────────────────────────────────────
// TutorMatch A.I. — entry point.
//
// The app talks to the FastAPI service in backend/. The session is restored from
// the refresh token before the first protected route is built, so a reload does
// not flash the dashboard and then throw the person out. Every route still goes
// through one switch; there is no router package.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/models.dart';
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
  const TutorMatchApp({this.state, super.key});

  /// Tests inject a state backed by a mock HTTP client. Production passes null.
  final AppState? state;

  @override
  State<TutorMatchApp> createState() => _TutorMatchAppState();
}

class _TutorMatchAppState extends State<TutorMatchApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppState _state = widget.state ?? AppState();
  late bool _wasSignedIn = _state.isSignedIn;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    if (widget.state == null) _state.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (_state.isReady && _wasSignedIn && !_state.isSignedIn) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        Routes.landing,
        (Route<dynamic> route) => false,
      );
    }
    _wasSignedIn = _state.isSignedIn;
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (BuildContext context, Widget? child) {
          if (!_state.isReady) return const _BootstrapScreen();
          return MaterialApp(
            title: 'TutorMatch A.I.',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            theme: AppTheme.light(),
            onGenerateRoute: _route,
            builder: (BuildContext context, Widget? child) =>
                FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

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

  Route<void> _route(RouteSettings settings) {
    final String? name = settings.name;
    final Object? args = settings.arguments;

    Route<void> build(Widget child, {String? name}) =>
        TMTransitions.page<void>(child, name: name ?? settings.name);

    if (!_state.isSignedIn && _isProtected(name)) {
      if (name != Routes.onboarding) {
        _state.rememberDestination(name!, args);
      }
      return build(
        LoginScreen(initialRole: _state.role),
        name: Routes.login,
      );
    }

    if (_state.isSignedIn && _isAuthEntry(name)) {
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
        final Role role = args is Role ? args : _state.role;
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

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TutorMatch A.I.',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('TutorMatch', style: AppType.titleLarge),
              const SizedBox(height: Space.sm),
              Text(
                'Restoring your session',
                style: AppType.bodySmall.quieter,
              ),
              const SizedBox(height: Space.xl),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class AuthFlow {
  static void complete(BuildContext context) {
    final AppState state = AppStateScope.read(context);
    if (!state.profileAnswered) {
      Navigator.of(context).pushReplacementNamed(
        Routes.onboarding,
        arguments: state.role,
      );
      return;
    }
    final PendingDestination destination = state.takePendingDestination() ??
        const PendingDestination(Routes.matches);
    Navigator.of(context).pushNamedAndRemoveUntil(
      destination.route,
      (Route<dynamic> route) => false,
      arguments: destination.arguments,
    );
  }

  static void signOut(BuildContext context) {
    AppStateScope.read(context).signOut();
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.landing,
      (Route<dynamic> route) => false,
    );
  }
}
