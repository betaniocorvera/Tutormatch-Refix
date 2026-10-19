// ─────────────────────────────────────────────────────────────────────────────
// The ranked list.
//
// Operate surface, so the list is the dominant element and everything else gets
// out of the way: a contents-style rail on the left on a laptop, a disclosure
// above the list on a phone.
//
// Two things here are worth defending:
//
//   * The filters narrow a ranking, they do not produce it. Rank order never
//     changes when a filter changes, because the order is the recommender's
//     opinion and the filters are yours.
//   * When the filters remove everybody, the empty state is generated from the
//     filters that actually fired and names the one to relax, with the count it
//     would bring back. See TMEmptyState.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/match_card.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_empty_state.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  /// The first ranking pass. A real service round trip would land here, and the
  /// skeleton holds the card's exact proportions so nothing jumps when it does.
  bool _ranking = true;
  bool _railOpen = false;

  /// Requests sent from this screen. In-memory, like everything else.
  final Set<String> _askedHere = <String>{};

  @override
  void initState() {
    super.initState();
    _startRanking();
  }

  void _startRanking() {
    setState(() => _ranking = true);
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _ranking = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool student = state.role == Role.student;
    final List<Candidate> pool = state.pool;
    final List<MatchResult> ranked = rank(pool, state.profile);
    final MatchOutcome outcome = applyFilters(ranked, state.filters, state.profile);
    final bool wide = TMLayout.isWide(context);

    final Widget rail = _FilterRail(
      state: state,
      ranked: ranked,
      onRerank: _startRanking,
    );

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(label: 'Matches', selected: true),
        TMNavItem(
          label: 'Requests',
          onTap: () => Navigator.of(context).pushNamed(Routes.requests),
        ),
        TMNavItem(
          label: 'Profile',
          onTap: () => Navigator.of(context).pushNamed(Routes.profile),
        ),
      ],
      navTrailing: _AccountTrailing(name: state.profile.name, role: state.role),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: Space.xxl),
          Text(
            student ? 'Tutors ranked for you' : 'Students ranked for you',
            style: AppType.pageTitle,
          ),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              _lede(student, ranked.length, pool.length),
              style: AppType.bodyLarge.quiet,
            ),
          ),
          if (state.profileAnswered) ...<Widget>[
            const SizedBox(height: Space.lg),
            _ProfileBasis(summary: state.profileSummary),
          ],
          SizedBox(height: Space.xxl),

          if (!wide) ...<Widget>[
            TMButton(
              label: _railOpen ? 'Hide the filters' : 'Filters and your answers',
              variant: TMButtonVariant.secondary,
              icon: TMIconName.sliders,
              iconLeading: true,
              minHeight: Hit.min,
              onPressed: () => setState(() => _railOpen = !_railOpen),
            ),
            const SizedBox(height: Space.lg),
          ],

          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: TMLayout.railWidth, child: rail),
                const SizedBox(width: Space.xxl),
                Expanded(child: _results(context, state, ranked, outcome)),
              ],
            )
          else ...<Widget>[
            // The rail sits above the list when it is open, and is still
            // visible while the results are being read: no overlay, no trap.
            if (_railOpen) ...<Widget>[
              rail,
              SizedBox(height: Space.xxl),
            ],
            _results(context, state, ranked, outcome),
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  static String _lede(bool student, int total, int pool) {
    final String counterpart = student ? 'tutor' : 'student';
    return '$pool $counterpart${pool == 1 ? '' : 's'} in the pool for this prototype, '
        'ordered by how well each one fits the five answers on your profile. '
        'Nothing outside those five is compared.';
  }

  Widget _results(
    BuildContext context,
    AppState state,
    List<MatchResult> ranked,
    MatchOutcome outcome,
  ) {
    if (_ranking) {
      return const _RankingInProgress();
    }

    if (outcome.empty != null) {
      final EmptyExplanation empty = outcome.empty!;
      return TMEmptyState(
        headline: empty.headline,
        body: empty.body,
        primaryLabel: empty.adjustLabel,
        onPrimary: () => state.relaxFilters(empty.relaxed),
        secondaryLabel: state.filters.isNarrowed ? 'Clear every filter' : null,
        onSecondary: state.clearFilters,
        filtersLabel: 'What is removing them',
        filters: <Widget>[
          if (state.filters.mustBeFreeWhenIAm)
            TMFilterTag(
              label: 'Hours must overlap mine',
              onRemove: () => state.filters =
                  state.filters.copyWith(mustBeFreeWhenIAm: false),
            ),
          for (final int p in state.filters.requiredParts)
            TMFilterTag(
              label: 'Free on my ${Week.partLong[p]}',
              onRemove: () => state.filters = state.filters.copyWith(
                requiredParts: <int>{...state.filters.requiredParts}..remove(p),
              ),
            ),
          if (state.filters.mode != null)
            TMFilterTag(
              label: state.filters.mode!.label,
              onRemove: () => state.filters =
                  state.filters.copyWith(clearMode: true, mode: null),
            ),
          if (state.filters.maxRate < 80)
            TMFilterTag(
              label: 'Up to \$${state.filters.maxRate}/hr',
              onRemove: () => state.filters = state.filters.copyWith(maxRate: 80),
            ),
          for (final String s in state.filters.subjects)
            TMFilterTag(
              label: s,
              onRemove: () => state.filters = state.filters.copyWith(
                subjects: <String>{...state.filters.subjects}..remove(s),
              ),
            ),
        ],
      );
    }

    final List<MatchResult> results = outcome.results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ResultSummary(results: results, total: ranked.length),
        SizedBox(height: Space.xl),
        for (int i = 0; i < results.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: Space.xl),
          // After the fifth entry the reasons stop being about what you gain.
          // Say so, rather than letting a long list quietly dilute itself.
          if (i == 5 && results.length > 6) ...<Widget>[
            const SizedBox(height: Space.xxl),
            const Divider(height: 1),
            const SizedBox(height: Space.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                'Below this line the reasons start to be about what you would be '
                'giving up. They are still ranked honestly, and the reason is '
                'still stated — read the third line of each one first.',
                style: AppType.bodySmall.quieter,
              ),
            ),
            const SizedBox(height: Space.xl),
          ],
          MatchResultCard(
            result: results[i],
            rank: i + 1,
            total: ranked.length,
            lead: i == 0,
            fromProfile: state.profileAnswered,
            profileSummary: state.profileSummary,
            requested: _askedHere.contains(results[i].candidate.id) ||
                sampleRequests.any((MatchRequest r) =>
                    r.counterpartId == results[i].candidate.id &&
                    r.status != RequestStatus.declined),
            onOpen: () => Navigator.of(context).pushNamed(
              Routes.matchDetail,
              arguments: results[i],
            ),
            onQuickRequest: () => setState(
              () => _askedHere.add(results[i].candidate.id),
            ),
          ),
        ],
      ],
    );
  }
}

