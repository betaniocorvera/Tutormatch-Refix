// ─────────────────────────────────────────────────────────────────────────────
// TutorMatch visual system — "Signal, not noise".
//
// This is the ONLY file in the project that names a colour, a type size, a
// radius or a motion value. Widgets read from here. If a screen needs a value
// that is not here, the value belongs here first.
//
// THE IDEA: matching is a question of distance. The interface behaves like a
// quiet instrument for reading closeness — cool paper, deep ink, one green
// signal, one amber marker for the nearest match. Hairlines do the structural
// work; shadows are reserved for things that genuinely lift off the page.
//
// TYPE: Bricolage Grotesque speaks (headlines, names, the mark). Figtree does
// the work (body, labels, controls). IBM Plex Mono reads the instrument
// (scores, rates, times), with tabular figures so numbers do not shift.
//
// MOTION: state changes only, 150–250 ms; page changes 380 ms on an ease-out
// curve. No bounce, no spin, no ambient loops except the neighbour map's slow
// orbit. All of it collapses under MediaQuery.disableAnimations.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Roles in the product. Used for copy, routes and which side of a match you are.
enum Role { student, tutor }

// ─────────────────────────────────────────────────────────────────────────────
// Colour
// ─────────────────────────────────────────────────────────────────────────────

/// Every colour in the product, in one place, named by its job.
///
/// The ground is a cool, green-leaning paper rather than a warm cream: it lets
/// the deep teal sit as ink rather than decoration. Contrast notes are measured
/// against [paper] unless stated otherwise.
abstract final class AppColors {
  // Grounds — three depths of the same cool paper. No neutral greys.
  static const Color paper = Color(0xFFF3F5F2); // page ground
  static const Color paperRaised = Color(0xFFFBFCFA); // cards, inputs, sheets
  static const Color paperSunken = Color(0xFFE8ECE7); // wells, tracks, rails

  // Ink — green-black through to a quiet slate. 15.1:1 / 8.6:1 / 4.9:1.
  static const Color ink = Color(0xFF14211C);
  static const Color inkSecondary = Color(0xFF43514B);
  static const Color inkMuted = Color(0xFF5F6D66);
  static const Color onAccent = Color(0xFFF7FBF8); // on teal, ink, amber (dark text)

  // Text on the ink band. Measured against [ink]: 11.9:1, 7.1:1.
  // Tinted from the paper hue; grey on green-black reads dead.
  static const Color onInkQuiet = Color(0xFFC8D3CD);
  static const Color onInkFaint = Color(0xFF93A29A);

  // Rules — the system's primary depth device. Hairlines, never heavy boxes.
  static const Color rule = Color(0xFFDCE2DD);
  static const Color ruleStrong = Color(0xFFC3CCC6);

  // The primary signal. 8.4:1 on paper, 8.9:1 under onAccent text.
  //
  // The green has exactly four jobs, all "what needs your attention": the
  // primary action, the current selection, the match score, and the focused
  // field. It is never used for request status — accepted, pending and
  // declined have their own vocabulary below.
  static const Color accent = Color(0xFF0F5C4D);

  /// Form validation and blocked actions. A true error red, distinct from the
  /// green signal so a mistake never looks like an invitation to act.
  static const Color alert = Color(0xFFB23A2F);

  static const Color accentPressed = Color(0xFF0A463B);
  static const Color accentHover = Color(0xFF0C5143);
  static const Color accentWash = Color(0xFFE2EFE9); // tint for selected rows

  // The one amber. Reserved for the nearest match and the single highlight a
  // person should notice next — never for a primary button, never for status.
  // 8.9:1 against ink; ink on amber is 8.9:1.
  static const Color amber = Color(0xFFF2B544);
  static const Color amberWash = Color(0xFFFBF0D8);
  static const Color onAmber = Color(0xFF2B210B);

  /// The nearest match. An alias, not a second amber.
  static const Color topMatch = amber;
  static const Color topMatchWash = amberWash;

  // Status. Deliberately NOT the amber. A rejected request must not look like
  // the nearest match or a primary action.
  static const Color accepted = Color(0xFF2C6E54); // 5.9:1 on paper
  static const Color acceptedWash = Color(0xFFE4F1E9);
  static const Color pending = Color(0xFF8A5A11); // 5.3:1 on paper
  static const Color pendingWash = Color(0xFFFBF0D8);
  static const Color declined = Color(0xFF5F6D66); // = inkMuted, on purpose
  static const Color declinedWash = Color(0xFFE9EDE9);

