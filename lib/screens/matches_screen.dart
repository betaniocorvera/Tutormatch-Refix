// ─────────────────────────────────────────────────────────────────────────────
// The ranked list — the instrument at the centre of the product.
//
// A search desk, not a dashboard: one question at the top, one honest answer
// below it. The filters are a drawer under the search field rather than a
// permanent wall, because the ranking is the product and the filters are a
// correction to it.
//
// Two rules are load-bearing:
//
//   * Filters narrow a ranking; they never re-sort it. The order is the
//     recommender's opinion. The filters are yours.
//   * Search looks only inside the current ranking, and says so when it finds
//     nothing. The fallback is the neighbour map — the whole pool, drawn by
//     closeness — not a dead end.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/location_map.dart';
import 'package:tutormatch/widgets/match_card.dart';
import 'package:tutormatch/widgets/neighbor_map_3d.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_empty_state.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_motion.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _filtersOpen = false;
  bool _mapView = false;
  bool _requestedMatches = false;

  /// Search is local and presentation-only: it never changes the ranking and
  /// never calls /matches again. The debounce is for the list of results, not
  /// for the server.
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchTimer;
  String _appliedQuery = '';
  int _searchTick = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedMatches) return;
    _requestedMatches = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppStateScope.read(context).ensureMatches();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _appliedQuery = _query.text;
        _searchTick++;
      });
    });
  }

  void _setQuery(String value) {
    _query.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    if (value.isNotEmpty) _searchFocus.requestFocus();
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _query.clear();
    setState(() {
      _appliedQuery = '';
      _searchTick++;
    });
    _searchFocus.unfocus();
  }

  void _toggleFilters() {
    setState(() => _filtersOpen = !_filtersOpen);
  }

  Future<void> _quickRequest(AppState state, MatchResult result) async {
    final Candidate candidate = result.candidate;
    final String? subject = state.sharedSubjectFor(candidate);
    if (subject == null) {
      _showMessage(
        'You have no subject in common with ${candidate.name} yet. '
        'Add one of their subjects to your profile first.',
      );
      return;
    }
    if (!state.canRequest(candidate)) {
      _showMessage(
        state.profileAnswered
            ? 'There is already an open request with ${candidate.name}.'
            : 'Finish your five answers before sending a request.',
      );
      return;
    }
    try {
      await state.createRequest(
        candidate: candidate,
        subject: subject,
        note: 'Hi ${candidate.name}, I would like to arrange $subject sessions. '
            'Are you available this week?',
      );
      _showMessage('Request sent to ${candidate.name}.');
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool student = state.role == Role.student;
    final List<MatchResult> ranked = state.matches;
    final List<MatchResult> searched = _search(ranked, _appliedQuery);
    final String query = _appliedQuery.trim();
    final Set<String> askedHere = <String>{
      for (final MatchRequest request in state.requests)
        if (request.status != RequestStatus.declined) request.counterpartId,
    };

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RankHeader(
            student: student,
            name: state.profile.name,
            ranked: state.rankedCount,
            pool: state.poolSize,
            profileAnswered: state.profileAnswered,
            profileSummary: state.profileSummary,
            onEditAnswers: () => Navigator.of(context).pushNamed(
              Routes.onboarding,
              arguments: state.role,
            ),
          ),
          SizedBox(height: Space.xl),
          _SearchConsole(
            controller: _query,
            focusNode: _searchFocus,
            filtersOpen: _filtersOpen,
            activeFilters: _activeFilterCount(state.filters),
            onToggleFilters: _toggleFilters,
            onClear: _clearSearch,
            onSubmitted: (_) => _searchFocus.unfocus(),
            activeChips: _activeChips(context, state),
            hasFilters: state.filters.isNarrowed,
            onClearFilters: state.clearFilters,
            showFilters: _filtersOpen,
            filters: _FilterPanel(
              state: state,
              ranked: ranked,
              onRerank: () {
                setState(() => _filtersOpen = false);
                state.loadMatches();
              },
              onClose: () => setState(() => _filtersOpen = false),
            ),
          ),
          SizedBox(height: Space.xl),
          if (state.matchesLoading)
            const _RankingInProgress()
          else if (state.matchesError != null && ranked.isEmpty)
            _MatchesError(
              message: state.matchesError!,
              onRetry: state.loadMatches,
            )
          else if (state.coldStart != null && ranked.isEmpty)
            _ColdStartState(
              coldStart: state.coldStart!,
              onEditAnswers: () => Navigator.of(context).pushNamed(
                Routes.onboarding,
                arguments: state.role,
              ),
              onRetry: state.loadMatches,
            )
          else if (ranked.isEmpty && state.filters.isNarrowed)
            _FilterEmpty(
              state: state,
            )
          else if (searched.isEmpty)
            _SearchEmpty(
              query: query,
              ranked: ranked,
              nearby: _nearbyPeople(searched.isEmpty ? ranked : searched),
              subjects: _subjectsIn(ranked),
              searchTick: _searchTick,
              onSubject: _setQuery,
              onClear: _clearSearch,
              onOpen: (MatchResult result) => Navigator.of(context).pushNamed(
                Routes.matchDetail,
                arguments: result,
              ),
              onOpenFilters: _toggleFilters,
            )
          else
            _Results(
              state: state,
              ranked: ranked,
              visible: searched,
              query: query,
              mapView: _mapView,
              onMapView: (bool map) => setState(() => _mapView = map),
              askedHere: askedHere,
              onRequest: (MatchResult result) => _quickRequest(state, result),
              onOpen: (MatchResult result) => Navigator.of(context).pushNamed(
                Routes.matchDetail,
                arguments: result,
              ),
            ),
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  /// Keeps only rows whose person, subjects or public area answer the query.
  /// All words must land somewhere, so "chem manchester" is an intersection, not
  /// a union. Search never touches the ranking.
  List<MatchResult> _search(List<MatchResult> results, String query) {
    final List<String> terms = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return results;

    return results.where((MatchResult result) {
      final Candidate c = result.candidate;
      final String haystack = <String>[
        c.name,
        c.headline,
        c.subjects.join(' '),
        c.styleLabel,
        c.styleTags.join(' '),
        c.modeCopy,
        c.location,
        c.publicPlace?.label ?? '',
      ].join(' ').toLowerCase();
      return terms.every(haystack.contains);
    }).toList();
  }

  List<String> _subjectsIn(List<MatchResult> ranked) {
    final Map<String, int> counts = <String, int>{};
    for (final MatchResult result in ranked) {
      for (final String subject in result.candidate.subjects) {
        counts[subject] = (counts[subject] ?? 0) + 1;
      }
    }
    final List<String> subjects = counts.keys.toList()
      ..sort((String a, String b) {
        final int byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return subjects.take(8).toList();
  }

  List<MatchResult> _nearbyPeople(List<MatchResult> results) {
    final List<MatchResult> mappable = results
        .where((MatchResult result) => result.candidate.publicPlace != null)
        .toList();
    return mappable.length >= 3 ? mappable : results;
  }

  int _activeFilterCount(MatchFilters f) {
    int count = f.subjects.length + f.requiredParts.length;
    if (f.mustBeFreeWhenIAm) count++;
    if (f.mode != null) count++;
    if (f.maxRate < 80) count++;
    if (f.maxDistanceKm != null) count++;
    if (f.minScore > 0) count++;
    return count;
  }

  List<Widget> _activeChips(BuildContext context, AppState state) {
    final MatchFilters f = state.filters;
    return <Widget>[
      if (f.mustBeFreeWhenIAm)
        TMFilterTag(
          label: 'Hours overlap mine',
          onRemove: () => state.filters =
              state.filters.copyWith(mustBeFreeWhenIAm: false),
        ),
      for (final int p in f.requiredParts)
        TMFilterTag(
          label: 'Free on my ${Week.partLong[p]}',
          onRemove: () => state.filters = state.filters.copyWith(
            requiredParts: <int>{...state.filters.requiredParts}..remove(p),
          ),
        ),
      if (f.mode != null)
        TMFilterTag(
          label: f.mode!.label,
          onRemove: () =>
              state.filters = state.filters.copyWith(clearMode: true, mode: null),
        ),
      if (f.maxRate < 80)
        TMFilterTag(
          label: 'Up to \$${f.maxRate}/hr',
          onRemove: () => state.filters = state.filters.copyWith(maxRate: 80),
        ),
      if (f.maxDistanceKm != null)
        TMFilterTag(
          label: 'Within ${f.maxDistanceKm} km',
          onRemove: () => state.filters = state.filters.copyWith(clearDistance: true),
        ),
      for (final String s in f.subjects)
        TMFilterTag(
          label: s,
          onRemove: () => state.filters = state.filters.copyWith(
            subjects: <String>{...state.filters.subjects}..remove(s),
          ),
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The head of the desk
// ─────────────────────────────────────────────────────────────────────────────

class _RankHeader extends StatelessWidget {
  const _RankHeader({
    required this.student,
    required this.name,
    required this.ranked,
    required this.pool,
    required this.profileAnswered,
    required this.profileSummary,
    required this.onEditAnswers,
  });

  final bool student;
  final String name;
  final int ranked;
  final int pool;
  final bool profileAnswered;
  final String profileSummary;
  final VoidCallback onEditAnswers;

  @override
  Widget build(BuildContext context) {
    final bool wide = TMLayout.isWide(context);
    final Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'MATCHES · ${student ? 'STUDENT' : 'TUTOR'} · ${name.toUpperCase()}',
          style: AppType.micro.tone(AppColors.inkMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.sm + 2),
        Text(
          student ? 'Tutors ranked for you' : 'Students ranked for you',
          style: AppType.pageTitle,
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Ordered by five signals on your profile: subject, hours, teaching '
            'style, format and budget. Filters narrow this ranking. They never '
            'change its order.',
            style: AppType.bodyLarge.quiet,
          ),
        ),
        if (profileAnswered) ...<Widget>[
          const SizedBox(height: Space.lg),
          _ProfileBasis(summary: profileSummary, onEdit: onEditAnswers),
        ],
      ],
    );

    if (!wide) return title;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: title),
        const SizedBox(width: Space.xxl),
        _PoolMeter(ranked: ranked, pool: pool),
      ],
    );
  }
}

/// Real counts, set like an instrument. Nothing here is a promise the data
/// cannot keep.
class _PoolMeter extends StatelessWidget {
  const _PoolMeter({required this.ranked, required this.pool});

  final int ranked;
  final int pool;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 194,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.rule),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                ranked.toString().padLeft(2, '0'),
                style: AppType.score,
              ),
              const SizedBox(width: Space.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('ranked', style: AppType.bodySmall.quieter),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.sm),
          Row(
            children: <Widget>[
              Text(
                pool.toString().padLeft(2, '0'),
                style: AppType.figure.tone(AppColors.inkSecondary),
              ),
              const SizedBox(width: Space.sm),
              Text('in the pool', style: AppType.bodySmall.quieter),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: <Widget>[
              Text(
                '05',
                style: AppType.figure.tone(AppColors.inkSecondary),
              ),
              const SizedBox(width: Space.sm),
              Text('signals weighed', style: AppType.bodySmall.quieter),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileBasis extends StatelessWidget {
  const _ProfileBasis({required this.summary, required this.onEdit});

  final String summary;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Widget basis = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm - 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentWash,
        border: Border.all(color: AppColors.accent),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const TMIcon(
            TMIconName.sliders,
            size: 13,
            color: AppColors.accent,
          ),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              'Ranked on your five answers',
              style: AppType.micro.tone(AppColors.accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    final Widget summaryText = Tooltip(
      message: summary,
      child: Text(
        summary,
        style: AppType.bodySmall.quieter,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final Widget change = TMTextLink(
      label: 'Change them',
      style: AppType.bodySmall,
      color: AppColors.accent,
      hoverColor: AppColors.accentHover,
      minHeight: Hit.min,
      onTap: onEdit,
    );

    if (TMLayout.isCompact(context)) {
      // On a phone the summary wraps; keeping the action in the same Wrap put
      // it wherever the last line happened to end. It gets its own left-aligned
      // row and the full 44 px tap height instead.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[basis, summaryText],
          ),
          change,
        ],
      );
    }

    return Wrap(
      spacing: Space.md,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[basis, summaryText, change],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search and filters
// ─────────────────────────────────────────────────────────────────────────────

class _SearchConsole extends StatelessWidget {
  const _SearchConsole({
    required this.controller,
    required this.focusNode,
    required this.filtersOpen,
    required this.activeFilters,
    required this.onToggleFilters,
    required this.onClear,
    required this.onSubmitted,
    required this.activeChips,
    required this.hasFilters,
    required this.onClearFilters,
    required this.showFilters,
    required this.filters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool filtersOpen;
  final int activeFilters;
  final VoidCallback onToggleFilters;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;
  final List<Widget> activeChips;
  final bool hasFilters;
  final VoidCallback onClearFilters;
  final bool showFilters;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(
              color: filtersOpen ? AppColors.ruleStrong : AppColors.rule,
            ),
            borderRadius: Radii.sharpAll,
          ),
          child: Column(
            children: <Widget>[
              _SearchField(
                controller: controller,
                focusNode: focusNode,
                filtersOpen: filtersOpen,
                activeFilters: activeFilters,
                onToggleFilters: onToggleFilters,
                onClear: onClear,
                onSubmitted: onSubmitted,
              ),
              if (hasFilters)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm,
                    Space.md,
                    Space.sm + 2,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.rule)),
                  ),
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        'Narrowed by',
                        style: AppType.micro.tone(AppColors.inkMuted),
                      ),
                      ...activeChips,
                      TMTextLink(
                        label: 'Clear all',
                        style: AppType.bodySmall,
                        onTap: onClearFilters,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Motion.respect(context, Motion.base),
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Motion.respect(context, Motion.fast),
            switchInCurve: Motion.ease,
            switchOutCurve: Motion.ease,
            child: showFilters
                ? Padding(
                    key: const ValueKey<String>('filters-open'),
                    padding: const EdgeInsets.only(top: Space.md),
                    child: filters,
                  )
                : const SizedBox(
                    key: ValueKey<String>('filters-closed'),
                    width: double.infinity,
                  ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.filtersOpen,
    required this.activeFilters,
    required this.onToggleFilters,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool filtersOpen;
  final int activeFilters;
  final VoidCallback onToggleFilters;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() => _focused = widget.focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final bool hasText = widget.controller.text.isNotEmpty;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showFilterLabel = constraints.maxWidth >= 470;
        return AnimatedContainer(
          duration: Motion.respect(context, Motion.fast),
          curve: Motion.ease,
          // A fixed height, not a minimum: the row is laid out inside a
          // vertically unbounded column, and a minHeight alone hands it an
          // infinite constraint it cannot resolve.
          constraints: const BoxConstraints.tightFor(height: 64),
          decoration: BoxDecoration(
            color: _focused ? AppColors.paper : AppColors.paperRaised,
            borderRadius: BorderRadius.circular(Radii.sharp - 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: Space.lg, right: Space.sm),
                child: Center(
                  child: TMIcon(
                    TMIconName.search,
                    size: 20,
                    color: _focused ? AppColors.accent : AppColors.inkMuted,
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'Search the ranked results by name, subject or area',
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) => widget.focusNode.unfocus(),
                    style: AppType.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: AppColors.accent,
                    cursorWidth: 1.5,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: Space.lg + 2,
                      ),
                      hintText: 'Search by name, subject or area',
                      hintStyle: AppType.bodyLarge.quieter,
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: Motion.respect(context, Motion.fast),
                switchInCurve: Motion.ease,
                switchOutCurve: Motion.ease,
                child: hasText
                    ? Padding(
                        key: const ValueKey<String>('clear'),
                        padding: const EdgeInsets.only(right: Space.xs),
                        child: Tooltip(
                          message: 'Clear search',
                          child: TMFocusable(
                            onTap: widget.onClear,
                            semanticLabel: 'Clear search',
                            builder: (BuildContext context, TMState s) =>
                                TMFocusRing(
                              focused: s.focused,
                              radius: Radii.pill,
                              child: SizedBox(
                                width: Hit.min,
                                height: Hit.min,
                                child: Center(
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: s.hovered
                                          ? AppColors.paperSunken
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const TMIcon(
                                      TMIconName.close,
                                      size: 14,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey<String>('clear-hidden'),
                        width: Space.sm,
                      ),
              ),
              const SizedBox(
                height: 32,
                width: 1,
                child: Center(
                  child: SizedBox(
                    width: 1,
                    height: 32,
                    child: ColoredBox(color: AppColors.rule),
                  ),
                ),
              ),
              Tooltip(
                message: widget.filtersOpen
                    ? 'Close filters and your answers'
                    : 'Open filters and your answers',
                child: TMFocusable(
                  onTap: widget.onToggleFilters,
                  semanticLabel: widget.filtersOpen
                      ? 'Close filters and your answers'
                      : 'Open filters and your answers',
                  builder: (BuildContext context, TMState s) => TMFocusRing(
                    focused: s.focused,
                    radius: Radii.sharp,
                    child: AnimatedContainer(
                      duration: Motion.respect(context, Motion.fast),
                      curve: Motion.ease,
                      // The control fills the search row so the tap target is
                      // the full 64 px desk height, not just the icon's box.
                      height: 64,
                      padding: EdgeInsets.symmetric(
                        horizontal: showFilterLabel ? Space.lg : Space.md,
                      ),
                      decoration: BoxDecoration(
                        color: widget.filtersOpen
                            ? AppColors.accentWash
                            : s.hovered
                                ? AppColors.paperSunken
                                : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(Radii.sharp - 1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TMIcon(
                            TMIconName.sliders,
                            size: 17,
                            color: widget.filtersOpen
                                ? AppColors.accent
                                : AppColors.inkSecondary,
                          ),
                          if (showFilterLabel) ...<Widget>[
                            const SizedBox(width: Space.sm),
                            Text(
                              'Filters',
                              style: AppType.labelSmall.tone(
                                widget.filtersOpen
                                    ? AppColors.accent
                                    : AppColors.inkSecondary,
                              ),
                            ),
                          ],
                          if (widget.activeFilters > 0) ...<Widget>[
                            const SizedBox(width: Space.sm),
                            Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              height: 18,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Text(
                                '${widget.activeFilters}',
                                style: AppType.micro.copyWith(
                                  fontSize: 10,
                                  height: 1,
                                  color: AppColors.onAccent,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: Space.xs),
                          TMRotatingIcon(
                            TMIconName.chevronDown,
                            turns: widget.filtersOpen ? 0.5 : 0,
                            size: 13,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.state,
    required this.ranked,
    required this.onRerank,
    required this.onClose,
  });

  final AppState state;
  final List<MatchResult> ranked;
  final VoidCallback onRerank;
  final VoidCallback onClose;

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

    final Widget hours = _FilterGroup(
      label: 'Hours',
      children: <Widget>[
        const _FilterLabel('Hours must overlap mine'),
        TMSegmented<bool>(
          options: const <bool>[true, false],
          selected: f.mustBeFreeWhenIAm,
          onSelect: (bool v) =>
              state.filters = f.copyWith(mustBeFreeWhenIAm: v),
          labelOf: (bool v) => v ? 'Only overlaps' : 'Every hour',
        ),
        const SizedBox(height: Space.sm),
        Text(
          f.mustBeFreeWhenIAm
              ? 'Only people with at least one hour free when you are.'
              : 'Everyone, including people you could never meet.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.lg),
        const _FilterLabel('Free on my'),
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
      ],
    );

    final Widget format = _FilterGroup(
      label: 'Format and distance',
      children: <Widget>[
        const _FilterLabel('Format'),
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
        const SizedBox(height: Space.lg),
        const _FilterLabel('Distance'),
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
              ? 'Your own area is hidden or unset, so there is nothing to '
                  'measure from. Choose an area or change your privacy setting '
                  'in Profile to use this filter.'
              : 'Measured from your approximate area and rounded to the nearest '
                  'kilometre. A hidden area cannot be measured.',
          style: AppType.bodySmall.quieter,
        ),
      ],
    );

    final Widget budget = _FilterGroup(
      label: 'Budget',
      children: <Widget>[
        TMBudgetScale(
          value: f.maxRate,
          onChanged: (int v) => state.filters = f.copyWith(maxRate: v),
        ),
        const SizedBox(height: Space.sm),
        Text(
          f.maxRate >= 80
              ? 'No ceiling. Every rate in the pool is eligible.'
              : 'Showing rates at or below \$${f.maxRate} an hour.',
          style: AppType.bodySmall.quieter,
        ),
      ],
    );

    final Widget subjects = _FilterGroup(
      label: 'Subjects',
      children: <Widget>[
        TMTagPicker(
          options: available,
          selected: f.subjects,
          onToggle: (String s) {
            final Set<String> next = <String>{...f.subjects};
            if (!next.remove(s)) next.add(s);
            state.filters = f.copyWith(subjects: next);
          },
        ),
      ],
    );

    final Widget answers = Container(
      padding: const EdgeInsets.all(Space.lg),
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
                TMIconName.sparkle,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Your five answers',
                  style: AppType.micro.tone(AppColors.accent),
                ),
              ),
              TMTextLink(
                label: 'Change them',
                style: AppType.bodySmall,
                color: AppColors.accent,
                hoverColor: AppColors.accentHover,
                minHeight: Hit.min,
                onTap: () => Navigator.of(context).pushNamed(
                  Routes.onboarding,
                  arguments: state.role,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(state.profileSummary, style: AppType.bodySmall.quieter),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.rule),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Narrow the ranking', style: AppType.sectionTitle),
                    const SizedBox(height: Space.xs),
                    Text(
                      'A filter removes rows. It never changes the order of the '
                      'ones that remain.',
                      style: AppType.bodySmall.quieter,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Tooltip(
                message: 'Close filters',
                child: TMFocusable(
                  onTap: onClose,
                  semanticLabel: 'Close filters',
                  builder: (BuildContext context, TMState s) => TMFocusRing(
                    focused: s.focused,
                    radius: Radii.sharp,
                    child: SizedBox(
                      width: Hit.min,
                      height: Hit.min,
                      child: AnimatedContainer(
                        duration: Motion.respect(context, Motion.fast),
                        decoration: BoxDecoration(
                          color: s.hovered
                              ? AppColors.paperSunken
                              : Colors.transparent,
                          borderRadius: Radii.sharpAll,
                        ),
                        child: const Center(
                          child: TMIcon(
                            TMIconName.close,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          answers,
          const SizedBox(height: Space.xl),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool twoColumns = constraints.maxWidth >= 680;
              if (!twoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    hours,
                    SizedBox(height: Space.xl),
                    format,
                    SizedBox(height: Space.xl),
                    budget,
                    SizedBox(height: Space.xl),
                    subjects,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        hours,
                        SizedBox(height: Space.xxl),
                        budget,
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.xxl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        format,
                        SizedBox(height: Space.xxl),
                        subjects,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: Space.xl),
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TMButton(
                label: 'Rank again',
                variant: TMButtonVariant.secondary,
                icon: TMIconName.refresh,
                iconLeading: true,
                minHeight: Hit.min,
                onPressed: onRerank,
              ),
              TMTextLink(
                label: 'Clear every filter',
                style: AppType.bodySmall,
                onTap: f.isNarrowed ? state.clearFilters : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TMMicroLabelText(label),
        const SizedBox(height: Space.md),
        ...children,
      ],
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(text, style: AppType.labelSmall.tone(AppColors.inkSecondary)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results
// ─────────────────────────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  const _Results({
    required this.state,
    required this.ranked,
    required this.visible,
    required this.query,
    required this.mapView,
    required this.onMapView,
    required this.askedHere,
    required this.onRequest,
    required this.onOpen,
  });

  final AppState state;
  final List<MatchResult> ranked;
  final List<MatchResult> visible;
  final String query;
  final bool mapView;
  final ValueChanged<bool> onMapView;
  final Set<String> askedHere;
  final ValueChanged<MatchResult> onRequest;
  final ValueChanged<MatchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final Widget summary = _ResultSummary(
      results: visible,
      total: ranked.length,
      query: query,
    );
    final Widget viewToggle = SizedBox(
      width: 180,
      child: TMSegmented<bool>(
        options: const <bool>[false, true],
        selected: mapView,
        onSelect: onMapView,
        labelOf: (bool map) => map ? 'Map' : 'List',
        height: 40,
        showDividers: false,
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

    final Widget body = AnimatedSwitcher(
      duration: Motion.respect(context, Motion.slow),
      switchInCurve: Motion.ease,
      switchOutCurve: Motion.ease,
      child: mapView
          ? Padding(
              key: const ValueKey<String>('map-view'),
              padding: const EdgeInsets.only(top: Space.xl),
              child: _ResultsMap(
                results: visible,
                onOpen: onOpen,
              ),
            )
          : Padding(
              key: const ValueKey<String>('list-view'),
              padding: const EdgeInsets.only(top: Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < visible.length; i++) ...<Widget>[
                    if (i > 0) SizedBox(height: Space.xl),
                    if (i == 5 && visible.length > 6) ...<Widget>[
                      const SizedBox(height: Space.xxl),
                      const Divider(height: 1),
                      const SizedBox(height: Space.lg),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          'Below this line the reasons start to be about what you '
                          'would be giving up. They are still ranked honestly, and '
                          'the reason is still stated — read the third line of '
                          'each one first.',
                          style: AppType.bodySmall.quieter,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                    ],
                    TMReveal(
                      key: ValueKey<String>('match-${visible[i].candidate.id}'),
                      delay: Motion.stagger * math.min(i, 6),
                      child: MatchResultCard(
                        result: visible[i],
                        rank: i + 1,
                        total: ranked.length,
                        lead: i == 0,
                        fromProfile: state.profileAnswered,
                        profileSummary: state.profileSummary,
                        requested:
                            askedHere.contains(visible[i].candidate.id),
                        onOpen: () => onOpen(visible[i]),
                        onQuickRequest: () => onRequest(visible[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        body,
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.results,
    required this.total,
    required this.query,
  });

  final List<MatchResult> results;
  final int total;
  final String query;

  @override
  Widget build(BuildContext context) {
    int band(MatchTier t) =>
        results.where((MatchResult r) => r.tier == t).length;
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
            Text(
              results.length.toString().padLeft(2, '0'),
              style: AppType.figureLarge.tone(AppColors.ink),
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                query.isEmpty
                    ? 'of $total showing'
                    : results.length == 1
                        ? 'result for “$query”'
                        : 'results for “$query”',
                style: AppType.bodySmall.quieter,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          parts.isEmpty
              ? 'Nothing above the threshold you set.'
              : '${parts.join(' · ')} · filters narrow, never re-rank',
          style: AppType.bodySmall.quieter,
        ),
      ],
    );
  }
}

class _RankingInProgress extends StatelessWidget {
  const _RankingInProgress();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            'format and budget.',
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

class _MatchesError extends StatelessWidget {
  const _MatchesError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return TMEmptyState(
      headline: 'The ranking could not load.',
      body: message,
      primaryLabel: 'Try again',
      onPrimary: onRetry,
    );
  }
}

class _ColdStartState extends StatelessWidget {
  const _ColdStartState({
    required this.coldStart,
    required this.onEditAnswers,
    required this.onRetry,
  });

  final ColdStart coldStart;
  final VoidCallback onEditAnswers;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool incomplete = coldStart.reason == 'profile_incomplete';
    return TMEmptyState(
      headline: incomplete
          ? 'A few answers are still missing.'
          : 'There is nobody to rank yet.',
      body: coldStart.message,
      primaryLabel: incomplete ? 'Finish my answers' : 'Try again',
      onPrimary: incomplete ? onEditAnswers : onRetry,
      filtersLabel: incomplete && coldStart.missing.isNotEmpty
          ? 'Still needed'
          : null,
      filters: <Widget>[
        for (final String item in coldStart.missing) TMFilterTag(label: item),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty states
// ─────────────────────────────────────────────────────────────────────────────

/// The filters removed everyone. The server has already applied them, so the
/// only honest next step is to remove one condition or clear them all.
class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return TMEmptyState(
      headline: 'Nobody matches every filter.',
      body: 'The ranking still exists; these conditions have narrowed it to '
          'nothing. Remove one condition to see the people it is hiding.',
      primaryLabel: 'Clear every filter',
      onPrimary: state.clearFilters,
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
            onRemove: () =>
                state.filters = state.filters.copyWith(clearMode: true, mode: null),
          ),
        if (state.filters.maxRate < 80)
          TMFilterTag(
            label: 'Up to \$${state.filters.maxRate}/hr',
            onRemove: () =>
                state.filters = state.filters.copyWith(maxRate: 80),
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
}

/// Search found nobody in the current list. Give the whole ranked pool back as a
/// map — the closest first — and the subjects that would reopen the search.
class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({
    required this.query,
    required this.ranked,
    required this.nearby,
    required this.subjects,
    required this.searchTick,
    required this.onSubject,
    required this.onClear,
    required this.onOpen,
    required this.onOpenFilters,
  });

  final String query;
  final List<MatchResult> ranked;
  final List<MatchResult> nearby;
  final List<String> subjects;
  final int searchTick;
  final ValueChanged<String> onSubject;
  final VoidCallback onClear;
  final ValueChanged<MatchResult> onOpen;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final bool compact = TMLayout.isCompact(context);
    final List<NeighborNode> nodes = <NeighborNode>[
      for (final MatchResult result in nearby.take(10))
        NeighborNode(
          id: result.candidate.id,
          name: result.candidate.name,
          subject: result.candidate.subjects.first,
          score: result.score.total,
          tint: result.candidate.photoTint,
        ),
    ];
    final Map<String, MatchResult> byId = <String, MatchResult>{
      for (final MatchResult result in nearby) result.candidate.id: result,
    };

    return TMEntry(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sharp - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(compact ? Space.lg : Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'NO SEARCH MATCH',
                    style: AppType.micro.tone(AppColors.inkMuted),
                  ),
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    width: 580,
                    child: Text(
                      query.isEmpty
                          ? 'Nobody in this list to show.'
                          : 'Nobody in this list matches “$query”.',
                      style: AppType.titleLarge,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    width: 620,
                    child: Text(
                      'Search reads the current ranking only. The pool is still '
                      'here, ordered by closeness — pick a subject or clear the '
                      'search to bring the cards back.',
                      style: AppType.body.quiet,
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      TMButton(
                        label: 'Clear search',
                        variant: TMButtonVariant.primary,
                        icon: TMIconName.close,
                        iconLeading: true,
                        minHeight: Hit.min,
                        onPressed: onClear,
                      ),
                      TMButton(
                        label: 'Adjust filters',
                        variant: TMButtonVariant.quiet,
                        icon: TMIconName.sliders,
                        iconLeading: true,
                        minHeight: Hit.min,
                        onPressed: onOpenFilters,
                      ),
                    ],
                  ),
                  if (subjects.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.xl),
                    Text(
                      'Try a subject in the pool',
                      style: AppType.micro.tone(AppColors.inkMuted),
                    ),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: <Widget>[
                        for (final String subject in subjects)
                          _SubjectSuggestion(
                            subject: subject,
                            selected: subject.toLowerCase() == query.toLowerCase(),
                            onTap: () => onSubject(subject),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            NeighborMap3D(
              nodes: nodes,
              height: compact ? 300 : 380,
              userLabel: 'You',
              searchTick: searchTick,
              onSelect: (NeighborNode node) {
                final MatchResult? result = byId[node.id];
                if (result != null) onOpen(result);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A subject chip that fills the search field rather than a filter. Same pill,
/// different job, and the difference is in the verb beside it.
class _SubjectSuggestion extends StatelessWidget {
  const _SubjectSuggestion({
    required this.subject,
    required this.selected,
    required this.onTap,
  });

  final String subject;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Search for $subject',
      child: TMFocusable(
        onTap: onTap,
        semanticLabel: 'Search for $subject',
        semanticSelected: selected,
        builder: (BuildContext context, TMState s) => TMFocusRing(
          focused: s.focused,
          radius: Radii.pill,
          child: AnimatedContainer(
            duration: Motion.respect(context, Motion.fast),
            curve: Motion.ease,
            constraints: const BoxConstraints(minHeight: Hit.min),
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accentWash
                  : s.hovered
                      ? AppColors.paperSunken
                      : AppColors.paperRaised,
              border: Border.all(
                color: selected
                    ? AppColors.accent
                    : s.hovered
                        ? AppColors.ruleStrong
                        : AppColors.rule,
              ),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TMIcon(
                  TMIconName.search,
                  size: 13,
                  color: selected ? AppColors.accent : AppColors.inkMuted,
                ),
                const SizedBox(width: Space.sm),
                Text(
                  subject,
                  style: AppType.labelSmall.tone(
                    selected ? AppColors.accent : AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The map reading
// ─────────────────────────────────────────────────────────────────────────────

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: Radii.sharpAll,
          child: LocationMap(
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

// ─────────────────────────────────────────────────────────────────────────────
// Account
// ─────────────────────────────────────────────────────────────────────────────

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
            !constraints.hasBoundedWidth || constraints.maxWidth >= 320;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showName) ...<Widget>[
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
              onPressed: () => AuthFlow.signOut(context),
            ),
          ],
        );
      },
    );
  }
}
