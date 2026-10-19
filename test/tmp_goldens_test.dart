// TEMPORARY — writes screenshots so the interface can be looked at on a machine
// with no browser connected. Deleted once reviewed.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/landing_screen.dart';
import 'package:tutormatch/screens/match_detail_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/onboarding_screen.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/screens/register_screen.dart';
import 'package:tutormatch/screens/requests_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

Future<void> _loadBundledFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final FontLoader loader = FontLoader(name);
    for (final String asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('Spectral', <String>[
    'assets/fonts/Spectral-Regular.ttf',
    'assets/fonts/Spectral-Italic.ttf',
    'assets/fonts/Spectral-SemiBold.ttf',
    'assets/fonts/Spectral-Bold.ttf',
  ]);
  await family('Public Sans', <String>['assets/fonts/PublicSans-Variable.ttf']);
}

void main() {
  setUpAll(_loadBundledFonts);

  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    Size size,
    String name, {
    AppState? state,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppStateScope(
        notifier: state ?? AppState(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: screen,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('_shots/$name.png'),
    );
  }

  testWidgets('shots', (WidgetTester tester) async {
    await shoot(tester, const LandingScreen(), const Size(1440, 1250), 'a_landing_1440');
    await shoot(tester, const LandingScreen(), const Size(390, 1250), 'b_landing_390');
    await shoot(tester, const MatchesScreen(), const Size(1440, 1000), 'c_matches_1440');
    await shoot(tester, const MatchesScreen(), const Size(390, 1300), 'd_matches_390');
    await shoot(
      tester,
      MatchDetailScreen(result: landingSpecimen()),
      const Size(1440, 1300),
      'e_detail_1440',
    );
    await shoot(
      tester,
      const OnboardingScreen(role: Role.student),
      const Size(390, 1150),
      'f_onboarding_390',
    );
    await shoot(tester, const RequestsScreen(), const Size(390, 900), 'g_requests_390');
    await shoot(tester, const ProfileScreen(), const Size(1440, 1150), 'h_profile_1440');
    await shoot(tester, const RegisterScreen(initialRole: Role.student),
        const Size(390, 900), 'i_register_390');
  });

  testWidgets('what is that mark at the top left', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppStateScope(
          notifier: AppState(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const LandingScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final ByteData data =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    String px(int x, int y) {
      final int o = (y * image.width + x) * 4;
      return '($x,$y)=${data.getUint8(o)},${data.getUint8(o + 1)},${data.getUint8(o + 2)}';
    }

    // ignore: avoid_print
    print('probe: across the top   ${px(0, 0)} ${px(1, 1)} ${px(60, 1)} ${px(113, 1)} '
        '${px(118, 1)} ${px(200, 1)} ${px(700, 1)} ${px(1439, 1)}');
    // ignore: avoid_print
    print('probe: down the left    ${px(113, 5)} ${px(113, 20)} ${px(113, 40)} '
        '${px(113, 56)} ${px(113, 60)} ${px(113, 70)} ${px(113, 120)}');
    // ignore: avoid_print
    print('probe: row through it   ${px(100, 20)} ${px(110, 20)} ${px(112, 20)} '
        '${px(114, 20)} ${px(116, 20)} ${px(120, 20)} ${px(130, 20)} ${px(168, 20)}');
  });
}
