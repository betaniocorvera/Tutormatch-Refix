// ─────────────────────────────────────────────────────────────────────────────
// Privacy Notice.
//
// The page the registration consent points at. It is deliberately plain: what
// is collected, why, who can see it, how long it is kept, and the rights RA
// 10173 gives the person reading it. The version must match
// `backend/app/privacy.py`.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  static const String version = '2026-10-v1';

  @override
  Widget build(BuildContext context) {
    return TMPage(
      maxWidth: 820,
      navTrailing: TMButton(
        label: 'Back',
        variant: TMButtonVariant.quiet,
        icon: TMIconName.arrowLeft,
        iconLeading: true,
        minHeight: Hit.min,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const TMMicroLabel('Privacy Notice'),
            const SizedBox(height: Space.md),
            Text(
              'Your data, and what you can do about it.',
              style: AppType.pageTitle,
            ),
            const SizedBox(height: Space.md),
            Text(
              'Version $version · Data Privacy Act of 2012 (RA 10173)',
              style: AppType.bodySmall.quieter,
            ),
            const SizedBox(height: Space.xl),
            Text(
              'TutorMatch is a matching service. We ask for the information '
              'needed to create an account, show a useful profile, and keep '
              'the exchange safe. We do not sell personal data, and we do not '
              'show your password, email address, phone number, birthdate, '
              'security answers, or consent record on a public profile.',
              style: AppType.bodyLarge.tone(AppColors.inkSecondary),
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'What we collect',
              paragraphs: <String>[
                'Account details: your full name, email address, role '
                    '(student or tutor), and a password. The password is '
                    'hashed with Argon2id; we never store or display the '
                    'plain text.',
                'Profile details: the subjects you study or teach, your area, '
                    'an optional phone number, a photo, a short description, '
                    'your preferred teaching style, availability, goal, and '
                    'budget. You choose how much of your area other people '
                    'see.',
                'Account-recovery details: three security questions and their '
                    'answers. Answers are trimmed, lower-cased, and stored '
                    'only as Argon2id hashes. They are never returned by an '
                    'endpoint or written to logs.',
                'Activity: requests, messages, and the timestamps needed to '
                    'deliver them. Uploaded photos are re-encoded and stored '
                    'by the server.',
                'Consent record: the fact that you agreed, the time you '
                    'agreed, and the version of this notice you agreed to '
                    '(currently $version).',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'Why we collect it',
              paragraphs: <String>[
                'To create and secure your account, including checking your '
                    'identity when you ask for help signing back in.',
                'To recommend tutors or students by subject, area, style, '
                    'availability, goal, and budget, and to calculate distance '
                    'when you have chosen an area.',
                'To deliver requests and messages, show a profile you control, '
                    'and keep the service usable and safe.',
                'To meet legal obligations and to record that you consented '
                    'to this version of the notice.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'Who can see it',
              paragraphs: <String>[
                'People signed in to TutorMatch can see the public part of '
                    'your profile: your name, role, subjects, the area you '
                    'chose to show, photo, description, style, availability, '
                    'goal, and budget. Your exact area is shown only if you '
                    'choose that setting; otherwise only the city is shown, or '
                    'nothing.',
                'Your email address, phone number, birthdate, password, '
                    'security questions and answers, and consent record are '
                    'not part of the public profile.',
                'The site operator can access the server and its local data '
                    'store to run, debug, and secure the service. This demo '
                    'has no third-party analytics or advertising processors.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'How long we keep it',
              paragraphs: <String>[
                'We keep account and profile data while your account exists. '
                    'Messages and requests are kept while they are needed to '
                    'provide the service and resolve disputes.',
                'This demo stores data in memory. A server restart clears it '
                    'unless snapshot persistence is enabled, in which case the '
                    'snapshot stays in the server’s local data directory until '
                    'it is removed.',
                'When you ask us to delete your account, we remove the account '
                    'and its profile data. We may keep the minimum needed to '
                    'show that a deletion happened or to meet a legal '
                    'obligation.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'Your rights',
              paragraphs: <String>[
                'Under RA 10173 you can ask to access the personal data we '
                    'hold about you, correct anything inaccurate, and ask us '
                    'to delete it. You can also object to processing, ask for '
                    'a portable copy, and complain to the National Privacy '
                    'Commission.',
                'To use a right, contact the site operator at '
                    'privacy@tutormatch.dev. We may need to verify that the '
                    'request comes from the account holder before we act.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'How we protect it',
              paragraphs: <String>[
                'Passwords and security answers are hashed with Argon2id. '
                    'Sessions use short-lived access tokens and refresh tokens. '
                    'The server validates names, phone numbers, subjects, '
                    'areas, and security questions before storing them, and '
                    'validation errors do not echo passwords or answers back.',
                'No system is perfectly secure. If you think your account has '
                    'been compromised, contact the site operator immediately.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            const _PrivacySection(
              title: 'Consent and changes',
              paragraphs: <String>[
                'Registration asks you to tick a box confirming that you have '
                    'read this notice. The server records the consent flag, '
                    'the timestamp, and the policy version. If this notice '
                    'changes in a way that matters, we will publish a new '
                    'version and ask for consent again.',
              ],
            ),
            const SizedBox(height: Space.xxl),
            Container(
              padding: const EdgeInsets.all(Space.xl),
              decoration: BoxDecoration(
                color: AppColors.paperRaised,
                border: Border.all(color: AppColors.rule),
                borderRadius: Radii.sharpAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const TMIcon(
                    TMIconName.book,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'This notice is version $version. The consent you give '
                      'during registration applies to this version.',
                      style: AppType.bodySmall.tone(AppColors.inkSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: AppType.sectionTitle),
        const SizedBox(height: Space.md),
        for (int i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 9),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    paragraphs[i],
                    style: AppType.body.tone(AppColors.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
