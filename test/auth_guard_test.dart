// ─────────────────────────────────────────────────────────────────────────────
// The public / dashboard boundary.
//
// The landing page is public and no longer shows a ranked list. Every route
// that reveals a candidate, a request, a conversation or a profile is guarded
// once, in main.dart, and that guard has to survive both typed URLs and Back.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/onboarding_screen.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/screens/register_screen.dart';
import 'package:tutormatch/state/app_state.dart';

Future<void> _loadBundledFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final FontLoader loader = FontLoader(name);
    for (final String asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('Bricolage Grotesque', <String>[
    'assets/fonts/BricolageGrotesque-Variable.ttf',
  ]);
  await family('Figtree', <String>['assets/fonts/Figtree-Variable.ttf']);
  await family('IBM Plex Mono', <String>[
    'assets/fonts/IBMPlexMono-Regular.ttf',
    'assets/fonts/IBMPlexMono-Medium.ttf',
  ]);
  await family('PhosphorRegular', <String>['assets/fonts/PhosphorRegular.ttf']);
  await family('PhosphorBold', <String>['assets/fonts/PhosphorBold.ttf']);
}

void main() {
  setUpAll(_loadBundledFonts);

  Future<void> landing(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TutorMatchApp());
    await tester.pump(const Duration(milliseconds: 900));
  }

  Future<void> route(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await route(tester);
  }

  testWidgets('the signed-out landing has no ranked tutor section',
      (WidgetTester tester) async {
    await landing(tester);

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(
      find.text('Three of the sixteen, ranked for the student on this page.'),
      findsNothing,
    );
    expect(find.text('What this pool actually teaches.'), findsOneWidget);
  });

  testWidgets('every dashboard route goes to Login while signed out',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    const List<String> guarded = <String>[
      Routes.matches,
      Routes.matchDetail,
      Routes.requests,
      Routes.messages,
      Routes.chat,
      Routes.profile,
      Routes.profilePreview,
      Routes.onboarding,
    ];

    for (final String name in guarded) {
      navigator.pushNamed(name);
      await route(tester);
      expect(find.byType(LoginScreen), findsOneWidget, reason: name);
      expect(find.byType(MatchesScreen), findsNothing, reason: name);

      navigator.pop();
      await route(tester);
      expect(find.byType(LandingScreen), findsOneWidget, reason: name);
    }
  });

  testWidgets('Back from the sign-in detour returns to the public page',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.pushNamed(Routes.profile);
    await route(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    final bool handled = await tester.binding.handlePopRoute();
    await route(tester);

    expect(handled, isTrue);
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('login returns to the dashboard page that was requested',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.pushNamed(Routes.profile);
    await route(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    final AppState state =
        AppStateScope.of(tester.element(find.byType(LoginScreen)));
    expect(state.pendingDestination?.route, Routes.profile);

    await tapVisible(tester, find.text('Open the demo student account'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(state.isSignedIn, isTrue);
    expect(state.pendingDestination, isNull);
  });

  testWidgets('registration keeps the requested page through onboarding',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.pushNamed(Routes.profile);
    await route(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tapVisible(tester, find.text('Create one in two fields'));
    expect(find.byType(RegisterScreen), findsOneWidget);
    final AppState state =
        AppStateScope.of(tester.element(find.byType(RegisterScreen)));

    await tapVisible(tester, find.text('Continue with Google'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.isSignedIn, isTrue);
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tapVisible(tester, find.text('Use the demo profile'));
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('a signed-in visitor is sent away from Login and Register',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.pushNamed(Routes.login);
    await route(tester);
    await tapVisible(tester, find.text('Open the demo student account'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(MatchesScreen), findsOneWidget);

    navigator.pushNamed(Routes.login);
    await route(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MatchesScreen), findsOneWidget);

    navigator.pushNamed(Routes.register);
    await route(tester);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(MatchesScreen), findsOneWidget);
    // Let the ranked list finish its one delayed build before the test tears
    // down the binding.
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('signing out clears the session and leaves nothing to go back to',
      (WidgetTester tester) async {
    await landing(tester);
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.pushNamed(Routes.login);
    await route(tester);
    await tapVisible(tester, find.text('Open the demo student account'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(MatchesScreen), findsOneWidget);

    final AppState state =
        AppStateScope.of(tester.element(find.byType(MatchesScreen)));
    expect(state.isSignedIn, isTrue);

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.byType(MatchesScreen), findsNothing);
    expect(state.isSignedIn, isFalse);
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('a dashboard URL typed on a cold start reaches Login',
      (WidgetTester tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = Routes.profile;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await landing(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);

    final AppState state =
        AppStateScope.of(tester.element(find.byType(LoginScreen)));
    expect(state.pendingDestination?.route, Routes.profile);

    await tapVisible(tester, find.text('Open the demo student account'));
    await tester.pump(const Duration(milliseconds: 900));

    // The cold-start URL is honoured after sign-in, not discarded.
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
