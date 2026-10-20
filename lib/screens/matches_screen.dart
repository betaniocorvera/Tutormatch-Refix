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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/location_map.dart';
import 'package:tutormatch/widgets/match_card.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
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

  /// List is the default because reasons are the product; the map is the second
  /// reading of the same filtered set, never a replacement for the cards.
  bool _mapView = false;

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
          label: 'Messages',
          onTap: () => Navigator.of(context).pushNamed(Routes.messages),
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

    // The static inbox is the side you are standing on: a student's outbox of
    // asks, a tutor's list of what arrived. The live conversations are checked
    // in the loop below, so a request sent a minute ago counts too.
    final List<MatchRequest> inbox =
        state.role == Role.student ? sampleRequests : sampleReceivedRequests;

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
          if (state.filters.maxDistanceKm != null)
            TMFilterTag(
              label: 'Within ${state.filters.maxDistanceKm} km',
              onRemove: () =>
                  state.filters = state.filters.copyWith(clearDistance: true),
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

    final Widget summary = _ResultSummary(results: results, total: ranked.length);
    final Widget viewToggle = SizedBox(
      width: 180,
      child: TMSegmented<bool>(
        options: const <bool>[false, true],
        selected: _mapView,
        onSelect: (bool map) => setState(() => _mapView = map),
        labelOf: (bool map) => map ? 'Map' : 'List',
      ),
    );

    final Widget header = TMLayout.isCompact(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              summary,
              const SizedBox(height: Space.md),
              viewToggle,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: summary),
              const SizedBox(width: Space.lg),
              viewToggle,
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        header,
        SizedBox(height: Space.xl),
        if (_mapView)
          _ResultsMap(
            results: results,
            onOpen: (MatchResult result) => Navigator.of(context).pushNamed(
              Routes.matchDetail,
              arguments: result,
            ),
          )
        else ...<Widget>[
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
                  state.conversations.any((Conversation chat) =>
                      chat.counterpartId == results[i].candidate.id &&
                      chat.status != RequestStatus.declined) ||
                  inbox.any((MatchRequest r) =>
                      r.counterpartId == results[i].candidate.id &&
                      r.status != RequestStatus.declined),
              onOpen: () => Navigator.of(context).pushNamed(
                Routes.matchDetail,
                arguments: results[i],
              ),
              onQuickRequest: () {
                // A quick request is a request: it becomes a conversation, and
                // the card says so from the same source the Messages screen reads.
                state.startConversation(results[i].candidate);
                setState(() => _askedHere.add(results[i].candidate.id));
              },
            ),
          ],
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

class _ResultsMap extends StatelessWidget {
  const _ResultsMap({required this.results, required this.onOpen});

  final List<MatchResult> results;
  final ValueChanged<MatchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final List<MatchResult> mappable = <MatchResult>[
      for (final MatchResult result in results)
        if (result.candidate.publicPlace != null) result,
    ];
    final int hidden = results.length - mappable.length;

