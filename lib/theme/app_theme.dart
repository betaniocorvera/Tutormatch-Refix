// ─────────────────────────────────────────────────────────────────────────────
// TutorMatch visual system.
//
// This is the ONLY file in the project that names a colour, a font size, a
// radius or a spacing value. Widgets and screens read from it. If you need a
// value that is not here, add it here first — that rule is what keeps the
// product looking like one product instead of eight screens by eight people.
//
// THE WORLD: a university course bulletin. Warm paper, ink, hairline rules,
// tabular numerals, entries that read as printed rows rather than floating
// cards. Two voices: Spectral (a serif) speaks — titles, people's names,
// editorial prose — and Public Sans works: labels, controls, every number.
// The one accent is an ink red. It marks the primary action, the current
// selection and the match score, and it is never used for status.
//
// Scene that fixed light/dark: a student at a kitchen table in the afternoon,
// a tutor between lessons in a well-lit room. Paper wins.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Roles in the product. Used for copy, routes and which side of a match you are.
enum Role { student, tutor }

// ─────────────────────────────────────────────────────────────────────────────
// Colour
// ─────────────────────────────────────────────────────────────────────────────

/// Every colour in the product, in one place, named by its job.
///
/// Contrast notes are measured against [paper] unless stated otherwise.
/// Accent and moss both clear 4.5:1 on paper AND as fills under [onAccent].
abstract final class AppColors {
  // Grounds — warm paper, three depths. No cool greys anywhere.
  static const Color paper = Color(0xFFF6F1E6); // page ground
  static const Color paperRaised = Color(0xFFFDFAF3); // entries, inputs
  static const Color paperSunken = Color(0xFFEDE6D7); // rails, wells, tracks

  // Ink — warm near-black through to a quiet grey-brown. 14.3:1 / 8.7:1 / 5.2:1
  static const Color ink = Color(0xFF17130E);
  static const Color inkSecondary = Color(0xFF4B4237);
  static const Color inkMuted = Color(0xFF6E6455);
  static const Color onAccent = Color(0xFFFFFCF6); // on ink, on accent, on moss

  // Text on the ink band. Measured against [ink]: 18.0:1, 12.0:1, 8.3:1.
  // Tinted from the paper hue, never grey — grey on warm black reads dead.
  static const Color onInkQuiet = Color(0xFFD8CFBE);
  static const Color onInkFaint = Color(0xFFB9AC94);

  // Rules — hairline separators. The system's primary depth device.
  static const Color rule = Color(0xFFDCD3C1);
  static const Color ruleStrong = Color(0xFFB9AC94);

  // The one accent. 6.6:1 on paper, 7.3:1 under onAccent text.
  //
  // The accent has exactly four jobs and they are all "what needs your
  // attention": the primary action, the current selection, the match score, and
  // a field you have to fix. It is never used for request status — accepted,
  // pending and rejected have their own vocabulary below, because a rejected
  // request wearing the action colour is a lie about what just happened.
  static const Color accent = Color(0xFF9E2B25);

  /// Form validation and blocked actions. Same red as the accent: the
  /// difference is context, not hue, and inventing a second red would fail
  /// contrast or read as a different brand.
  static const Color alert = accent;
  static const Color accentPressed = Color(0xFF7C1F1A);
  static const Color accentWash = Color(0xFFF4E3DE); // tint for selected rows

  // Status. Deliberately NOT the accent — a rejected request must not look
  // like a primary action.
  static const Color accepted = Color(0xFF3E5C4B); // 6.6:1 on paper
  static const Color acceptedWash = Color(0xFFE3EAE3);
  static const Color pending = Color(0xFF8A5A11); // 5.3:1 on paper
  static const Color pendingWash = Color(0xFFF5E9D5);
  static const Color declined = Color(0xFF6E6455); // = inkMuted, on purpose
  static const Color declinedWash = Color(0xFFE9E3D6);

  // Focus. Ink, not accent, so focus is unambiguous: it is the only 2px ring
  // in the system and it never competes with selection for meaning.
  static const Color focusRing = Color(0xFF17130E);

  /// Ink on a coloured fill. Kept as a function so a new fill cannot be added
  /// without deciding what sits on top of it.
  static Color on(Color fill) =>
      (fill == paper || fill == paperRaised || fill == paperSunken) ? ink : onAccent;

  /// Tint for a status wash and the ink that belongs on it.
  static (Color wash, Color text) statusTint(StatusTone tone) => switch (tone) {
        StatusTone.pending => (pendingWash, pending),
        StatusTone.accepted => (acceptedWash, accepted),
        StatusTone.declined => (declinedWash, declined),
        StatusTone.neutral => (paperSunken, inkSecondary),
      };
}

/// The four tones a request or a filter can be in. One vocabulary, everywhere.
enum StatusTone { pending, accepted, declined, neutral }

// ─────────────────────────────────────────────────────────────────────────────
// Space, radius, size
// ─────────────────────────────────────────────────────────────────────────────