class _RankingInProgress extends StatelessWidget {
  const _RankingInProgress();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: TMProgressRule(width: 320)),
          ],
        ),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Comparing your five answers against every profile in the pool: '
            'subjects first, then the hours you both keep free, then style, '
            'format and budget. This takes about a second.',
            style: AppType.body.quiet,
          ),
        ),
        const SizedBox(height: Space.xxl),
        for (int i = 0; i < 2; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: Space.xl),
          MatchCardSkeleton(rank: i + 1),
        ],
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.results, required this.total});

  final List<MatchResult> results;
  final int total;

  @override
  Widget build(BuildContext context) {
    int band(MatchTier t) => results.where((MatchResult r) => r.tier == t).length;
    final int strong = band(MatchTier.strong);
    final int good = band(MatchTier.good);
    final int rest = results.length - strong - good;

    final List<String> parts = <String>[
      if (strong > 0) '$strong strong',
      if (good > 0) '$good good',
      if (rest > 0) '$rest worth a look',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text('${results.length}', style: AppType.figureLarge),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                results.length == total
                    ? 'of $total showing'
                    : 'of $total after filtering',
                style: AppType.bodySmall.quieter,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          parts.isEmpty ? 'Nothing above the threshold you set.' : parts.join(' · '),
          style: AppType.bodySmall.quieter,
        ),
      ],
    );
  }
}

