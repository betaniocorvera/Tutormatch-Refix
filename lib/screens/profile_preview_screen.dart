// ─────────────────────────────────────────────────────────────────────────────
// How others see you.
//
// The honest version of a preview: not a mock-up and not a screenshot with the
// wrong name on it, but the same [PersonSummary] block the match page draws,
// reading your profile through [profileAsCandidate]. If the two ever disagree
// it is because one of them changed and the other did not — and sharing the
// widget is what stops that happening.
//
// Nothing here is editable, and nothing here is compared: no score, no shared
// week, no reasons. Those belong to a pairing, and a person on their own is not
// a pairing.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/person_profile.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class ProfilePreviewScreen extends StatelessWidget {
  const ProfilePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Profile p = state.profile;
    final Candidate me = profileAsCandidate(p);
    final String other = p.role == Role.student ? 'a tutor' : 'a student';

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'Matches',
          onTap: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        TMNavItem(
          label: 'Requests',
          onTap: () => Navigator.of(context).pushNamed(Routes.requests),
        ),
        TMNavItem(
          label: 'Messages',
          onTap: () => Navigator.of(context).pushNamed(Routes.messages),
        ),
        TMNavItem(
          label: 'Profile',
          onTap: () => Navigator.of(context).pushNamed(Routes.profile),
        ),
      ],
      navTrailing: TMButton(
        label: 'Back to your profile',
        variant: TMButtonVariant.quiet,
        icon: TMIconName.arrowLeft,
        iconLeading: true,
        minHeight: Hit.min,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: Space.xxl),
          Text('How others see you', style: AppType.pageTitle),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'This is your profile exactly as $other opens it: the same block '
              'the match page draws, reading the same fields you just edited. '
              'Nothing below is editable here — go back to your profile to '
              'change any of it.',
              style: AppType.bodyLarge.quiet,
            ),
          ),
          const SizedBox(height: Space.xl),
          const TMInlineNote(
            tone: StatusTone.neutral,
            title: 'A preview, not another person',
            body: 'You are looking at your own answers. A real match page also '
                'carries the score, the shared hours and the reasons for the '
                'match — those belong to a pairing, so they are not here.',
          ),
          const SizedBox(height: Space.xxl),
          PersonSummary(person: me, photo: state.photo),
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}