/// A 4 px rhythm. Named by step, not by pixel count, so a value can be
/// retuned in one place.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
  static const double vast = 96;

  /// The gap between major bands of a page. Grows with the viewport.
  static double band(double width) => width >= AppBreakpoints.wide ? vast : huge;
}

/// Corners. Print has nearly square corners; the web rounds everything. We
/// side with print, and keep one soft radius for the two things that genuinely
/// float above the page.
abstract final class Radii {
  static const double sharp = 3; // entries, inputs, buttons — the default
  static const double soft = 12; // the floating action panel, dialogs, menus
  static const double pill = 999; // tags and chips only, never a container
  static const BorderRadius sharpAll = BorderRadius.all(Radius.circular(sharp));
  static const BorderRadius softAll = BorderRadius.all(Radius.circular(soft));
}

/// Minimum hit area. Apple and Material both land on 44; we hold it everywhere,
/// including on the compact tag chips by padding rather than by growing them.
abstract final class Hit {
  static const double min = 44;
}

/// Named widths. Compact is a phone; wide is a laptop with a rail beside the
/// content; maxContent stops the measure from running away on a 4K monitor.
abstract final class AppBreakpoints {
  static const double compact = 640; // below: one column, stacked
  static const double medium = 900; // below: rail collapses under content
  static const double wide = 1200; // at/above: full two-column shell
  static const double maxContent = 1200;
  static const double measure = 68; // characters, for prose columns
}

/// Motion. Short and purposeful: state changes only, never decoration.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
// Type
// ─────────────────────────────────────────────────────────────────────────────

/// The type scale. Two families, one job each.
///
/// Spectral is the editorial voice and appears ONLY on titles, people's names,
/// pull quotes and the wordmark. It is never used for a label, a button or a
/// number, because in this product every number is data and data is read in
/// Public Sans with tabular figures.
///
/// Both faces are bundled in assets/fonts and declared in pubspec.yaml. Nothing
/// is fetched at runtime: the first frame is set in the real type, and the app
/// renders identically with no network.
///
/// Product screens use this fixed scale. Only the landing hero is fluid, via
/// [heroAt], because it is the one brand surface in the app.
abstract final class AppType {
  static const String _serifFamily = 'Spectral';
  static const String _sansFamily = 'Public Sans';

  static const List<String> _serifFallback = <String>['Georgia', 'serif'];
  static const List<String> _sansFallback = <String>[
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
  ];

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// Public Sans is one variable file, whose default instance is Regular.
  /// Without this the whole interface would draw in Regular whatever weight was
  /// asked for, and the labels and numerals that carry the hierarchy would lose
  /// it. Static families ignore `fontVariations`, so this is safe for Spectral.
  static List<FontVariation> _wght(FontWeight weight) =>
      <FontVariation>[FontVariation('wght', weight.value.toDouble())];

  static TextStyle _serif(
    double size,
    FontWeight weight,
    double height, {
    double tracking = 0,
    Color color = AppColors.ink,
    bool italic = false,
  }) =>
      TextStyle(
        fontFamily: _serifFamily,
        fontFamilyFallback: _serifFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      );

  static TextStyle _sans(
    double size,
    FontWeight weight,
    double height, {
    double tracking = 0,
    Color color = AppColors.ink,
    bool tabular = false,
  }) =>
      TextStyle(
        fontFamily: _sansFamily,
        fontFamilyFallback: _sansFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color,
        fontVariations: _wght(weight),
        fontFeatures: tabular ? _tabular : null,
      );

  // ── Display — Spectral ────────────────────────────────────────────────────
  /// Landing hero only. Fluid; see [heroAt].
  static TextStyle get hero => heroAt(375);
  static TextStyle heroAt(double width) => _serif(
        width >= AppBreakpoints.wide
            ? 68
            : width >= AppBreakpoints.medium
                ? 52
                : width >= AppBreakpoints.compact
                    ? 40
                    : 33,
        FontWeight.w600,
        width >= AppBreakpoints.medium ? 1.02 : 1.08,
        tracking: -0.02,
      );

  /// The largest serif used inside the product: page titles.
  static TextStyle get pageTitle => _serif(31, FontWeight.w600, 1.14, tracking: -0.015);
  static TextStyle get titleLarge => _serif(24, FontWeight.w600, 1.2, tracking: -0.01);

  /// A person's name on a match entry. The subject of the row, so it is serif.
  static TextStyle get name => _serif(21, FontWeight.w600, 1.22, tracking: -0.008);
  static TextStyle get sectionTitle => _serif(17.5, FontWeight.w600, 1.3);
  static TextStyle get quote => _serif(19, FontWeight.w400, 1.5, italic: true);
  static TextStyle get wordmark => _serif(21, FontWeight.w700, 1.0, tracking: -0.015);

