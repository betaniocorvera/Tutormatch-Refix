import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/token_store.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/onboarding_screen.dart';
import 'package:tutormatch/screens/register_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

import 'test_support.dart';

const List<Size> _sizes = <Size>[
  Size(360, 780),
  Size(390, 844),
  Size(430, 932),
  Size(1440, 900),
];

void main() {
  setUpAll(loadBundledFonts);
  setUp(mockPreferences);

  AppState stateFor(FakeApi fake) => AppState(
        api: ApiClient(
          baseUrl: fakeBaseUrl,
          client: fake.client,
          tokenStore: TokenStore(),
        ),
        autoInitialize: false,
      );

  Future<void> render(
    WidgetTester tester,
    Widget screen,
    AppState state,
    Size size,
  ) async {
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await pumpScreen(tester, screen, state, size: size);
    } finally {
      FlutterError.onError = previous;
    }
    expect(
      errors.map((FlutterErrorDetails e) => e.exceptionAsString()).toList(),
      isEmpty,
      reason: '${screen.runtimeType} at ${size.width.toInt()}px',
    );
  }

  for (final Size size in _sizes) {
    final String at = '@${size.width.toInt()}px';

    testWidgets('landing and auth screens render $at',
        (WidgetTester tester) async {
      final FakeApi fake = FakeApi();
      final AppState state = stateFor(fake);
      addTearDown(state.dispose);
      await state.initialize();

      await render(tester, const LandingScreen(), state, size);
      await render(
        tester,
        const LoginScreen(initialRole: Role.student),
        state,
        size,
      );
      await render(
        tester,
        const RegisterScreen(initialRole: Role.tutor),
        state,
        size,
      );
      await render(
        tester,
        const OnboardingScreen(role: Role.student),
        state,
        size,
      );
    });

    testWidgets('the ranked list renders with live results $at',
        (WidgetTester tester) async {
      final FakeApi fake = FakeApi();
      final AppState state = stateFor(fake);
      addTearDown(state.dispose);
      await state.initialize();
      await state.login(
        email: 'maya@tutormatch.local',
        password: 'TutorMatch123!',
      );
      await state.loadMatches();

      await render(tester, const MatchesScreen(), state, size);
    });
  }
}
