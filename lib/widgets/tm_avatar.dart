// ─────────────────────────────────────────────────────────────────────────────
// The avatar.
//
// There are no stock faces in this product: a stock face would be a lie with
// better lighting. People without a picture are their initials on a flat dye,
// rounded like a card rather than circled like a social profile.
//
// The dye is deterministic from the name, so the same person is the same colour
// on the map, in the list and on their own page without storing anything. A
// caller may supply an explicit tint; otherwise one is assigned.
//
// A real photograph comes from the API and arrives as bytes in app state. It
// falls back to the initials when no picture exists or the picture is removed.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class TMAvatar extends StatelessWidget {
  const TMAvatar(
    this.name, {
    this.size = 40,
    this.photo,
    this.tint,
    this.heroTag,
    super.key,
  });

  final String name;
  final double size;

  /// The real picture, when the API has one. Bytes rather than a URL because
  /// the media endpoint is private and needs the bearer token.
  final Uint8List? photo;

  /// An optional flat dye. Null means the deterministic dye below.
  final Color? tint;

  /// Set to the same tag on a list row and a detail header to carry the avatar
  /// between routes. Callers are responsible for uniqueness within one route.
  final Object? heroTag;

  /// Two letters, taken from the start of the first two words. Public because
  /// the chat uses it for a run of messages without repeating the full name.
  static String initialsOf(String name) {
    final List<String> parts = name
        .trim()
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final String word = parts.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static const List<Color> _dyes = <Color>[
    AppColors.accent,
    AppColors.avatarSlate,
    AppColors.avatarClay,
    AppColors.avatarMoss,
    AppColors.avatarPlum,
    AppColors.avatarSteel,
  ];

  /// A stable dye for a name. Not a status, not a rank: identity only.
  static Color dyeFor(String name) {
    int hash = 7;
    for (final int unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _dyes[hash % _dyes.length];
  }

  double get _radius => (size * 0.3).clamp(6.0, 22.0);

  Widget _fallback() {
    final Color dye = tint ?? dyeFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dye,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: AppColors.onAccent.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        initialsOf(name),
        maxLines: 1,
        style: AppType.label.copyWith(
          fontSize: (size * 0.31).clamp(9.0, 22.0),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppColors.onAccent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Decorative: every avatar in the product sits beside the person's name or
    // inside a control that announces itself.
    Widget content;
    if (photo == null) {
      content = ExcludeSemantics(child: _fallback());
    } else {
      content = ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Image.memory(
            photo!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Bytes that turn out not to be an image are not worth a broken
            // screen: the initials are right there behind them.
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) =>
                _fallback(),
          ),
        ),
      );
    }

    if (heroTag == null) return content;
    return Hero(tag: heroTag!, child: content);
  }
}
