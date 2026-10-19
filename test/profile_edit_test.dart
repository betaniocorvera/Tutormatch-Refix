// ─────────────────────────────────────────────────────────────────────────────
// The profile's edit mode.
//
// The promises the screen makes and this file holds it to: Save writes the
// draft and says so, Cancel writes nothing, the completeness meter counts the
// draft as it is typed rather than the saved profile, a profile with no name is
// refused, and the picture can be taken away again. Layout is not this file's
// job — that is screens_render_test.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/profile_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_field.dart';

/// A valid, opaque 1×1 red PNG: a picture picked from a device, in miniature.
/// The bytes are never decoded here — a widget test frame cannot wait for a
/// decode — but they are exactly what the picker hands to app state.
final Uint8List _redDot = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);

void main() {
  setUpAll(_loadBundledFonts);

  /// Two frames: the first starts an animation or a route, the second finishes
  /// it. One pump of a long duration only gets as far as the first frame.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the profile on a phone-width screen tall enough that the whole page
  /// fits. This file is about behaviour, and a tap that misses because the page
  /// scrolled is a wrong test rather than a wrong screen: real phone viewports
  /// are screens_render_test.dart's job.
  Future<AppState> open(WidgetTester tester, {AppState? state}) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final AppState s = state ?? AppState();
    await tester.pumpWidget(
      AppStateScope(
        notifier: s,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    return s;
  }

  /// Taps a control by its label. The page fits the viewport, so the label is
  /// on screen and there is nothing to scroll.
  Future<void> tapLabel(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await settle(tester);
  }

  /// The field whose label is [label]; the label lives inside the field.
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TMTextField));

  testWidgets('Save writes the draft and says so', (WidgetTester tester) async {
    final AppState state = await open(tester);
    await tapLabel(tester, 'Edit profile');

    await tester.enterText(field('Display name'), 'Maya C.');
    await tester.enterText(field('Lives in'), 'Finsbury Park, London');
    await tester.enterText(
      field('Bio'),
      'Worked examples first, then I do the next one on my own.',
    );
    await settle(tester);

    // Of the two Save rows, the top one — the other sits under the last field.
    await tapLabel(tester, 'Save changes');

    expect(state.profile.name, 'Maya C.');
    expect(state.profile.livesIn, 'Finsbury Park, London');
    expect(
      state.profile.bio,
      'Worked examples first, then I do the next one on my own.',
    );
    expect(find.text('Profile updated'), findsOneWidget);
    // Back to reading: the form's labels are gone.
    expect(find.text('Display name'), findsNothing);
  });

  testWidgets('Cancel leaves the profile exactly as it was',
      (WidgetTester tester) async {
    final AppState state = await open(tester);
    final String before = state.profile.name;

    await tapLabel(tester, 'Edit profile');
    await tester.enterText(field('Display name'), 'Someone Else');
    await settle(tester);
    await tapLabel(tester, 'Cancel');

    expect(state.profile.name, before);
    expect(find.text('Someone Else'), findsNothing);
    expect(find.text('Display name'), findsNothing);
  });

  testWidgets('an empty display name is refused, and says why',
      (WidgetTester tester) async {
    final AppState state = await open(tester);
    await tapLabel(tester, 'Edit profile');

    await tester.enterText(field('Display name'), '   ');
    await settle(tester);
    await tapLabel(tester, 'Save changes');

    expect(state.profile.name, demoStudentProfile.name);
    expect(find.textContaining('A display name is required'), findsOneWidget);
    // Still editing, so the answer can be fixed where it was given.
    expect(find.text('Display name'), findsOneWidget);
  });

  testWidgets('the completeness meter counts the draft, not the saved profile',
      (WidgetTester tester) async {
    await open(tester);
    // The demo student has everything but a picture and a bio.
    expect(find.text('Still missing: a picture, a bio.'), findsOneWidget);
    expect(find.text('10 of 12'), findsOneWidget);

    await tapLabel(tester, 'Edit profile');
    await tester.enterText(field('Bio'), 'Worked examples, mostly.');
    await settle(tester);

    expect(find.text('Still missing: a picture.'), findsOneWidget);
    expect(find.text('11 of 12'), findsOneWidget);

    await tapLabel(tester, 'Cancel');

    expect(find.text('Still missing: a picture, a bio.'), findsOneWidget);
    expect(find.text('10 of 12'), findsOneWidget);
  });

  testWidgets('a picture can be removed, and the initials come back',
      (WidgetTester tester) async {
    final AppState state = AppState()..photo = _redDot;
    await open(tester, state: state);

    // While a picture is set it stands in the initials' place.
    expect(find.text('MC'), findsNothing);
    expect(find.text('Change picture'), findsOneWidget);

    await tapLabel(tester, 'Change picture');
    expect(find.text('Remove picture'), findsOneWidget);

    await tapLabel(tester, 'Remove picture');

    expect(state.photo, isNull);
    expect(find.text('MC'), findsOneWidget);
    expect(find.text('Add a picture'), findsOneWidget);
  });
}

/// Registers the two bundled families under the names the theme asks for.
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
