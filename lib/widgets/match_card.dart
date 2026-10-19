// ─────────────────────────────────────────────────────────────────────────────
// THE MATCH RESULT CARD — the signature component, and the thing this whole
// interface exists to show well.
//
// Every design decision in it is a decision about reading order:
//
//   1. Who, and how well. The rank sits in the corner as a figure, the name is
//      in the serif because a person is the subject of the entry, and the tier
//      word ("Strong match") appears before any number, because a word is
//      processed faster than a value.
//   2. The score as a measurement. The ruler is the second largest thing on the
//      card and it is countable: ten graduations, a filled fraction, and a
//      cursor on the exact value. See match_score_scale.dart.
//   3. The three reasons, in full, without a click. This is the requirement the
//      card is really built around — if a person has to open anything to find
//      out why, the score is a black box and the product has failed. The three
//      shown are always the three highest-weighted dimensions for this pairing,
//      so they change with the profile rather than being decoration.
//   4. The week grid, because "we agree in principle" is worth nothing until you
//      know when. Filled cells only: this card answers "when are we both free",
//      and the profile screen answers "who is free when".
//
// The top-ranked entry is given a deliberate lead treatment — an accent rule
// across its top edge and a larger score — so a list of sixteen entries reads as
// a ranking rather than a wall.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/match_score_scale.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class MatchResultCard extends StatelessWidget {
  const MatchResultCard({
    required this.result,
    required this.rank,
    this.lead = false,
    this.fromProfile = false,
    this.profileSummary,
    this.onOpen,
    this.onQuickRequest,
    this.requested = false,
    this.total = 0,
    super.key,
  });

  final MatchResult result;
  final int rank;
  final bool lead;

  /// Shows the "based on your profile" tag. True for anyone who has just
  /// answered the onboarding questions, because their answers are the thing
  /// producing this order and it would be dishonest to hide that.
  final bool fromProfile;
  final String? profileSummary;

  final VoidCallback? onOpen;
  final VoidCallback? onQuickRequest;
  final bool requested;

  /// How many candidates were ranked in total, so "01" reads as "first of
  /// sixteen" rather than as a number floating in a corner.
  final int total;

  @override
  Widget build(BuildContext context) {
    final Candidate c = result.candidate;
    final String? when = describeOverlap(result.score.overlap);

    final Widget identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Header(
          rank: rank,
          total: total,
          tier: result.tier,
          lead: lead,
          fromProfile: fromProfile,
          profileSummary: profileSummary,
        ),
        SizedBox(height: lead ? Space.lg : Space.md),
        Text(c.name, style: lead ? AppType.titleLarge : AppType.name),
        const SizedBox(height: Space.xs + 2),
        SizedBox(
          width: 460,
          child: Text(c.headline, style: AppType.body.quiet),
        ),
        const SizedBox(height: Space.lg),
        _Facts(candidate: c),
      ],
    );

    // Whether the card splits into two columns is decided by the card's own
    // width, not the window's: the same card sits in a full-width list and in a
    // narrow hero column, and it has to hold in both.
    Widget scoreBlock(bool wide) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const TMRule(label: 'Match'),
            const SizedBox(height: Space.lg),
            MatchScorePanel(
              score: result.score.total,
              large: lead,
              showMeaning: wide,
            ),
          ],
        );

    final Widget reasons = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMRule(label: 'Why this match'),
        const SizedBox(height: Space.lg),
        for (int i = 0; i < result.reasons.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: Space.lg),
          _Reason(index: i + 1, note: result.reasons[i]),
        ],
      ],
    );

    final Widget week = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMRule(label: "When you're both free"),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: AvailabilityGrid(
            overlap: result.score.overlap,
            cellHeight: lead ? 17 : 15,
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: <Widget>[
            TMIcon(
              when == null ? TMIconName.dash : TMIconName.check,
              size: 15,
              color: when == null ? AppColors.inkMuted : AppColors.accepted,
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                when == null
                    ? 'No overlapping hours in a normal week'
                    : '${result.score.overlapSlots} blocks a week — $when',
                style: AppType.bodySmall.tone(
                  when == null ? AppColors.inkMuted : AppColors.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return TMEntry(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sharp - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The lead entry is marked with a rule across its top edge. One
            // line, three pixels, no shadow — it is enough to establish rank.
            if (lead) const SizedBox(height: 3, child: ColoredBox(color: AppColors.accent)),
            Padding(
              padding: EdgeInsets.all(lead ? Space.xxl : Space.xl),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 620;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 3, child: identity),
                            const SizedBox(width: Space.xxl),
                            Expanded(flex: 2, child: scoreBlock(true)),
                          ],
                        )
                      else ...<Widget>[
                        identity,
                        SizedBox(height: Space.xl),
                        scoreBlock(false),
                      ],
                      SizedBox(height: Space.xxl),
                      reasons,
                      SizedBox(height: Space.xxl),
                      week,
                      SizedBox(height: Space.xl),
                      const Divider(height: 1),
                      const SizedBox(height: Space.lg),
                      _Actions(
                        lead: lead,
                        requested: requested,
                        tier: result.tier,
                        onOpen: onOpen,
                        onQuickRequest: onQuickRequest,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.rank,
    required this.total,
    required this.tier,
    required this.lead,
    required this.fromProfile,
    required this.profileSummary,
  });

  final int rank;
  final int total;
  final MatchTier tier;
  final bool lead;
  final bool fromProfile;
  final String? profileSummary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // On a phone the three things that belong in this corner do not fit on
        // one line at a legible size, so the profile tag drops to its own line
        // rather than the row overflowing. Rank and tier stay together: they are
        // the two answers to "who is this and how good".
        final bool stack = constraints.maxWidth < 400;

        // Rank and tier on one line, pushed apart — but if a narrow card or a
        // long tier word means they cannot share a line, the tier drops below
        // rather than being clipped. Wrap gives that for free; a Row with a
        // Spacer would stripe.
        final Widget rankAndPill = Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.sm,
          children: <Widget>[
            _RankFigure(rank: rank, total: total, accent: lead),
            TMStatusPill(tone: tier.tone, label: tier.label, dense: !lead),
          ],
        );

        if (!fromProfile) return rankAndPill;

        final Widget tag = _ProfileTag(summary: profileSummary);

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              rankAndPill,
              const SizedBox(height: Space.md),
              tag,
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: _RankFigure(rank: rank, total: total, accent: lead)),
            Flexible(child: tag),
            const SizedBox(width: Space.sm),
            TMStatusPill(tone: tier.tone, label: tier.label, dense: !lead),
          ],
        );
      },
    );
  }
}