    if (mappable.isEmpty) {
      return TMEntry(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const TMIcon(TMIconName.map, size: 20, color: AppColors.inkMuted),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('No areas to map.', style: AppType.name),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Everyone in these results hides their location. Their '
                    'cards are still in the list, with every other fact intact.',
                    style: AppType.bodySmall.quieter,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final List<LocationPin> pins = _fanOut(mappable);
    final String hiddenNote = hidden == 0
        ? ''
        : ' $hidden ${hidden == 1 ? 'person is' : 'people are'} not shown '
            'because their area is hidden.';
    final String note = 'Circles are approximate 1–2 km areas, not addresses. '
        'Tap a face to open their profile.$hiddenNote';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LocationMap(
          centerLatitude: pins.first.latitude,
          centerLongitude: pins.first.longitude,
          height: TMLayout.isWide(context) ? 540 : 420,
          pins: pins,
          fitPins: true,
          showCenterCircle: false,
          showPinCircles: true,
          interactive: true,
          fallbackTitle: 'Approximate areas',
          fallbackNote:
              '${pins.length} ${pins.length == 1 ? 'person' : 'people'} · '
              'details stay in the list',
          semanticLabel:
              'Map of ${pins.length} approximate areas. Tap a person to open '
              'their profile. $note',
        ),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: TMIcon(
                TMIconName.map,
                size: 14,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(note, style: AppType.bodySmall.quieter)),
          ],
        ),
      ],
    );
  }

  /// People can share a neighbourhood, and city-only people share a centre.
  /// Fan the pins into a small ring so every face stays tappable; the area
  /// circle, not the pin, is the claim about where they are.
  List<LocationPin> _fanOut(List<MatchResult> members) {
    final Map<String, List<MatchResult>> groups = <String, List<MatchResult>>{};
    for (final MatchResult result in members) {
      final PublicPlace place = result.candidate.publicPlace!;
      final String key =
          '${place.latitude.toStringAsFixed(4)}|${place.longitude.toStringAsFixed(4)}';
      groups.putIfAbsent(key, () => <MatchResult>[]).add(result);
    }

    final List<LocationPin> pins = <LocationPin>[];
    for (final List<MatchResult> group in groups.values) {
      for (int i = 0; i < group.length; i++) {
        final MatchResult result = group[i];
        final PublicPlace place = result.candidate.publicPlace!;
        double latitude = place.latitude;
        double longitude = place.longitude;
        if (group.length > 1) {
          final double angle = 2 * math.pi * i / group.length;
          const double spread = 0.0045;
          final double cosLat = math
              .cos(place.latitude * math.pi / 180)
              .abs()
              .clamp(0.2, 1.0)
              .toDouble();
          latitude += spread * math.sin(angle);
          longitude += spread * math.cos(angle) / cosLat;
        }
        final String? distance = result.distanceKm == null
            ? null
            : describeDistance(result.distanceKm!);
        pins.add(
          LocationPin(
            latitude: latitude,
            longitude: longitude,
            child: TMAvatar(
              result.candidate.name,
              size: 40,
              tint: result.candidate.photoTint,
            ),
            semanticLabel: 'Open ${result.candidate.name}\'s profile. '
                '${place.label}'
                '${distance == null ? '' : ', $distance'}.',
            onTap: () => onOpen(result),
          ),
        );
      }
    }
    return pins;
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
    // The name is the first thing to go when the top bar's right-hand side is
    // tight. "Sign out" is the action; the name is repeated on the page.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showName =
            !constraints.hasBoundedWidth || constraints.maxWidth >= 210;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showName) ...<Widget>[
              // A name is the one unbounded piece of user text in this bar, so
              // it gets a cap and an ellipsis: a forty-character name shortens
              // itself instead of pushing the navigation off the edge.
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
            ],
            TMButton(
              label: 'Sign out',
              variant: TMButtonVariant.quiet,
              minHeight: Hit.min,
              onPressed: () => Navigator.of(context)
                  .popUntil((Route<void> route) => route.isFirst),
            ),
          ],
        );
      },
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

        const TMMicroLabelText('Distance'),
        const SizedBox(height: Space.md),
        TMTagRow<int?>(
          options: const <int?>[null, 5, 10, 25],
          selected: f.maxDistanceKm,
          onSelect: (int? km) => state.filters = km == null
              ? f.copyWith(clearDistance: true, maxDistanceKm: null)
              : f.copyWith(maxDistanceKm: km),
          labelOf: (int? km) => km == null ? 'Any distance' : 'Within $km km',
        ),
        const SizedBox(height: Space.sm),
        Text(
          state.profile.publicPlace == null
              ? 'Your own area is hidden or not set, so there is nothing to '
                  'measure from. Choose an area or change your privacy setting '
                  'in Profile to use this filter.'
              : 'Measured from your approximate area; distances are shown '
                  'rounded to the nearest kilometre. A city-only area is '
                  'measured from its centre; a hidden area cannot be measured.',
          style: AppType.bodySmall.quieter,
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
