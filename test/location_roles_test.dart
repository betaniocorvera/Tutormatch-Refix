// ─────────────────────────────────────────────────────────────────────────────
// The location feature is not a student feature.
//
// These tests stand on the tutor side and re-check the same promises the
// student-side location tests make: the shared edit section, the preview, the
// person page in both directions, the ranked list's distances and map, and the
// chat header. The role switch itself is included because a tutor profile must
// not inherit the demo student's saved area.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/screens/chat_screen.dart';
import 'package:tutormatch/screens/login_screen.dart';
import 'package:tutormatch/screens/match_detail_screen.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/screens/profile_preview_screen.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/location_map.dart';

void main() {
  setUpAll(_loadBundledFonts);
  setUp(() => debugLoadMapTiles = false);
  tearDown(() => debugLoadMapTiles = true);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> render(
    WidgetTester tester,
    Widget screen, {
    required AppState state,
    Size size = const Size(390, 4200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppStateScope(
        notifier: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: screen,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
  }

  test('changing the account role loads that side\'s profile', () {
    final AppState state = AppState()..role = Role.tutor;

    expect(state.profile.role, Role.tutor);
    expect(state.profile.placeId, demoTutorProfile.placeId);
    expect(state.profile.locationPrivacy, demoTutorProfile.locationPrivacy);
    expect(state.profile.publicPlace, isNotNull);

    state.role = Role.student;
    expect(state.profile.role, Role.student);
    expect(state.profile.placeId, demoStudentProfile.placeId);
    expect(state.profile.publicPlace, isNotNull);
  });

  test('every sample tutor has a complete, privacy-controlled location', () {
    for (final Candidate tutor in sampleTutors) {
      expect(tutor.livesIn.trim(), isNotEmpty, reason: tutor.id);
      expect(placeById(tutor.placeId), isNotNull, reason: tutor.id);
      if (tutor.locationPrivacy == LocationPrivacy.hidden) {
        expect(tutor.publicPlace, isNull, reason: tutor.id);
      } else {
        expect(tutor.publicPlace, isNotNull, reason: tutor.id);
      }
    }
    expect(
      sampleTutors.any(
        (Candidate c) => c.locationPrivacy == LocationPrivacy.hidden,
      ),
      isTrue,
    );
    expect(
      sampleTutors.any(
        (Candidate c) => c.locationPrivacy == LocationPrivacy.cityOnly,
      ),
      isTrue,
    );
  });

  testWidgets('signing in as a tutor lands on the tutor profile', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final AppState state = AppState();
    await tester.pumpWidget(
      AppStateScope(
        notifier: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const LoginScreen(initialRole: Role.student),
          routes: <String, WidgetBuilder>{
            Routes.matches: (_) => const Scaffold(body: Text('Matches')),
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.tap(find.text('Tutor'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'tutor@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'longenough');
    await tester.tap(find.text('Sign in').last);
    await tester.pump(const Duration(milliseconds: 1200));

    expect(state.role, Role.tutor);
    expect(state.profile.role, Role.tutor);
    expect(state.profile.placeId, demoTutorProfile.placeId);
    expect(state.profile.locationPrivacy, demoTutorProfile.locationPrivacy);
    expect(state.profile.publicPlace, isNotNull);
  });

  testWidgets('a tutor edits and saves the shared Lives in section', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState()..role = Role.tutor;
    await render(tester, const ProfileScreen(), state: state);

    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await settle(tester);

    // The same section the student sees, with the tutor fields still present.
    expect(find.text('LIVES IN'), findsOneWidget);
    expect(find.text('Province / region'), findsOneWidget);
    expect(find.text('City / municipality'), findsOneWidget);
    expect(find.text('Barangay / area'), findsOneWidget);
    expect(find.text('Location privacy'), findsOneWidget);
    expect(find.byType(LocationMap), findsOneWidget);
    expect(
      find.textContaining('Only your approximate area is shown to others.'),
      findsOneWidget,
    );
    expect(find.text('Years of experience'), findsOneWidget);
    expect(find.text('Education'), findsOneWidget);
    expect(find.text('Year level'), findsNothing);

    // Choose a different neighbourhood and make it public at area level.
    await tester.ensureVisible(find.byKey(const Key('place-area')));
    await tester.tap(find.byKey(const Key('place-area')));
    await settle(tester);
    await tester.tap(find.text('Didsbury').last);
    await settle(tester);

    final LocationMap preview = tester.widget<LocationMap>(
      find.byType(LocationMap),
    );
    expect(preview.centerLatitude, closeTo(53.4165, 0.0001));

    await tester.ensureVisible(
      find.text('Show my area on my profile and in Search'),
    );
    await tester.tap(find.text('Show my area on my profile and in Search'));
    await settle(tester);

    await tester.ensureVisible(find.text('Save changes').first);
    await tester.tap(find.text('Save changes').first);
    await settle(tester);

    expect(state.profile.role, Role.tutor);
    expect(state.profile.placeId, 'manchester-didsbury');
    expect(state.profile.livesIn, 'Didsbury, Manchester');
    expect(state.profile.locationPrivacy, LocationPrivacy.area);
    expect(find.byType(LocationMap), findsOneWidget);
    expect(find.text('Didsbury, Manchester'), findsWidgets);
  });

  testWidgets('a tutor preview follows the tutor privacy setting', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState()..role = Role.tutor;
    await render(tester, const ProfilePreviewScreen(), state: state);

    // The demo tutor is city-only: the map exists, the neighbourhood does not.
    expect(find.byType(LocationMap), findsOneWidget);
    expect(find.text('APPROXIMATE AREA'), findsOneWidget);
    expect(find.text('Manchester'), findsWidgets);
    expect(
      find.text('City only — the neighbourhood is not shown.'),
      findsOneWidget,
    );
    expect(find.text('Highbury, London'), findsNothing);

    // Hidden means no map, no area and no fallback text, for tutors too.
    state.profile = demoTutorProfile.copyWith(
      locationPrivacy: LocationPrivacy.hidden,
    );
    await settle(tester);
    expect(find.byType(LocationMap), findsNothing);
    expect(find.text('APPROXIMATE AREA'), findsNothing);
    expect(find.text('Manchester'), findsNothing);
  });

  testWidgets('a tutor with no area still sees the shared map preview', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState()
      ..profile = demoTutorProfile.copyWith(placeId: '', livesIn: '');
    await render(tester, const ProfileScreen(), state: state);

    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await settle(tester);

    final LocationMap preview = tester.widget<LocationMap>(
      find.byType(LocationMap),
    );
    expect(
      preview.centerLatitude,
      closeTo(samplePlaces.first.latitude, 0.0001),
    );
    expect(
      preview.centerLongitude,
      closeTo(samplePlaces.first.longitude, 0.0001),
    );
    expect(find.text('Choose your area'), findsOneWidget);
    expect(find.text('Years of experience'), findsOneWidget);
  });

  testWidgets(
    'the person page shows the other side\'s area in both directions',
    (WidgetTester tester) async {
      final MatchResult tutor = rank(
        sampleTutors,
        demoStudentProfile,
      ).firstWhere((MatchResult r) => r.distanceKm != null);
      await render(
        tester,
        MatchDetailScreen(result: tutor),
        state: AppState(),
        size: const Size(1100, 2200),
      );
      expect(find.byType(LocationMap), findsOneWidget);
      expect(find.text(tutor.candidate.publicPlace!.label), findsWidgets);
      expect(tutor.candidate.publicPlace, isNotNull);

      final AppState tutorState = AppState()..role = Role.tutor;
      final MatchResult student = rank(
        sampleStudents,
        tutorState.profile,
      ).firstWhere((MatchResult r) => r.distanceKm != null);
      await render(
        tester,
        MatchDetailScreen(result: student),
        state: tutorState,
        size: const Size(1100, 2200),
      );
      expect(find.byType(LocationMap), findsOneWidget);
      expect(find.text(student.candidate.publicPlace!.label), findsWidgets);
      expect(student.candidate.publicPlace, isNotNull);
    },
  );

  testWidgets('a tutor sees student distances and can switch to the map', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState()..role = Role.tutor;
    final List<MatchResult> ranked = rank(sampleStudents, state.profile);
    expect(ranked.every((MatchResult r) => r.distanceKm != null), isTrue);

    final MatchOutcome nearby = applyFilters(
      ranked,
      const MatchFilters(maxDistanceKm: 25),
      state.profile,
    );
    expect(nearby.results, isNotEmpty);
    expect(
      nearby.results.every((MatchResult r) => r.distanceKm! <= 25),
      isTrue,
    );

    await render(
      tester,
      const MatchesScreen(),
      state: state,
      size: const Size(1100, 1800),
    );

    // The redesigned list carries distance inside each result card rather
    // than in a table column header.
    expect(find.textContaining('km away'), findsWidgets);

    await tester.tap(find.text('Map'));
    await tester.pump();

    expect(find.byType(LocationMap), findsOneWidget);
    expect(find.text('Approximate areas'), findsOneWidget);
    expect(find.text('Map tiles need a connection.'), findsOneWidget);
  });

  testWidgets('the chat header shows an allowed area for both roles', (
    WidgetTester tester,
  ) async {
    await render(
      tester,
      const ChatScreen(conversationId: 'c-1041'),
      state: AppState(),
      size: const Size(390, 1600),
    );
    // Amara is city-only, so the student sees her city, never the area.
    expect(find.text('Manchester'), findsOneWidget);

    await render(
      tester,
      const ChatScreen(conversationId: 'c-2011'),
      state: AppState()..role = Role.tutor,
      size: const Size(390, 1600),
    );
    // Maya is also city-only, and the tutor sees the same public reading.
    expect(find.text('London'), findsOneWidget);
  });
}

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
  await family('PhosphorRegular', <String>[
    'assets/fonts/PhosphorRegular.ttf',
  ]);
  await family('PhosphorBold', <String>['assets/fonts/PhosphorBold.ttf']);
}