  // Identity fills for initials avatars. These never mean accepted, pending or
  // declined. Initials sit on them in [onAccent], and each clears 6:1 against
  // it.
  static const Color avatarSlate = Color(0xFF3D5A5F);
  static const Color avatarPlum = Color(0xFF5B4656);
  static const Color avatarClay = Color(0xFF8A5A3B);
  static const Color avatarMoss = Color(0xFF4A6842);
  static const Color avatarSteel = Color(0xFF455A6B);

  // Focus. Ink, not green, so focus is unambiguous: the only 2 px ring in the
  // system, and it never competes with selection for meaning.
  static const Color focusRing = Color(0xFF14211C);

  // Scrims for media and modals. Green-black, never flat black.
  static const Color scrim = Color(0xE614211C);
  static const Color veil = Color(0x6614211C);

  /// Ink on a coloured fill. Luminance-aware so amber automatically takes ink
  /// and teal takes paper — a new fill cannot arrive without a readable label.
  static Color on(Color fill) =>
      fill.computeLuminance() > 0.45 ? ink : onAccent;

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

/// Corners. One soft radius for everything that holds content, one pill for
/// things you can choose, and a larger soft corner for floating surfaces.
abstract final class Radii {
  static const double sharp = 12; // cards, inputs, buttons — the default
  static const double soft = 20; // dialogs, sheets, floating panels
  static const double pill = 999; // tags, chips, status pills only
  static const BorderRadius sharpAll = BorderRadius.all(Radius.circular(sharp));
  static const BorderRadius softAll = BorderRadius.all(Radius.circular(soft));
}

/// Shadows are a last resort: hairline borders carry structure. The two here
/// are only for a surface that has physically lifted (tilt, drag, dialog).
abstract final class TMShadows {
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1414211C),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> lifted = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F14211C),
      blurRadius: 44,
      offset: Offset(0, 18),
    ),
  ];
}

/// Minimum hit area. Apple and Material both land on 44; we hold it everywhere,
/// including on compact chips by padding rather than by growing the chip.
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

  /// Below this, 3D is switched off entirely: a narrow phone should get a flat,
  /// legible map, not a squashed one.
  static const double flat3d = 360;
}

