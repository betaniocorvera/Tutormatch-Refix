// ─────────────────────────────────────────────────────────────────────────────
// THE MATCH RESULT CARD — the signature component.
//
// Reading order is the design:
//   1. Who, how close, and the one word for it. The tier is read before the
//      number because a word is faster than a figure.
//   2. The score as an instrument: a ring that fills once and counts with it.
//   3. Three reasons, each with the dimension's own mark. No click required.
//   4. The week, because agreement in principle is worthless until you know
//      when. Filled cells only.
//
// The first result is given amber rather than a bigger shadow: the lead is a
// ranking fact, not a decoration. Every other card earns its place with rhythm
// and hairlines alone.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/match_score_scale.dart';
import 'package:tutormatch/widgets/tilt_card.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
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
  final bool fromProfile;
  final String? profileSummary;
  final VoidCallback? onOpen;
  final VoidCallback? onQuickRequest;
  final bool requested;
  final int total;

  @override
  Widget build(BuildContext context) {
    final Candidate c = result.candidate;
    final String? when = describeOverlap(result.score.overlap);

    final Widget identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TMAvatar(
              c.name,
              size: lead ? 56 : 46,
              tint: c.photoTint,
              heroTag: 'avatar-${c.id}',
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    c.name,
                    style: lead ? AppType.titleLarge : AppType.name,
                  ),
                  const SizedBox(height: Space.xs + 2),
                  Text(
                    c.headline,
                    style: AppType.body.quiet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        _Facts(result: result),
        const SizedBox(height: Space.lg),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.md),
        for (int i = 0; i < result.reasons.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: Space.sm),
          _Reason(note: result.reasons[i]),
        ],
      ],
    );

    final Widget scoreBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MatchScorePanel(
          score: result.score.total,
          large: lead,
          showMeaning: false,
        ),
        const SizedBox(height: Space.lg),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: AppColors.paper,
            border: Border.all(color: AppColors.rule),
            borderRadius: Radii.sharpAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const TMIcon(
                    TMIconName.calendar,
                    size: 13,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: Space.sm),
                  Text('Shared hours', style: AppType.micro.tone(AppColors.inkMuted)),
                ],
              ),
              const SizedBox(height: Space.sm),
              AvailabilityGrid(
                overlap: result.score.overlap,
                cellHeight: lead ? 13 : 11,
                partLabels: false,
              ),
              const SizedBox(height: Space.sm),
              Text(
                when == null
                    ? 'No overlapping hours in a normal week.'
                    : '$when · ${result.score.overlapSlots} blocks',
                style: AppType.bodySmall.tone(
                  when == null ? AppColors.inkMuted : AppColors.inkSecondary,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    );

    final Widget actions = _Actions(
      lead: lead,
      requested: requested,
      onOpen: onOpen,
      onQuickRequest: onQuickRequest,
    );

    final Widget body = TMEntry(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sharp - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (lead)
              const SizedBox(height: 3, child: ColoredBox(color: AppColors.amber)),
            Padding(
              padding: EdgeInsets.all(lead ? Space.xl : Space.lg + 4),
              child: Column(
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
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final bool wide = constraints.maxWidth >= 680;
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            identity,
                            const SizedBox(height: Space.xl),
                            scoreBlock,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 7, child: identity),
                          const SizedBox(width: Space.xxl),
                          Expanded(flex: 3, child: scoreBlock),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: lead ? Space.xl : Space.lg),
                  const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
                  const SizedBox(height: Space.md),
                  actions,
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return TiltCard(
      maxTilt: lead ? 3.5 : 2.2,
      lift: lead ? 5 : 2,
      child: body,
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
    final Widget rankFigure = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          rank.toString().padLeft(2, '0'),
          style: AppType.figureLarge.tone(
            lead ? AppColors.onAmber : AppColors.inkMuted,
          ),
        ),
        if (total > 0) ...<Widget>[
          const SizedBox(width: Space.xs + 1),
          Text(
            'of $total',
            style: AppType.micro.tone(AppColors.inkMuted),
          ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (lead)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: Space.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                rankFigure,
                const SizedBox(width: Space.sm),
                Text(
                  'Nearest',
                  style: AppType.micro.copyWith(fontSize: 9.5)
                      .tone(AppColors.onAmber),
                ),
              ],
            ),
          )
        else
          rankFigure,
        const Spacer(),
        if (fromProfile)
          Flexible(
            child: Tooltip(
              message: profileSummary == null
                  ? 'Ranked using the answers you just gave.'
                  : 'Ranked using: $profileSummary',
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints limits) {
                  // At the narrowest card the provenance mark survives as its
                  // icon alone: the page header already names the five answers,
                  // and a squeezed label is worse than no label.
                  final bool withLabel = limits.maxWidth >= 56;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const TMIcon(
                        TMIconName.sparkle,
                        size: 12,
                        color: AppColors.accent,
                      ),
                      if (withLabel) ...<Widget>[
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            'Your answers',
                            style: AppType.micro.copyWith(fontSize: 9.5)
                                .tone(AppColors.accent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        const SizedBox(width: Space.sm),
        TMStatusPill(tone: tier.tone, label: tier.label, dense: true),
      ],
    );
  }
}

/// Subjects, format, rate, review line and public area. Facts, set as facts.
class _Facts extends StatelessWidget {
  const _Facts({required this.result});
  final MatchResult result;

  @override
  Widget build(BuildContext context) {
    final Candidate candidate = result.candidate;
    final PublicPlace? place = candidate.publicPlace;
    final String? distance = result.distanceKm == null
        ? null
        : describeDistance(result.distanceKm!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final String subject in candidate.subjects)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 2,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.ruleStrong),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  subject,
                  style: AppType.micro.copyWith(fontSize: 10)
                      .tone(AppColors.inkSecondary),
                ),
              ),
            _Dot(),
            Text(candidate.modeCopy, style: AppType.bodySmall.quieter),
            _Dot(),
            Text(
              candidate.rateCopy,
              style: AppType.figure.tone(AppColors.ink),
            ),
            if (candidate.reviews > 0) ...<Widget>[
              _Dot(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const TMIcon(
                    TMIconName.star,
                    size: 12,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${candidate.rating} · ${candidate.reviews}',
                    style: AppType.bodySmall.quieter,
                  ),
                ],
              ),
            ],
          ],
        ),
        if (place != null || distance != null) ...<Widget>[
          const SizedBox(height: Space.sm),
          Row(
            children: <Widget>[
              const TMIcon(
                TMIconName.pin,
                size: 13,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: Space.xs + 1),
              if (place != null)
                Flexible(
                  child: Text(
                    place.label,
                    style: AppType.bodySmall.tone(AppColors.inkSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (distance != null)
                Text(
                  '${place == null ? '' : ' · '}$distance',
                  style: AppType.bodySmall.quieter,
                ),
            ],
          ),
        ],
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

/// One reason, led by the mark of the dimension that produced it. The dimension
/// is visible rather than buried: three rows, three different sources.
class _Reason extends StatelessWidget {
  const _Reason({required this.note});
  final FitNote note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentWash,
            borderRadius: BorderRadius.circular(Radii.sharp - 3),
          ),
          child: TMIcon(
            switch (note.dimension) {
              MatchDimension.subjects => TMIconName.book,
              MatchDimension.time => TMIconName.clock,
              MatchDimension.style => TMIconName.sparkle,
              MatchDimension.format => TMIconName.compass,
              MatchDimension.budget => TMIconName.wallet,
            },
            size: 14,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                note.signal,
                style: AppType.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                note.detail,
                style: AppType.bodySmall.copyWith(fontSize: 12).quieter,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
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
    required this.onOpen,
    required this.onQuickRequest,
  });

  final bool lead;
  final bool requested;
  final VoidCallback? onOpen;
  final VoidCallback? onQuickRequest;

  @override
  Widget build(BuildContext context) {
    if (requested) {
      // A request is a step, not a dead end: the reasons and the person page
      // remain one click away after asking.
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget open = TMButton(
            label: 'Open profile',
            variant: TMButtonVariant.secondary,
            icon: TMIconName.arrowRight,
            minHeight: Hit.min,
            onPressed: onOpen,
          );
          final Widget status = TMStatusPill(
            tone: StatusTone.pending,
            label: 'Requested',
          );

          // On a narrow card the button sits under the status rather than
          // squeezing the explanation into a three-word column.
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[status, open],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'You have already asked. The answer will arrive in Messages.',
                  style: AppType.bodySmall.quieter,
                ),
              ],
            );
          }

          return Row(
            children: <Widget>[
              status,
              const SizedBox(width: Space.md),
              Flexible(
                child: Text(
                  'You have already asked. The answer will arrive in Messages.',
                  style: AppType.bodySmall.quieter,
                ),
              ),
              const SizedBox(width: Space.md),
              open,
            ],
          );
        },
      );
    }

    final Widget open = TMButton(
      label: lead ? 'Open the full profile' : 'Open profile',
      variant: lead ? TMButtonVariant.primary : TMButtonVariant.secondary,
      icon: TMIconName.arrowRight,
      minHeight: Hit.min,
      onPressed: onOpen,
    );

    if (!lead) {
      return Align(alignment: Alignment.centerLeft, child: open);
    }

    // The lead card carries a second, lighter action. It moves to its own row
    // on a narrow card rather than shrinking both targets or clipping one.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget quick = TMTextLink(
          label: 'Ask straight away',
          onTap: onQuickRequest,
        );
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              open,
              const SizedBox(height: Space.md),
              quick,
            ],
          );
        }
        return Row(
          children: <Widget>[
            open,
            const Spacer(),
            quick,
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────

/// A skeleton with the card's proportions, so nothing jumps when content lands.
/// Static blocks, no shimmer.
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
                  style: AppType.figureLarge.tone(AppColors.ruleStrong),
                ),
                const Spacer(),
                const _Block(width: 88, height: 20, radius: Radii.pill),
              ],
            ),
            const SizedBox(height: Space.xl),
            Row(
              children: <Widget>[
                const _Block(width: 46, height: 46, radius: 14),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      _Block(width: 190, height: 18),
                      SizedBox(height: Space.sm),
                      _Block(width: 260, height: 11),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            const _Block(width: 300, height: 11),
            const SizedBox(height: Space.lg),
            for (int i = 0; i < 3; i++) ...<Widget>[
              Row(
                children: <Widget>[
                  const _Block(width: 26, height: 26, radius: 9),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        _Block(width: 220, height: 10),
                        SizedBox(height: Space.xs),
                        _Block(width: 300, height: 9),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
            ],
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.sm,
              children: const <Widget>[
                _Block(width: 160, height: 44, radius: 12),
                _Block(width: 120, height: 20, radius: 10),
              ],
            ),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
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
      ),
    );
  }
}
