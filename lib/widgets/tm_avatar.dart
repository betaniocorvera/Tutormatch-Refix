// ─────────────────────────────────────────────────────────────────────────────
// The avatar.
//
// There are no photographs of anybody else in this product and there will not
// be: everybody in the pool is sample data, and a stock face would be a lie
// with better lighting. So most people here are their initials on a ruled
// square, drawn from the same paper and the same hairline as every row around
// them. Two or three of them wear a flat dye instead — the stand-in for "has a
// picture" that costs no stranger anything.
//
// The one real photograph in the product is the picture the person using it
// picked from their own device. It arrives as bytes from app state, is never
// uploaded, and falls back to the initials the moment it is removed — so this
// one widget draws every avatar in the app, and nothing else has to know which
// kind it is.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class TMAvatar extends StatelessWidget {
  const TMAvatar(this.name, {this.size = 40, this.photo, this.tint, super.key});

  final String name;
  final double size;

  /// The real picture, when the person using the app has set one. Bytes rather
  /// than a path, because it lives in memory for as long as the tab does.
  final Uint8List? photo;

  /// The flat dye that stands in for a picture on a few of the sample people.
  /// Null — which is almost everybody — means initials on sunken paper.
  final Color? tint;

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

  /// The fallback: initials on paper, or on the dye when there is one. Drawn at
  /// the same weight as the rules around it — this identifies a person, it does
  /// not decorate one.
  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint ?? AppColors.paperSunken,
        border: Border.all(color: tint ?? AppColors.ruleStrong),
        borderRadius: Radii.sharpAll,
      ),
      child: Text(
        initialsOf(name),
        maxLines: 1,
        style: AppType.micro
            .copyWith(fontSize: size * 0.3)
            .tone(tint == null ? AppColors.inkSecondary : AppColors.onAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Decorative: every avatar in the product sits beside the person's name or
    // inside a control that announces itself.
    if (photo == null) return ExcludeSemantics(child: _fallback());

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: Radii.sharpAll,
        child: Image.memory(
          photo!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // Bytes that turn out not to be an image are not worth a broken
          // screen: the initials are right there behind them.
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              _fallback(),
        ),
      ),
    );
  }
}