/// Motion. Short and purposeful: state changes only, never decoration.
///
/// `fast`/`base`/`slow` are the everyday vocabulary. The longer values are
/// reserved for authored moments: a page push, a staggered reveal, a card flip.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
  static const Duration page = Duration(milliseconds: 380);
  static const Duration reveal = Duration(milliseconds: 420);
  static const Duration flip = Duration(milliseconds: 500);
  static const Duration stagger = Duration(milliseconds: 55);
  static const Duration orbit = Duration(seconds: 60);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve emphasized = Cubic(0.22, 1, 0.36, 1);
  static const Curve settle = Cubic(0.2, 0.7, 0.2, 1);

  /// True when the platform asks for reduced motion. Every authored animation
  /// in the product must consult this and provide a still alternative.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Duration helper: zero under reduced motion, the authored value otherwise.
  static Duration respect(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

// ─────────────────────────────────────────────────────────────────────────────
// Type
// ─────────────────────────────────────────────────────────────────────────────

/// The type scale. Three families, one job each.
///
/// Bricolage Grotesque is the voice: titles, people's names, the wordmark.
/// Figtree is the hand: body, labels, controls, buttons. IBM Plex Mono is the
/// instrument: scores, rates, times and counts, always tabular. No serif is
/// used anywhere in the product.
///
/// All faces are bundled, so the first frame is set in the real type and the
/// layout never waits on a network round trip. Bricolage and Figtree are
/// variable cuts; their weight axes are set explicitly below.
abstract final class AppType {
  static const List<String> _fallback = <String>[
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle _display(
    double size,
    FontWeight weight,
    double height, {
    double tracking = 0,
    Color color = AppColors.ink,
    FontStyle style = FontStyle.normal,
  }) =>
      TextStyle(
        fontFamily: 'Bricolage Grotesque',
        fontSize: size,
        fontWeight: weight,
        fontVariations: <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
          const FontVariation('opsz', 28),
        ],
        height: height,
        letterSpacing: tracking,
        color: color,
        fontStyle: style,
        fontFamilyFallback: _fallback,
      );

  static TextStyle _body(
    double size,
    FontWeight weight,
    double height, {
    double tracking = 0,
    Color color = AppColors.ink,
    FontStyle style = FontStyle.normal,
  }) =>
      TextStyle(
        fontFamily: 'Figtree',
        fontSize: size,
        fontWeight: weight,
        fontVariations: <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
        ],
        height: height,
        letterSpacing: tracking,
        color: color,
        fontStyle: style,
        fontFamilyFallback: _fallback,
      );

  static TextStyle _mono(
    double size,
    FontWeight weight,
    double height, {
    double tracking = 0,
    Color color = AppColors.ink,
  }) =>
      TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color,
        fontFeatures: _tabular,
        fontFamilyFallback: const <String>['Consolas', 'monospace'],
      );

  // ── Display — Bricolage Grotesque ─────────────────────────────────────────
  /// Landing hero only. Fluid; see [heroAt].
  static TextStyle get hero => heroAt(375);

  static TextStyle heroAt(double width) => _display(
        width >= AppBreakpoints.wide
            ? 74
            : width >= AppBreakpoints.medium
                ? 58
                : width >= AppBreakpoints.compact
                    ? 46
                    : 36,
        FontWeight.w600,
        width >= AppBreakpoints.medium ? 0.98 : 1.02,
        tracking: width >= AppBreakpoints.wide
            ? -2.6
            : width >= AppBreakpoints.medium
                ? -2.0
                : -1.4,
      );

  /// The largest heading used inside the product: page titles.
  static TextStyle get pageTitle =>
      _display(34, FontWeight.w600, 1.08, tracking: -1.1);
  static TextStyle get titleLarge =>
      _display(26, FontWeight.w600, 1.12, tracking: -0.7);

  /// A person's name on a match entry — the subject of the row.
  static TextStyle get name =>
      _display(22, FontWeight.w600, 1.16, tracking: -0.5);
  static TextStyle get sectionTitle =>
      _display(18.5, FontWeight.w600, 1.26, tracking: -0.2);
  static TextStyle get quote =>
      _body(19, FontWeight.w400, 1.55, style: FontStyle.italic);
  static TextStyle get wordmark =>
      _display(21, FontWeight.w700, 1.0, tracking: -0.6);

  // ── Task — Figtree ────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => _body(16.5, FontWeight.w400, 1.62);
  static TextStyle get body => _body(15, FontWeight.w400, 1.6);
  static TextStyle get bodySmall => _body(13.5, FontWeight.w400, 1.55);
  static TextStyle get label => _body(14.5, FontWeight.w500, 1.35);
  static TextStyle get labelSmall => _body(13, FontWeight.w500, 1.35);
  static TextStyle get button =>
      _body(15, FontWeight.w600, 1.0, tracking: 0.1);

  /// Uppercase micro-label. Used for data captions and column headers — a
  /// label on an instrument, never an eyebrow above a heading.
  static TextStyle get micro =>
      _body(11, FontWeight.w600, 1.25, tracking: 1.1);

  /// Emoji are glyphs, not a typeface; this only fixes the size they are set
  /// at in the picker. The platform supplies the drawing.
  static TextStyle get emoji => _body(22, FontWeight.w400, 1.2);

  // ── Numerals — IBM Plex Mono, always tabular ──────────────────────────────
  /// The match score. The single largest number in the product.
  static TextStyle get score =>
      _mono(44, FontWeight.w500, 1.0, tracking: -1.8);
  static TextStyle get scoreSmall =>
      _mono(21, FontWeight.w500, 1.0, tracking: -0.6);
  static TextStyle get figure => _mono(14.5, FontWeight.w500, 1.3);
  static TextStyle get figureLarge => _mono(18, FontWeight.w500, 1.25);

  /// Assembles a Material [TextTheme] from the scale above, so framework
  /// widgets (dialogs, tooltips, text selection) inherit the same faces.
  static TextTheme textTheme() => TextTheme(
        displayLarge: pageTitle,
        displayMedium: titleLarge,
        headlineMedium: sectionTitle,
        titleLarge: name,
        titleMedium: _body(15.5, FontWeight.w600, 1.35),
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
      primaryContainer: AppColors.accentWash,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.amber,
      onSecondary: AppColors.onAmber,
      secondaryContainer: AppColors.amberWash,
      onSecondaryContainer: AppColors.ink,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerLowest: AppColors.paperRaised,
      surfaceContainerLow: AppColors.paperRaised,
      surfaceContainer: AppColors.paper,
      surfaceContainerHigh: AppColors.paperSunken,
      surfaceContainerHighest: AppColors.paperSunken,
      outline: AppColors.ruleStrong,
      outlineVariant: AppColors.rule,
      error: AppColors.alert,
      onError: AppColors.onAccent,
      shadow: const Color(0x1A14211C),
      scrim: AppColors.scrim,
    );

    const OutlineInputBorder fieldBorder = OutlineInputBorder(
      borderRadius: Radii.sharpAll,
      borderSide: BorderSide(color: AppColors.ruleStrong),
    );
    const OutlineInputBorder fieldFocus = OutlineInputBorder(
      borderRadius: Radii.sharpAll,
      borderSide: BorderSide(color: AppColors.ink, width: 2),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.paper,
      textTheme: text,
      visualDensity: VisualDensity.standard,
      // Paper, not a white card floating on grey.
      dividerTheme: const DividerThemeData(
        color: AppColors.rule,
        thickness: 1,
        space: Space.xl,
      ),
      iconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppType.titleLarge,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.paperRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.sharpAll,
          side: BorderSide(color: AppColors.rule),
        ),
      ),
      // Text selection and the caret are part of the design; theme them.
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentWash,
        selectionHandleColor: AppColors.accent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paperRaised,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldFocus,
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.sharpAll,
          borderSide: BorderSide(color: AppColors.alert),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.sharpAll,
          borderSide: BorderSide(color: AppColors.alert, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        hintStyle: TextStyle(color: AppColors.inkMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.paperSunken,
          disabledForegroundColor: AppColors.inkMuted,
          elevation: 0,
          minimumSize: const Size(0, Hit.min),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.sharpAll),
          textStyle: AppType.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ruleStrong),
          minimumSize: const Size(0, Hit.min),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.sharpAll),
          textStyle: AppType.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(0, Hit.min),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          shape: const RoundedRectangleBorder(borderRadius: Radii.sharpAll),
          textStyle: AppType.button,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.paperRaised,
        selectedColor: AppColors.accentWash,
        side: const BorderSide(color: AppColors.ruleStrong),
        shape: const StadiumBorder(),
        labelStyle: AppType.labelSmall.tone(AppColors.inkSecondary),
        secondaryLabelStyle: AppType.labelSmall.tone(AppColors.accent),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.xs,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.paperRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.softAll),
        titleTextStyle: AppType.titleLarge,
        contentTextStyle: AppType.body.quiet,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paperRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.soft)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.paperRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.sharpAll,
          side: const BorderSide(color: AppColors.rule),
        ),
        textStyle: AppType.body,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: AppType.bodySmall.tone(AppColors.onAccent),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.all(Space.lg),
        shape: const RoundedRectangleBorder(borderRadius: Radii.sharpAll),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.ink,
          borderRadius: Radii.sharpAll,
        ),
        textStyle: AppType.bodySmall.tone(AppColors.onAccent),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      // Native scrollbars restyled to the palette (craft floor: browser surfaces).
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(8),
        radius: const Radius.circular(Radii.pill),
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) => s.contains(WidgetState.dragged)
              ? AppColors.inkMuted
              : AppColors.ruleStrong,
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      // Default page transition is 300 ms. Our authored route move is 380 ms
      // and lives in [TMTransitions.page]; stop Material stacking a second one.
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

