// ─────────────────────────────────────────────────────────────────────────────
// The icon set.
//
// Phosphor, not Material and never an emoji: one authored family with a
// consistent optical weight, a 24-unit grid and rounded terminals that sit well
// beside the product's 12 px corners. The enum is the public API — screens name
// a job ("sliders", "pin"), never a package glyph — so the drawing can change
// behind it without touching a screen.
//
// Weight is chosen once: the regular cut for normal UI, the bold cut when a
// caller asks for 2 px or more (the small marks inside status pills). Icons are
// decorative here; the text beside them carries the meaning.
//
// The glyphs come from the Phosphor font bundled in `assets/fonts`, drawn with
// Flutter's own Icon widget. The official package's Dart wrapper subclasses
// IconData, which Flutter 3.44 made final; the font asset is version-independent,
// so the codepoints are declared here as plain IconData. Same font, same cuts.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:tutormatch/theme/app_theme.dart';

enum TMIconName {
  arrowRight,
  arrowLeft,
  check,
  cross,
  dash,
  chevronDown,
  menu,
  close,
  sliders,
  pin,
  map,

  // The chat.
  phone,
  phoneDown,
  video,
  videoOff,
  cameraFlip,
  mic,
  micOff,
  image,
  calendar,
  emoji,
  play,
  pause,
  plus,
  speaker,
  speakerOff,

  // Navigation and matching.
  search,
  target,
  chat,
  user,
  send,
  sparkle,
  clock,
  warning,
  refresh,
  star,
  dots,
  compass,
  eye,
  eyeOff,
  book,
  graduation,
  teach,
  wallet,
  inbox,
  chats,
  briefcase,
}

class TMIcon extends StatelessWidget {
  const TMIcon(
    this.name, {
    this.size = 18,
    this.color = AppColors.ink,
    this.strokeWidth = 1.5,
    super.key,
  });

  final TMIconName name;
  final double size;
  final Color color;

  /// Kept for API compatibility. Phosphor's cuts are fixed at 16/24 units; a
  /// value of 2 or more selects the bold cut, everything else the regular one.
  final double strokeWidth;

  static const Map<TMIconName, (IconData regular, IconData bold)> _glyphs =
      <TMIconName, (IconData, IconData)>{
    TMIconName.arrowRight: (
      IconData(0xe06c, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe06c, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.arrowLeft: (
      IconData(0xe058, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe058, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.check: (
      IconData(0xe182, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe182, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.cross: (
      IconData(0xe4f6, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4f6, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.dash: (
      IconData(0xe32a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe32a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.chevronDown: (
      IconData(0xe136, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe136, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.menu: (
      IconData(0xe2f0, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe2f0, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.close: (
      IconData(0xe4f6, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4f6, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.sliders: (
      IconData(0xe434, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe434, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.pin: (
      IconData(0xe316, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe316, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.map: (
      IconData(0xe31a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe31a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.phone: (
      IconData(0xe3b8, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe3b8, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.phoneDown: (
      IconData(0xe3bc, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe3bc, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.video: (
      IconData(0xe4da, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4da, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.videoOff: (
      IconData(0xe4dc, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4dc, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.cameraFlip: (
      IconData(0xe7a4, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe7a4, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.mic: (
      IconData(0xe326, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe326, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.micOff: (
      IconData(0xe328, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe328, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.image: (
      IconData(0xe2ca, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe2ca, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.calendar: (
      IconData(0xe10a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe10a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.emoji: (
      IconData(0xe436, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe436, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.play: (
      IconData(0xe3d0, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe3d0, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.pause: (
      IconData(0xe39e, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe39e, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.plus: (
      IconData(0xe3d4, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe3d4, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.speaker: (
      IconData(0xe44a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe44a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.speakerOff: (
      IconData(0xe45a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe45a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.search: (
      IconData(0xe30c, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe30c, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.target: (
      IconData(0xe47c, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe47c, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.chat: (
      IconData(0xe168, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe168, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.user: (
      IconData(0xe4c4, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4c4, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.send: (
      IconData(0xe398, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe398, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.sparkle: (
      IconData(0xe6a2, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe6a2, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.clock: (
      IconData(0xe19a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe19a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.warning: (
      IconData(0xe4e2, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4e2, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.refresh: (
      IconData(0xe094, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe094, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.star: (
      IconData(0xe46a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe46a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.dots: (
      IconData(0xe1fe, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe1fe, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.compass: (
      IconData(0xe1c8, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe1c8, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.eye: (
      IconData(0xe220, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe220, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.eyeOff: (
      IconData(0xe224, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe224, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.book: (
      IconData(0xe0e6, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe0e6, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.graduation: (
      IconData(0xe62c, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe62c, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.teach: (
      IconData(0xe600, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe600, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.wallet: (
      IconData(0xe68a, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe68a, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.inbox: (
      IconData(0xe4aa, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe4aa, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.chats: (
      IconData(0xe17c, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe17c, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
    TMIconName.briefcase: (
      IconData(0xe0ee, fontFamily: 'PhosphorRegular', matchTextDirection: true),
      IconData(0xe0ee, fontFamily: 'PhosphorBold', matchTextDirection: true),
    ),
  };

  IconData get _glyph {
    final (IconData regular, IconData bold) = _glyphs[name]!;
    return strokeWidth >= 2 ? bold : regular;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Icon(
          _glyph,
          size: size,
          color: color,
        ),
      ),
    );
  }
}

/// An icon that turns with a short, purposeful ease — used by the expanding
/// sections, where the rotation *is* the state.
class TMRotatingIcon extends StatelessWidget {
  const TMRotatingIcon(
    this.name, {
    required this.turns,
    this.size = 18,
    this.color = AppColors.ink,
    super.key,
  });

  final TMIconName name;
  final double turns;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: turns,
      duration: Motion.respect(context, Motion.base),
      curve: Motion.ease,
      child: TMIcon(name, size: size, color: color),
    );
  }
}
