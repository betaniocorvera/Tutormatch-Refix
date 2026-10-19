// ─────────────────────────────────────────────────────────────────────────────
// The avatar.
//
// There are no photographs in this product and there will not be: everybody in
// it is sample data, and a stock face would be a lie with better lighting. So
// an avatar is the person's initials on a ruled square, drawn from the same
// paper and the same hairline as every row around it. It identifies a person;
// it does not decorate one.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';

class TMAvatar extends StatelessWidget {
  const TMAvatar(this.name, {this.size = 40, super.key});

  final String name;
  final double size;

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

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.paperSunken,
          border: Border.all(color: AppColors.ruleStrong),
          borderRadius: Radii.sharpAll,
        ),
        child: Text(
          initialsOf(name),
          maxLines: 1,
          style: AppType.micro
              .copyWith(fontSize: size * 0.3)
              .tone(AppColors.inkSecondary),
        ),
      ),
    );
  }
}