  // ── Task — Public Sans ────────────────────────────────────────────────────
  static TextStyle get bodyLarge => _sans(16.5, FontWeight.w400, 1.62);
  static TextStyle get body => _sans(15, FontWeight.w400, 1.6);
  static TextStyle get bodySmall => _sans(13.5, FontWeight.w400, 1.55);
  static TextStyle get label => _sans(14.5, FontWeight.w500, 1.35);
  static TextStyle get labelSmall => _sans(13, FontWeight.w500, 1.35);
  static TextStyle get button => _sans(15, FontWeight.w600, 1.0, tracking: 0.005);

  /// Uppercase micro-label. Used for data captions and column headers — a
  /// label on a table, never an eyebrow above a heading.
  static TextStyle get micro => _sans(11, FontWeight.w600, 1.25, tracking: 0.1);

  // ── Numerals — always tabular ─────────────────────────────────────────────
  /// The match score. The single largest number in the product.
  static TextStyle get score => _sans(40, FontWeight.w700, 1.0, tracking: -0.03, tabular: true);
  static TextStyle get scoreSmall => _sans(20, FontWeight.w700, 1.0, tracking: -0.01, tabular: true);
  static TextStyle get figure => _sans(15, FontWeight.w600, 1.3, tabular: true);
  static TextStyle get figureLarge => _sans(18, FontWeight.w600, 1.25, tabular: true);

  /// Assembles a Material [TextTheme] from the scale above, so framework
  /// widgets (dialogs, tooltips, text selection) inherit the same two faces.
  static TextTheme textTheme() => TextTheme(
        displayLarge: pageTitle,
        displayMedium: titleLarge,
        headlineMedium: sectionTitle,
        titleLarge: name,
        titleMedium: _sans(15.5, FontWeight.w600, 1.35),
        bodyLarge: bodyLarge.copyWith(color: AppColors.inkSecondary),
        bodyMedium: body.copyWith(color: AppColors.inkSecondary),
        bodySmall: bodySmall.copyWith(color: AppColors.inkMuted),
        labelLarge: button,
        labelMedium: label,
        labelSmall: micro.copyWith(color: AppColors.inkMuted),
      );
}

/// Small helpers so widgets never hand-roll a colour variant of a shared style.
extension TextStyleRoles on TextStyle {
  TextStyle tone([Color? color]) => color == null ? this : copyWith(color: color);
  TextStyle get quiet => copyWith(color: AppColors.inkSecondary);
  TextStyle get quieter => copyWith(color: AppColors.inkMuted);
}

// ─────────────────────────────────────────────────────────────────────────────
// ThemeData
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AppTheme {
  static ThemeData light() {
    final TextTheme text = AppType.textTheme();
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.paperSunken,
      outline: AppColors.rule,
      outlineVariant: AppColors.rule,
      error: AppColors.accent,
      onError: AppColors.onAccent,
      shadow: const Color(0x1A17130E),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.paper,
      textTheme: text,
      // Paper, not a white card floating on grey.
      dividerTheme: const DividerThemeData(
        color: AppColors.rule,
        thickness: 1,
        space: Space.xl,
      ),
      iconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 20),
      // Text selection and the caret are part of the design; theme them.
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentWash,
        selectionHandleColor: AppColors.accent,
      ),
      // Native scrollbars restyled to the palette (craft floor: browser surfaces).
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(8),
        radius: const Radius.circular(Radii.pill),
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.dragged) ? AppColors.ruleStrong : AppColors.rule,
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.ink,
          borderRadius: Radii.softAll,
        ),
        textStyle: AppType.bodySmall.tone(AppColors.onAccent),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.paperRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.softAll),
        titleTextStyle: AppType.titleLarge,
        contentTextStyle: AppType.body.quiet,
      ),
      // Default page transition is 300 ms. The product moves in 200.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: _NoAnimationPageTransition(),
          TargetPlatform.linux: _NoAnimationPageTransition(),
          TargetPlatform.macOS: _NoAnimationPageTransition(),
          TargetPlatform.android: _NoAnimationPageTransition(),
          TargetPlatform.iOS: _NoAnimationPageTransition(),
        },
      ),
    );
  }
}

/// The real transition is the 200 ms travel in [TMTransitions.page]. This
/// builder exists only to stop Material stacking a second, slower one on top.
class _NoAnimationPageTransition extends PageTransitionsBuilder {
  const _NoAnimationPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Page-level motion. One authored move: content rises 10 px and fades, in
/// 200 ms, eased out, from an already-visible default.
abstract final class TMTransitions {
  static Route<T> page<T>(Widget child, {String? name}) => PageRouteBuilder<T>(
        settings: RouteSettings(name: name),
        transitionDuration: Motion.base,
        reverseTransitionDuration: Motion.fast,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (BuildContext context, Animation<double> a, _, Widget child) {
          final Animation<double> eased = CurvedAnimation(parent: a, curve: Motion.ease);
          return FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.018),
                end: Offset.zero,
              ).animate(eased),
              child: child,
            ),
          );
        },
      );
}