/// Rank as a figure, tabular so 02 and 10 align, with the size of the list
/// beside it so the number reads as "first of sixteen".
class _RankFigure extends StatelessWidget {
  const _RankFigure({required this.rank, required this.total, required this.accent});

  final int rank;
  final int total;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          rank.toString().padLeft(2, '0'),
          style: AppType.figureLarge.tone(accent ? AppColors.accent : AppColors.inkMuted),
        ),
        if (total > 0) ...<Widget>[
          const SizedBox(width: Space.xs + 1),
          Flexible(
            child: Text(
              'of $total',
              style: AppType.micro.tone(AppColors.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// The one honest label for a first-run list: it says the order came from the
/// answers, and it says which answers, on hover and to a screen reader.
class _ProfileTag extends StatelessWidget {
  const _ProfileTag({required this.summary});

  final String? summary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: summary == null
          ? 'Ranked using the answers you just gave.'
          : 'Ranked using: $summary',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.accent),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const TMIcon(TMIconName.sliders, size: 12, color: AppColors.accent),
            const SizedBox(width: Space.xs + 1),
            Flexible(
              child: Text(
                'Based on your profile',
                style: AppType.micro.copyWith(fontSize: 10).tone(AppColors.accent),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subjects, format, rate and the review line. Facts, set as facts.
class _Facts extends StatelessWidget {
  const _Facts({required this.candidate});
  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final String subject in candidate.subjects)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 1,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.ruleStrong),
                  borderRadius: BorderRadius.circular(Radii.sharp - 1),
                ),
                child: Text(subject, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
              ),
            _Dot(),
            Text(candidate.modeCopy, style: AppType.bodySmall.quieter),
            _Dot(),
            Text(candidate.rateCopy, style: AppType.figure.tone(AppColors.ink)),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          candidate.reviews > 0
              ? '${candidate.rating} from ${candidate.reviews} reviews · ${candidate.location}'
              : candidate.location,
          style: AppType.bodySmall.quieter,
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.xs),
        child: Text('·', style: TextStyle(color: AppColors.inkMuted)),
      );
}

/// One reason: the signal in ink, the explanation quieter underneath, numbered
/// so "three reasons" is visibly three and not a paragraph.
class _Reason extends StatelessWidget {
  const _Reason({required this.index, required this.note});
  final int index;
  final FitNote note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 22,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$index',
              style: AppType.micro.copyWith(fontSize: 11).tone(AppColors.accent),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                note.signal,
                style: AppType.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Space.xs),
              SizedBox(
                width: 560,
                child: Text(note.detail, style: AppType.bodySmall.quieter),
              ),
              const SizedBox(height: Space.xs),
              Text(note.dimension.label.toUpperCase(), style: AppType.micro.tone(AppColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.lead,
    required this.requested,
    required this.tier,
    required this.onOpen,
    required this.onQuickRequest,
  });

  final bool lead;
  final bool requested;
  final MatchTier tier;
  final VoidCallback? onOpen;
  final VoidCallback? onQuickRequest;

  @override
  Widget build(BuildContext context) {
    if (requested) {
      return Row(
        children: <Widget>[
          const TMStatusPill(tone: StatusTone.pending, label: 'Requested'),
          const SizedBox(width: Space.md),
          Flexible(
            child: Text(
              'You have already asked. You will hear back here.',
              style: AppType.bodySmall.quieter,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: Space.md,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        TMButton(
          label: lead ? 'Open the full profile' : 'Open profile',
          variant: lead ? TMButtonVariant.primary : TMButtonVariant.secondary,
          icon: TMIconName.arrowRight,
          minHeight: Hit.min,
          onPressed: onOpen,
        ),
        if (lead)
          TMTextLink(
            label: 'or send a request straight away',
            onTap: onQuickRequest,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────

/// A skeleton that keeps the card's exact proportions, so nothing jumps when the
/// real content lands. Static blocks with one sweeping rule above them: no
/// shimmer, no spinner over the content.
class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({this.rank = 1, super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  rank.toString().padLeft(2, '0'),
                  style: AppType.figureLarge.tone(AppColors.rule),
                ),
                const Spacer(),
                const _Block(width: 96, height: 20, radius: Radii.pill),
              ],
            ),
            const SizedBox(height: Space.lg),
            const _Block(width: 190, height: 20),
            const SizedBox(height: Space.md),
            const _Block(width: 280, height: 12),
            const SizedBox(height: Space.xl),
            const _Block(width: 260, height: 14, radius: 2),
            const SizedBox(height: Space.md),
            const _Block(width: 74, height: 22),
            const SizedBox(height: Space.sm),
            const _Block(width: double.infinity, height: 22, radius: 2),
            const SizedBox(height: Space.xl),
            for (int i = 0; i < 2; i++) ...<Widget>[
              const _Block(width: 240, height: 12),
              const SizedBox(height: Space.sm),
              const _Block(width: double.infinity, height: 10),
              const SizedBox(height: Space.lg),
            ],
            const _Block(width: 320, height: 58, radius: 2),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    this.radius = Radii.sharp,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paperSunken,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
