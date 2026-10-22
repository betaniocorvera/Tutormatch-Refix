// The location feature's promises, held to in one place: a public place is
// either an area, a city, or nothing at all; distances are rounded and only
// exist when both sides allow one; and a hidden area never becomes a pin, a
// label, or a "Nearby" reason.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/matches_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/location_map.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

void main() {
  setUpAll(_loadBundledFonts);
  group('the place catalogue', () {
    test('has at least twelve unique areas with plausible coordinates', () {
      expect(samplePlaces.length, greaterThanOrEqualTo(12));
      expect(
        samplePlaces.map((Place p) => p.id).toSet().length,
        samplePlaces.length,
      );
      expect(sampleCities.length, greaterThanOrEqualTo(8));

      for (final Place place in samplePlaces) {
        expect(place.name.trim(), isNotEmpty);
        expect(place.latitude.abs(), lessThanOrEqualTo(90));
        expect(place.longitude.abs(), lessThanOrEqualTo(180));
        expect(sampleCities.contains(place.city), isTrue);
      }
    });

    test('sample people span six areas, with one hidden and one city-only', () {
      final List<Candidate> all = <Candidate>[
        ...sampleTutors,
        ...sampleStudents,
      ];
      final Set<String> areas = <String>{
        for (final Candidate candidate in all)
          if (candidate.placeId.isNotEmpty) candidate.placeId,
      };

      expect(areas.length, greaterThanOrEqualTo(6));
      expect(
        all.where((Candidate c) => c.locationPrivacy == LocationPrivacy.hidden),
        isNotEmpty,
      );
      expect(
        all.where(
          (Candidate c) => c.locationPrivacy == LocationPrivacy.cityOnly,
        ),
        isNotEmpty,
      );
    });
  });

  group('public location', () {
    test('area, city-only and hidden resolve differently', () {
      final PublicPlace area = publicPlaceFor(
        'london-highbury',
        LocationPrivacy.area,
      )!;
      expect(area.label, 'Highbury, London');
      expect(area.cityOnly, isFalse);

      final PublicPlace city = publicPlaceFor(
        'london-highbury',
        LocationPrivacy.cityOnly,
      )!;
      expect(city.label, 'London');
      expect(city.cityOnly, isTrue);
      expect(city.latitude, cityLondon.latitude);
      expect(city.longitude, cityLondon.longitude);

      expect(publicPlaceFor('london-highbury', LocationPrivacy.hidden), isNull);
    });

    test('a hidden tutor has no public place, distance or location copy', () {
      final Candidate nora = candidateById('t-nora')!;
      expect(nora.locationPrivacy, LocationPrivacy.hidden);
      expect(nora.publicPlace, isNull);

      final MatchResult result = rank(
        sampleTutors,
        demoStudentProfile,
      ).firstWhere((MatchResult r) => r.candidate.id == 't-nora');
      expect(result.distanceKm, isNull);

      // Nothing the page renders may name the area either: the reasons,
      // credentials, headline and bio are all still read aloud.
      final String visible = <String>[
        for (final FitNote note in result.reasons)
          '${note.signal} ${note.detail}',
        ...nora.credentials,
        nora.headline,
        nora.bio,
      ].join(' ').toLowerCase();
      expect(visible, isNot(contains('sheffield')));
      expect(visible, isNot(contains('crookes')));
    });
  });

  group('distance', () {
    test('haversine is kilometre-scaled and copy is rounded', () {
      final double km = haversineKm(51.5072, -0.1276, 51.5390, -0.1426);
      expect(km, inInclusiveRange(3, 5));
      expect(describeDistance(3.4), 'about 3 km away');
      expect(describeDistance(0.4), 'less than 1 km away');
    });

    test(
      'a distance filter keeps rank order and removes far or hidden people',
      () {
        final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
        final MatchOutcome out = applyFilters(
          ranked,
          const MatchFilters(maxDistanceKm: 5),
          demoStudentProfile,
        );

        expect(out.empty, isNull);
        expect(out.results, isNotEmpty);
        final List<String> expected = ranked
            .where(
              (MatchResult r) => r.distanceKm != null && r.distanceKm! <= 5,
            )
            .map((MatchResult r) => r.candidate.id)
            .toList();
        expect(
          out.results.map((MatchResult r) => r.candidate.id).toList(),
          expected,
        );
        expect(
          out.results.any((MatchResult r) => r.candidate.id == 't-nora'),
          isFalse,
        );
        expect(
          out.results.every((MatchResult r) => r.distanceKm! <= 5),
          isTrue,
        );
      },
    );

    test('a nearby result carries a Nearby reason; a far one does not', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      final MatchResult near = ranked.firstWhere(
        (MatchResult r) => (r.distanceKm ?? 999) <= nearbyDistanceKm,
      );
      expect(near.reasons.length, 3);
      expect(
        near.reasons.any((FitNote note) => note.label == 'Nearby'),
        isTrue,
      );

      final MatchResult far = ranked.firstWhere(
        (MatchResult r) => (r.distanceKm ?? 0) > nearbyDistanceKm,
      );
      expect(
        far.reasons.any((FitNote note) => note.label == 'Nearby'),
        isFalse,
      );
    });
  });

  testWidgets('the ranked list switches to a map of the same results', (
    WidgetTester tester,
  ) async {
    debugLoadMapTiles = false;
    addTearDown(() => debugLoadMapTiles = true);
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppStateScope(
        notifier: AppState(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const MatchesScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.text('List'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pump();

    expect(find.byType(LocationMap), findsOneWidget);
    expect(find.textContaining('Circles are approximate'), findsOneWidget);
    // Tile loading is off for the test, which is the offline state too: the
    // neutral fallback must carry the area name, an icon and the reason, not
    // an empty rectangle.
    expect(find.byKey(const Key('map-offline')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('map-offline')),
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is TMIcon && widget.name == TMIconName.map,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Approximate areas'), findsOneWidget);
    expect(find.text('Map tiles need a connection.'), findsOneWidget);
  });
}

/// Registers the bundled faces under the names the theme asks for, so a test
/// measures the same text the browser draws.
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
