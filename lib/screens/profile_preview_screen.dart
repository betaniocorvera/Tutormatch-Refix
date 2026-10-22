// ─────────────────────────────────────────────────────────────────────────────
// How others see you.
//
// The honest version of a preview: not a mock-up and not a screenshot with the
// wrong name on it, but the same [PersonSummary] block the match page draws,
// reading your profile through [profileAsCandidate]. If the two ever disagree
// it is because one of them changed and the other did not — and sharing the
// widget is what stops that happening.
//
// The card at the top has two faces because a profile really is read twice: once
// as written, and once as the first glance in a ranked list. It turns on its own
// vertical axis in 500 ms, or swaps instantly when the platform asks for reduced
// motion. Nothing here is editable, and nothing here is compared: no score, no
// shared week, no reasons. Those belong to a pairing.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/flip_card.dart';
import 'package:tutormatch/widgets/person_profile.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class ProfilePreviewScreen extends StatefulWidget {
  const ProfilePreviewScreen({super.key});

  @override
  State<ProfilePreviewScreen> createState() => _ProfilePreviewScreenState();
}

class _ProfilePreviewScreenState extends State<ProfilePreviewScreen> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Profile p = state.profile;
    final Candidate me = profileAsCandidate(p);
    final String other = p.role == Role.student ? 'a tutor' : 'a student';
    final bool compact = TMLayout.isCompact(context);
    final bool roomy = TMLayout.isRoomy(context);

    // ── The two faces ───────────────────────────────────────────────────────
    final Widget readings = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (compact) ...<Widget>[
            const TMMicroLabelText('The same profile, two readings'),
            const SizedBox(height: Space.xs),
            Text(
              _flipped
                  ? 'The first glance in a ranked list.'
                  : 'The page as you wrote it.',
              style: AppType.bodySmall.quieter,
            ),
            const SizedBox(height: Space.md),
            TMSegmented<bool>(
              options: const <bool>[false, true],
              selected: _flipped,
              onSelect: (bool v) => setState(() => _flipped = v),
              labelOf: (bool v) => v ? 'First glance' : 'As written',
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const TMMicroLabelText(
                        'The same profile, two readings',
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        _flipped
                            ? 'The first glance in a ranked list.'
                            : 'The page as you wrote it.',
                        style: AppType.bodySmall.quieter,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.lg),
                SizedBox(
                  width: 210,
                  child: TMSegmented<bool>(
                    options: const <bool>[false, true],
                    selected: _flipped,
                    onSelect: (bool v) => setState(() => _flipped = v),
                    labelOf: (bool v) => v ? 'First glance' : 'As written',
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.md),
          SizedBox(
            height: compact ? 392 : 364,
            child: FlipCard(
              flipped: _flipped,
              onTap: () => setState(() => _flipped = !_flipped),
              front: _PreviewFace(
                label: 'YOUR PROFILE, AS WRITTEN',
                child: _AsWritten(person: me, photo: state.photo),
              ),
              back: _PreviewFace(
                label: p.role == Role.student
                    ? 'WHAT A TUTOR SEES FIRST'
                    : 'WHAT A STUDENT SEES FIRST',
                child: _FirstGlance(person: me),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 2, right: Space.sm),
                child: TMIcon(
                  TMIconName.refresh,
                  size: 13,
                  color: AppColors.inkMuted,
                ),
              ),
              Expanded(
                child: Text(
                  'Use the switch or tap the card to turn it. The card is '
                  'the only place in the product with two faces — the choice '
                  'is yours, and it is remembered only while this page is open.',
                  style: AppType.bodySmall.quieter,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // On a wide screen the readings sit beside an explanation of what each
    // face is for, rather than leaving half the page blank. On a phone the
    // explanation follows the card.
    final Widget guidance = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Reading it twice'),
        const SizedBox(height: Space.sm),
        Text(
          'The front is the profile as a document. The back is the same person '
          'as a ranked list presents them: subjects, format, rate and the week '
          'they keep.',
          style: AppType.bodySmall.quiet,
        ),
        if (roomy) ...<Widget>[
          const SizedBox(height: Space.xl),
          const _ReadingNote(
            index: '01',
            title: 'As written',
            body: 'Avatar, status, headline, bio and area. Everything a person '
                'chose to put on their profile.',
          ),
          const SizedBox(height: Space.lg),
          const _ReadingNote(
            index: '02',
            title: 'First glance',
            body: 'What a tutor or student reads in a result row before opening '
                'anything: subjects, format, rate and availability.',
          ),
          const SizedBox(height: Space.xl),
        ] else
          const SizedBox(height: Space.xl),
        const TMInlineNote(
          tone: StatusTone.neutral,
          title: 'A preview, not another person',
          body: 'You are looking at your own answers. A real match page also '
              'carries the score, the shared hours and the reasons for the '
              'match — those belong to a pairing, so they are not here.',
        ),
      ],
    );

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
        TMNavItem(label: 'Profile', selected: true),
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
          if (roomy)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: readings),
                const SizedBox(width: Space.xxl),
                SizedBox(width: 318, child: guidance),
              ],
            )
          else ...<Widget>[
            readings,
            const SizedBox(height: Space.xl),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: guidance,
            ),
          ],
          const SizedBox(height: Space.xxl),
          Text('The full page', style: AppType.titleLarge),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: PersonSummary(person: me, photo: state.photo),
          ),
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}

