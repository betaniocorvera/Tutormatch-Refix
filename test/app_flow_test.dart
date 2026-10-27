import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/token_store.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/chat_screen.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/state/app_state.dart';

import 'test_support.dart';

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TutorMatchApp(state: state));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(loadBundledFonts);
  setUp(mockPreferences);

  AppState makeState(FakeApi fake) => AppState(
        api: ApiClient(
          baseUrl: fakeBaseUrl,
          client: fake.client,
          tokenStore: TokenStore(),
        ),
      );

  testWidgets('the public landing uses the live catalogue, not sample people',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);

    await _pumpApp(tester, state);

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(state.subjects, contains('Calculus'));
    expect(find.text('Amara Okonkwo'), findsNothing);
  });

  testWidgets('a protected URL sends a signed-out visitor to sign in, then back',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    navigator.pushNamed(Routes.profile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(state.pendingDestination?.route, Routes.profile);

    final Finder seeded = find.text('Open the seeded student account');
    await tester.ensureVisible(seeded);
    await tester.pump();
    await tester.tap(seeded);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(state.isSignedIn, isTrue);
    expect(state.pendingDestination, isNull);
  });

  testWidgets('a login error stays on the form and explains itself',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi()..failLogin = true;
    final AppState state = makeState(fake);
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    navigator.pushNamed(Routes.login);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final Finder seeded = find.text('Open the seeded student account');
    await tester.ensureVisible(seeded);
    await tester.pump();
    await tester.tap(seeded);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(state.isSignedIn, isFalse);
  });

  testWidgets('a session that expires is removed from the dashboard',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    navigator.pushNamed(Routes.login);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final Finder seeded = find.text('Open the seeded student account');
    await tester.ensureVisible(seeded);
    await tester.pump();
    await tester.tap(seeded);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(MatchesScreen), findsOneWidget);

    fake
      ..expireSession = true
      ..failRefresh = true;
    await state.loadMatches();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(state.isSignedIn, isFalse);
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.byType(MatchesScreen), findsNothing);
  });

  testWidgets('the ranked list has a real error state and retries',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi()..failMatches = true;
    final AppState state = makeState(fake);
    addTearDown(state.dispose);
    await state.initialize();
    await state.login(
      email: 'maya@tutormatch.local',
      password: 'TutorMatch123!',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.matches, isEmpty);
    expect(state.matchesError, 'Matching is unavailable.');

    await pumpScreen(tester, const MatchesScreen(), state,
        size: const Size(900, 1400));

    expect(find.text('The ranking could not load.'), findsOneWidget);
    expect(find.text('Matching is unavailable.'), findsOneWidget);

    fake.failMatches = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Amara Okonkwo'), findsWidgets);
    expect(find.text('The ranking could not load.'), findsNothing);
  });

  testWidgets('a sent chat line is the only new line: no fake reply follows',
      (WidgetTester tester) async {
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);
    await state.initialize();
    await state.login(
      email: 'maya@tutormatch.local',
      password: 'TutorMatch123!',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await state.loadConversation('c-1');
    expect(state.conversation('c-1')!.messages, hasLength(1));

    await pumpScreen(
      tester,
      const ChatScreen(conversationId: 'c-1'),
      state,
      size: const Size(900, 1600),
    );

    await tester.enterText(find.byType(TextField).last, 'See you Thursday.');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('See you Thursday.'), findsOneWidget);
    expect(state.conversation('c-1')!.messages, hasLength(2));
    expect(state.conversation('c-1')!.messages.last.fromMe, isTrue);

    // Polling is REST, not a scripted typing animation or an automatic reply.
    expect(state.isTyping('c-1'), isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(state.conversation('c-1')!.messages, hasLength(2));
  });
}