class _ProfileBasis extends StatelessWidget {
  const _ProfileBasis({required this.summary});
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(
              color: AppColors.accentWash,
              border: Border.all(color: AppColors.accent),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const TMIcon(TMIconName.sliders, size: 13, color: AppColors.accent),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    'Ranked on your answers: $summary',
                    style: AppType.micro.tone(AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountTrailing extends StatelessWidget {
  const _AccountTrailing({required this.name, required this.role});

  final String name;
  final Role role;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // A name is the one unbounded piece of user text in this bar, so it gets
        // a cap and an ellipsis: a forty-character name shortens itself instead
        // of pushing the navigation off the edge.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              '$name · ${role == Role.student ? 'Student' : 'Tutor'}',
              style: AppType.bodySmall.quieter,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        TMButton(
          label: 'Sign out',
          variant: TMButtonVariant.quiet,
          minHeight: Hit.min,
          onPressed: () => Navigator.of(context)
              .popUntil((Route<void> route) => route.isFirst),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The filter rail
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.state,
    required this.ranked,
    required this.onRerank,
  });

  final AppState state;
  final List<MatchResult> ranked;
  final VoidCallback onRerank;

  @override
  Widget build(BuildContext context) {
    final MatchFilters f = state.filters;

    // Only subjects that somebody in the pool actually teaches are offered.
    // A filter that can only ever return nothing is not a filter, it is a trap.
    final List<String> available = <String>{
      for (final MatchResult r in ranked) ...r.candidate.subjects,
    }.toList()
      ..sort();

    final Set<String> partNames = <String>{
      for (final int p in f.requiredParts) Week.partLong[p],
    };

    const String anyFormat = 'Any format';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Your answers'),
        const SizedBox(height: Space.md),
        Text(state.profileSummary, style: AppType.bodySmall.quieter),
        const SizedBox(height: Space.sm),
        TMTextLink(
          label: 'Change them',
          style: AppType.bodySmall,
          onTap: () => Navigator.of(context).pushNamed(
            Routes.onboarding,
            arguments: state.role,
          ),
        ),
        const SizedBox(height: Space.xl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.xl),

        const TMMicroLabelText('Hours must overlap mine'),
        const SizedBox(height: Space.md),
        TMSegmented<bool>(
          options: const <bool>[true, false],
          selected: f.mustBeFreeWhenIAm,
          onSelect: (bool v) => state.filters = f.copyWith(mustBeFreeWhenIAm: v),
          labelOf: (bool v) => v ? 'Only overlaps' : 'Every hour',
        ),
        const SizedBox(height: Space.sm),
        Text(
          f.mustBeFreeWhenIAm
              ? 'Showing only people with at least one hour free when you are.'
              : 'Showing everyone, including people you could never meet.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xl),

        const TMMicroLabelText('Free on my'),
        const SizedBox(height: Space.md),
        TMTagPicker(
          options: Week.partLong,
          selected: partNames,
          onToggle: (String name) {
            final int index = Week.partLong.indexOf(name);
            final Set<int> next = <int>{...f.requiredParts};
            if (!next.remove(index)) next.add(index);
            state.filters = f.copyWith(requiredParts: next);
          },
        ),
        const SizedBox(height: Space.xl),

        const TMMicroLabelText('Format'),
        const SizedBox(height: Space.md),
        TMTagRow<SessionMode?>(
          options: const <SessionMode?>[
            null,
            SessionMode.online,
            SessionMode.inPerson,
            SessionMode.both,
          ],
          selected: f.mode,
          onSelect: (SessionMode? m) => state.filters = m == null
              ? f.copyWith(clearMode: true, mode: null)
              : f.copyWith(mode: m),
          labelOf: (SessionMode? m) => m == null ? anyFormat : m.label,
        ),
        const SizedBox(height: Space.xl),

        const TMMicroLabelText('Ceiling'),
        const SizedBox(height: Space.md),
        TMBudgetScale(
          value: f.maxRate,
          onChanged: (int v) => state.filters = f.copyWith(maxRate: v),
        ),
        const SizedBox(height: Space.xl),

        const TMMicroLabelText('Subjects'),
        const SizedBox(height: Space.md),
        TMTagPicker(
          options: available,
          selected: f.subjects,
          onToggle: (String s) {
            final Set<String> next = <String>{...f.subjects};
            if (!next.remove(s)) next.add(s);
            state.filters = f.copyWith(subjects: next);
          },
        ),
        const SizedBox(height: Space.xl),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TMButton(
              label: 'Rank again',
              variant: TMButtonVariant.secondary,
              minHeight: Hit.min,
              onPressed: onRerank,
            ),
            if (f.isNarrowed)
              TMTextLink(
                label: 'Clear every filter',
                style: AppType.bodySmall,
                onTap: state.clearFilters,
              ),
          ],
        ),
      ],
    );
  }
}