/// One line of the reading key beside the card. A number, a name and a
/// sentence — not a legend with swatches, because there is no colour coding.
class _ReadingNote extends StatelessWidget {
  const _ReadingNote({
    required this.index,
    required this.title,
    required this.body,
  });

  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 28,
          child: Text(
            index,
            style: AppType.figure.tone(AppColors.accent),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: AppType.label),
              const SizedBox(height: Space.xxs),
              Text(body, style: AppType.bodySmall.quieter),
            ],
          ),
        ),
      ],
    );
  }
}

/// One face of the card. Same surface, padding and eyebrow, so the turn changes
/// the content rather than the furniture.
class _PreviewFace extends StatelessWidget {
  const _PreviewFace({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppType.micro.tone(AppColors.inkMuted)),
          const SizedBox(height: Space.lg),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AsWritten extends StatelessWidget {
  const _AsWritten({required this.person, required this.photo});

  final Candidate person;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final PublicPlace? place = person.publicPlace;
    final bool tutor = person.role == Role.tutor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TMAvatar(
              person.name,
              size: 82,
              photo: photo,
              tint: person.photoTint,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    person.name,
                    style: AppType.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  PersonStatusLine(
                    presence: person.presence,
                    statusText: person.statusText,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    person.headline,
                    style: AppType.bodySmall.quieter,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Expanded(
          child: Text(
            person.bio.trim().isEmpty
                ? 'No bio yet. A couple of lines about how you work is the '
                    'thing people read before they write to you.'
                : '“${person.bio}”',
            style: person.bio.trim().isEmpty
                ? AppType.body.quieter
                : AppType.quote,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (place != null)
              _Meta(
                icon: TMIconName.pin,
                text: place.label,
              ),
            _Meta(
              icon: tutor ? TMIconName.teach : TMIconName.graduation,
              text: tutor ? 'Tutor' : 'Student',
            ),
            _Meta(
              icon: TMIconName.wallet,
              text: person.rateCopy,
            ),
          ],
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final TMIconName icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TMIcon(icon, size: 13, color: AppColors.inkMuted),
        const SizedBox(width: Space.xs + 1),
        Text(
          text,
          style: AppType.bodySmall.tone(AppColors.inkSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _FirstGlance extends StatelessWidget {
  const _FirstGlance({required this.person});

  final Candidate person;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TMAvatar(
              person.name,
              size: 54,
              tint: person.photoTint,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    person.name,
                    style: AppType.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    person.headline,
                    style: AppType.body.quieter,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final String subject in person.subjects.take(4))
              _SubjectChip(subject),
            Text('·', style: AppType.bodySmall.quieter),
            Text(person.modeCopy, style: AppType.bodySmall.quieter),
            Text('·', style: AppType.bodySmall.quieter),
            Text(person.rateCopy, style: AppType.figure),
          ],
        ),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.md),
        const TMMicroLabelText('The hours they keep free'),
        const SizedBox(height: Space.sm),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AvailabilityGrid(
                overlap: person.availability,
                cellHeight: 15,
                partLabels: false,
              ),
            ),
          ),
        ),
        Row(
          children: <Widget>[
            const TMIcon(
              TMIconName.sparkle,
              size: 13,
              color: AppColors.inkMuted,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                'A ranked card adds the score and the three reasons. This is the '
                'person on their own.',
                style: AppType.bodySmall.quieter,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ruleStrong),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: AppType.micro.copyWith(fontSize: 10).tone(AppColors.inkSecondary),
      ),
    );
  }
}