/// The real transition is the authored push in [TMTransitions.page]. This
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

/// Page-level motion. One authored move: the incoming page arrives from the
/// right on a shallow perspective axis (≈6°), settling flat in 380 ms, while
/// the page it covers steps back and turns away by half as much.
///
/// The rotation is applied to the page as a whole, never to body text or an
/// input, and it disappears completely when the platform asks for reduced
/// motion.
abstract final class TMTransitions {
  static Route<T> page<T>(Widget child, {String? name}) => PageRouteBuilder<T>(
        settings: RouteSettings(name: name),
        transitionDuration: Motion.page,
        reverseTransitionDuration: Motion.slow,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          if (Motion.reduced(context)) return child;

          final Animation<double> enter = CurvedAnimation(
            parent: animation,
            curve: Motion.emphasized,
            reverseCurve: Motion.ease,
          );
          final Animation<double> covered = CurvedAnimation(
            parent: secondaryAnimation,
            curve: Motion.emphasized,
            reverseCurve: Motion.ease,
          );

          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[enter, covered]),
            child: child,
            builder: (BuildContext context, Widget? child) {
              final double inT = enter.value;
              final double outT = covered.value;
              final double incoming = 1 - inT;
              final double width = MediaQuery.sizeOf(context).width;
              final double angle = incoming * 0.105 - outT * 0.055;
              final double dx = incoming * width * 0.045 - outT * width * 0.018;
              final double scale = 1 - outT * 0.012;

              final Matrix4 transform = Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translateByDouble(dx, 0, 0, 1)
                ..rotateY(angle)
                ..scaleByDouble(scale, scale, 1, 1);

              return Opacity(
                opacity: inT.clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: child,
                ),
              );
            },
          );
        },
      );
}
