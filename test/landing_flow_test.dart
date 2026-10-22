// ─────────────────────────────────────────────────────────────────────────────
// The landing page's job: get a student or a tutor into the product without
// losing which side they said they were on.
//
// The hero's map orbits forever, so `pumpAndSettle` can never return here.
// Every wait below is a fixed pump long enough for the 380 ms route move.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/register_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';

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

  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settleRoute(tester);
  }

  testWidgets('a student can start from the hero and switch to sign in',
      (WidgetTester tester) async {
    await landing(tester);

    await tester.tap(find.text('Find my tutor'));
    await settleRoute(tester);

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).initialRole,
      Role.student,
    );

    await tapVisible(tester, find.text('Sign in instead'));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      tester.widget<LoginScreen>(find.byType(LoginScreen)).initialRole,
      Role.student,
    );

    await tapVisible(tester, find.text('Open the demo student account'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(MatchesScreen), findsOneWidget);
    final AppState state =
        AppStateScope.of(tester.element(find.byType(MatchesScreen)));
    expect(state.role, Role.student);
    expect(state.profileAnswered, isTrue);
  });

  testWidgets('the header sign-in keeps the student role',
      (WidgetTester tester) async {
    await landing(tester);

    // The footer link and the header link share a label; the header is painted
    // after the scrolling page, so it is the last one in the tree.
    await tester.tap(find.widgetWithText(TMTextLink, 'Sign in').last);
    await settleRoute(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      tester.widget<LoginScreen>(find.byType(LoginScreen)).initialRole,
      Role.student,
    );
  });

  testWidgets('header anchors stop below the fixed bar',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TutorMatchApp());
    await tester.pump(const Duration(milliseconds: 900));

    // The header is painted after the scrolling page, so its link is last.
    await tester.tap(find.text('How it works').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    final double top = tester
        .getTopLeft(find.text('Three steps, and the guesswork is gone.'))
        .dy;
    expect(top, greaterThan(72));
    expect(top, lessThan(130));
  });

  testWidgets('a tutor can start from the hero and switch to sign in',
      (WidgetTester tester) async {
    await landing(tester);

    await tester.tap(find.text('I teach instead'));
    await settleRoute(tester);

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(
      tester.widget<RegisterScreen>(find.byType(RegisterScreen)).initialRole,
      Role.tutor,
    );

    await tapVisible(tester, find.text('Sign in instead'));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      tester.widget<LoginScreen>(find.byType(LoginScreen)).initialRole,
      Role.tutor,
    );

    await tapVisible(tester, find.text('Open the demo tutor account'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(MatchesScreen), findsOneWidget);
    final AppState state =
        AppStateScope.of(tester.element(find.byType(MatchesScreen)));
    expect(state.role, Role.tutor);
    expect(state.profileAnswered, isTrue);
  });
}
