// ─────────────────────────────────────────────────────────────────────────────
// How a person reads on their own page.
//
// The header is a surface that leans towards the pointer on a wide screen — a
// person is the one thing on this page you are deciding about, so their block
// is allowed to lift. Everything under it is grouped in the order a reader
// actually asks: where they are, who they are, what they teach, when they are
// free, then the smaller facts.
//
// The block deliberately holds no comparison: no score, no reasons, no shared
// week. Those belong to a pairing, not to a person. The one week it does draw is
// that person's own availability, which is a fact about them.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/location_map.dart';
import 'package:tutormatch/widgets/tilt_card.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class PersonSummary extends StatelessWidget {
  const PersonSummary({
    required this.person,
    this.photo,
    this.distanceKm,
    this.heroTag,
    this.showAvailability = true,
    super.key,
  });

  final Candidate person;

  /// The viewer's own picture, for the one case where this block is drawn for
  /// them. Null for everybody else — nobody else's picture exists.
  final Uint8List? photo;

  /// Distance from the viewer, when this person was opened from a ranked list.
  /// Null on the profile preview, and whenever either side hides their area.
  final double? distanceKm;

  /// Carries the avatar from the ranked card to this header. Shared by the
  /// match page and its list so the person does not become a second drawing.
  final Object? heroTag;

  /// The match page already draws the shared week below its reasons; the
  /// preview has no pairing to compare against, so it shows this week instead.
  final bool showAvailability;

  @override
  Widget build(BuildContext context) {
    final bool hasBio = person.bio.trim().isNotEmpty;
    final PublicPlace? place = person.publicPlace;

    final Widget header = TMEntry(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMAvatar(
                person.name,
                size: 92,
                photo: photo,
                tint: person.photoTint,
                heroTag: heroTag,
              ),
              const SizedBox(width: Space.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(person.name, style: AppType.pageTitle),
                    if (person.headline.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: Space.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child:
                            Text(person.headline, style: AppType.bodyLarge.quiet),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          PersonStatusLine(
            presence: person.presence,
            statusText: person.statusText,
          ),
          const SizedBox(height: Space.md),
          PersonFactLine(candidate: person),
        ],
      ),
    );

    final Widget head = TiltCard(maxTilt: 3, lift: 3, child: header);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        head,
        if (place != null) ...<Widget>[
          const SizedBox(height: Space.xxl),
          const TMRule(label: 'Approximate area'),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: LocationCard(
              place: place,
              distanceKm: distanceKm,
              height: 240,
            ),
          ),
        ],
        const SizedBox(height: Space.xxl),
        const TMRule(label: 'About'),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            hasBio
                ? '“${person.bio}”'
                : 'No bio yet — this person has not written one.',
            style: hasBio ? AppType.quote : AppType.bodyLarge.quieter,
          ),
        ),
        const SizedBox(height: Space.xxl),
        const TMRule(label: 'Subjects'),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final String subject in person.subjects)
              _SubjectTag(subject: subject),
            Text('·', style: AppType.bodySmall.quieter),
            Text(person.modeCopy, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
            Text('·', style: AppType.bodySmall.quieter),
            Text(person.rateCopy, style: AppType.figure),
            if (person.reviews > 0) ...<Widget>[
              Text('·', style: AppType.bodySmall.quieter),
              Text(
                '${person.rating} from ${person.reviews}',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ],
        ),
        if (showAvailability) ...<Widget>[
          const SizedBox(height: Space.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: AvailabilityGrid(
              overlap: person.availability,
              cellHeight: 16,
              partLabels: true,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'A normal week. Filled cells are hours they keep free.',
            style: AppType.bodySmall.quieter,
          ),
        ],
        const SizedBox(height: Space.xxl),
        PersonFacts(person: person),
        if (_hasColumns(person)) ...<Widget>[
          const SizedBox(height: Space.xxl),
          PersonColumns(candidate: person),
        ],
      ],
    );
  }

  static bool _hasColumns(Candidate person) =>
      person.styleLabel.trim().isNotEmpty ||
      person.styleTags.isNotEmpty ||
      person.credentials.isNotEmpty ||
      person.languages.isNotEmpty ||
      person.reviews > 0;
}

class _SubjectTag extends StatelessWidget {
  const _SubjectTag({required this.subject});
  final String subject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs + 1),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.ruleStrong),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        subject,
        style: AppType.bodySmall.tone(AppColors.inkSecondary),
      ),
    );
  }
}

/// The status line: whether they are around, and the one sentence they wrote
/// about what they are up to. Either half can stand alone; the pill always
/// renders, because "Available" is a fact about a person.
class PersonStatusLine extends StatelessWidget {
  const PersonStatusLine({
    required this.presence,
    required this.statusText,
    super.key,
  });

  final PresenceStatus presence;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        TMStatusPill(tone: presence.tone, label: presence.label, dense: true),
        if (statusText.trim().isNotEmpty)
          Text(
            statusText.trim(),
            style: AppType.bodySmall.tone(AppColors.inkSecondary),
          ),
      ],
    );
  }
}

/// The one-line summary: who they are on the market, what they teach or need,
/// how they meet and at what rate. The place itself lives in [LocationCard],
/// where it can be read properly.
class PersonFactLine extends StatelessWidget {
  const PersonFactLine({required this.candidate, super.key});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          candidate.role == Role.tutor ? 'Tutor' : 'Student',
          style: AppType.bodySmall.tone(AppColors.inkMuted),
        ),
        Text('·', style: AppType.bodySmall.quieter),
        Text(candidate.modeCopy, style: AppType.bodySmall.quieter),
        Text('·', style: AppType.bodySmall.quieter),
        Text(candidate.rateCopy, style: AppType.figure),
      ],
    );
  }
}

/// The rest of the profile: the facts a person page has room for and the
/// ranking does not read. A ruled grid of label-and-value columns, in the same
/// shape as [PersonColumns] below it. An empty fact is skipped rather than
/// shown as a blank — a missing birthdate is not a fact worth printing.
class PersonFacts extends StatelessWidget {
  const PersonFacts({required this.person, super.key});

  final Candidate person;

  @override
  Widget build(BuildContext context) {
    final DateTime? born = person.birthdate;
    final bool tutor = person.role == Role.tutor;

    final List<Widget> facts = <Widget>[
      if (born != null)
        _Column(
          label: 'Age',
          value: '${ageOn(born, DateTime.now())} years old',
        ),
      if (person.publicPlace != null)
        _Column(label: 'Lives in', value: person.publicPlace!.label),
      if (person.gender.trim().isNotEmpty && person.gender != Profile.noAnswer)
        _Column(label: 'Gender', value: person.gender.trim()),
      if (tutor && person.years != null)
        _Column(
          label: 'Experience',
          value: person.years == 1 ? '1 year' : '${person.years} years',
        ),
      if (!tutor && person.grade.trim().isNotEmpty)
        _Column(label: 'Year level', value: person.grade.trim()),
      if (!tutor && person.goal.trim().isNotEmpty)
        _Column(label: 'Working towards', value: person.goal.trim()),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMRule(label: 'The rest of the profile'),
        const SizedBox(height: Space.xl),
        Wrap(spacing: Space.xxxl, runSpacing: Space.xl, children: facts),
      ],
    );
  }
}

/// The four standing columns: how they work, what sits behind them, what they
/// speak, and what other people have said. Skipped column by column when there
/// is nothing to print, so the viewer's own preview — who has no reviews and
/// sometimes no credentials — reads as spare rather than broken.
class PersonColumns extends StatelessWidget {
  const PersonColumns({required this.candidate, super.key});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final bool tutor = candidate.role == Role.tutor;
    final String style = <String>[
      candidate.styleLabel,
      candidate.styleTags.join(' · '),
    ].where((String s) => s.trim().isNotEmpty).join('\n');

    final List<Widget> columns = <Widget>[
      if (style.trim().isNotEmpty)
        _Column(label: tutor ? 'Works this way' : 'Wants this', value: style),
      if (candidate.credentials.isNotEmpty)
        _Column(
          label: tutor ? 'Background' : 'Where they are',
          value: candidate.credentials.join('\n'),
        ),
      if (candidate.languages.isNotEmpty)
        _Column(label: 'Speaks', value: candidate.languages.join(' · ')),
      _Column(
        label: 'Reviews',
        value: candidate.reviews > 0
            ? '${candidate.rating} from ${candidate.reviews}'
            : 'No reviews yet — newer to the platform',
      ),
    ];

    return Wrap(spacing: Space.xxxl, runSpacing: Space.xl, children: columns);
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.md),
          TMMicroLabelText(label),
          const SizedBox(height: Space.sm),
          Text(value, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
        ],
      ),
    );
  }
}
