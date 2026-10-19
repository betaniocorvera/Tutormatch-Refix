// ═════════════════════════════════════════════════════════════════════════════
// SAMPLE DATA — NOT A BACKEND.
//
// Everything in this file is hard-coded so the interface can be built and
// judged before any service exists. Nothing here is fetched, stored or saved.
//
// HOW TO REPLACE IT WITH THE REAL THING
//   1. `MatchDimension` and `MatchScore` mirror the shape a KNN response should
//      return: a total 0-100 plus the per-dimension contribution that produced
//      it. Keep that shape and the detail screen keeps working.
//   2. `Candidate` is one row of the recommendation pool, for either role.
//      `fitSubjects / fitStyle / fitFormat / fitBudget` are the authored
//      agreement scores per dimension, each already capped at
//      `MatchDimension.max`. A real service sends these computed.
//   3. `MatchDimension.time` is the ONE dimension computed live in this demo,
//      from the actual overlap between the viewer's availability and the
//      candidate's. That is why the mini week grid and the score agree, and why
//      changing your availability in onboarding visibly re-ranks the list.
//      With a real service this arrives precomputed with the rest.
//   4. `applyFilters` and `MatchOutcome` are UI-side narrowing of an
//      already-ranked list. They are not the recommender. The recommender
//      ranks; the filters here only let a person interrogate the ranking.
//   5. `sampleRequests` is a static inbox. Wire it to POST /requests.
//
// The authored fit scores are calibrated against `demoStudentProfile` and
// `demoTutorProfile` at the bottom of this file, which is what you see if you
// skip onboarding. Walk the onboarding flow and the time dimension moves.
// ═════════════════════════════════════════════════════════════════════════════

import 'package:tutormatch/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Weekly availability
// ─────────────────────────────────────────────────────────────────────────────

/// One half of the week's timetable: seven days by three parts of the day.
/// Stored as a flat 21-cell grid in day-major order, which is exactly the
/// shape the mini week grid draws.
abstract final class Week {
  static const List<String> days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> dayLong = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> partKeys = <String>['Morn', 'Aft', 'Eve'];
  static const List<String> partShort = <String>['AM', 'PM', 'EVE'];
  static const List<String> partLong = <String>['mornings', 'afternoons', 'evenings'];

  static const int cells = 21;
  static int index(int day, int part) => day * 3 + part;
}

/// Reads `['Mon-Eve', 'Sat-Morn']` into the 21-cell grid.
///
/// Written as readable strings in the data below rather than 21 booleans,
/// because a wrong boolean is invisible in review and a wrong string is not.
List<bool> avail(List<String> keys) {
  final List<bool> grid = List<bool>.filled(Week.cells, false);
  for (final String key in keys) {
    final List<String> parts = key.split('-');
    if (parts.length != 2) {
      throw ArgumentError.value(key, 'key', 'Expected a slot like "Mon-Eve"');
    }
    final int day = Week.days.indexOf(parts[0]);
    final int part = Week.partKeys.indexOf(parts[1]);
    if (day < 0 || part < 0) {
      throw ArgumentError.value(key, 'key', 'Unknown day or part of day');
    }
    grid[Week.index(day, part)] = true;
  }
  return grid;
}

/// The hours both people are free. The whole point of the product.
List<bool> overlapOf(List<bool> a, List<bool> b) =>
    List<bool>.generate(Week.cells, (int i) => a[i] && b[i]);

/// Human sentence for the overlap, e.g. `Monday and Thursday evenings`.
/// Returns null when there is no overlap, so callers must handle that case
/// rather than printing "0 slots".
String? describeOverlap(List<bool> grid) {
  if (!grid.contains(true)) return null;
  final List<String> dayNames = <String>[];
  final Set<String> parts = <String>{};
  for (int d = 0; d < Week.days.length; d++) {
    final List<int> hit = <int>[
      for (int p = 0; p < Week.partKeys.length; p++)
        if (grid[Week.index(d, p)]) p,
    ];
    if (hit.isEmpty) continue;
    dayNames.add(Week.days[d]);
    for (final int p in hit) {
      parts.add(Week.partLong[p]);
    }
  }
  final String days = switch (dayNames.length) {
    1 => dayNames.first,
    2 => '${dayNames[0]} and ${dayNames[1]}',
    _ => '${dayNames.take(dayNames.length - 1).join(', ')} and ${dayNames.last}',
  };
  return '$days ${parts.length == 1 ? parts.first : 'at various times'}';
}

// ─────────────────────────────────────────────────────────────────────────────
// The five dimensions the recommender compares
// ─────────────────────────────────────────────────────────────────────────────

/// Weights and plain-language explanations live together on purpose: the
/// landing page promises the same mechanism the detail screen scores against.
enum MatchDimension {
  subjects(
    'Subjects',
    40,
    'What you need help with, set against what they actually teach or want to learn.',
    'Add one more subject and the list grows quickly — most tutors cover three or four.',
  ),
  time(
    'Available time',
    25,
    'The hours you are both free in a normal week, counted cell by cell.',
    'This is the dimension that empties a list. One shared block a week is often enough to start.',
  ),
  style(
    'Style',
    15,
    'How you like to work: worked examples, first principles, discussion, drill.',
    'Worth compromising last. A mismatch here is felt in every single session.',
  ),
  format(
    'Online or in person',
    10,
    'Whether either of you is willing to travel, or would rather stay on a call.',
    'Online widens the list more than any other single change on this page.',
  ),
  budget(
    'Budget',
    10,
    'The hourly rate against what the other side can spend.',
    'A five-dollar gap is usually one session a month, not a decision about quality.',
  );

  const MatchDimension(this.label, this.max, this.explainer, this.widening);

  final String label;
  final int max;
  final String explainer;

  /// What happens if you relax this one. Written per dimension, because
  /// "adjust your filters" is not advice.
  final String widening;

  String get weightCopy => '$max of 100';
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// How the recommender reached a score. Kept as five numbers rather than one,
/// so the detail screen can show its work.
class MatchScore {
  const MatchScore({
    required this.byDimension,
    required this.overlap,
  });

  final Map<MatchDimension, int> byDimension;
  final List<bool> overlap;

  int get total => byDimension.values.fold(0, (int a, int b) => a + b);
  int get overlapSlots => overlap.where((bool c) => c).length;
}

enum MatchTier { strong, good, possible, weak }

/// Thresholds are product copy, not maths: they decide which word a person
/// reads, so they live next to the words.
MatchTier tierFor(int score) => switch (score) {
      >= 80 => MatchTier.strong,
      >= 60 => MatchTier.good,
      >= 40 => MatchTier.possible,
      _ => MatchTier.weak,
    };

extension MatchTierCopy on MatchTier {
  String get label => switch (this) {
        MatchTier.strong => 'Strong match',
        MatchTier.good => 'Good match',
        MatchTier.possible => 'Worth a look',
        MatchTier.weak => 'Long shot',
      };

  /// What the word means, in words a person can act on.
  String get meaning => switch (this) {
        MatchTier.strong => 'Close on nearly everything that matters to you.',
        MatchTier.good => 'Solid on the important parts, with one real gap.',
        MatchTier.possible => 'Some overlap, but you would be compromising.',
        MatchTier.weak => 'Little in common. Shown so you can see the spread.',
      };

  StatusTone get tone => switch (this) {
        MatchTier.strong || MatchTier.good => StatusTone.accepted,
        MatchTier.possible => StatusTone.pending,
        MatchTier.weak => StatusTone.neutral,
      };
}

/// One plain-language reason, attached to the dimension that produced it.
class FitNote {
  const FitNote(this.dimension, this.signal, this.detail);

  /// The concrete fact, set in ink at the start of the line.
  final String signal;

  /// One clause on why it counts. Set quieter than the signal.
  final String detail;

  final MatchDimension dimension;
}

/// One row of the recommendation pool — a tutor when the viewer is a student,
/// a student when the viewer is a tutor. Same shape either way.
class Candidate {
  const Candidate({
    required this.id,
    required this.role,
    required this.name,
    required this.headline,
    required this.subjects,
    required this.styleLabel,
    required this.styleTags,
    required this.mode,
    required this.rate,
    required this.location,
    required this.rating,
    required this.reviews,
    required this.bio,
    required this.credentials,
    required this.languages,
    required this.availability,
    required this.fitSubjects,
    required this.fitStyle,
    required this.fitFormat,
    required this.fitBudget,
    required this.notes,
  });

  final String id;
  final Role role;
  final String name;

  /// One line under the name. Specific, never a slogan.
  final String headline;
  final List<String> subjects;
  final String styleLabel;
  final List<String> styleTags;
  final SessionMode mode;

  /// Hourly rate for a tutor; the student's own ceiling when role is student.
  final int rate;
  final String location;
  final double rating;
  final int reviews;
  final String bio;
  final List<String> credentials;
  final List<String> languages;
  final List<bool> availability;

  // Authored agreement scores, each already capped at MatchDimension.max.
  final int fitSubjects;
  final int fitStyle;
  final int fitFormat;
  final int fitBudget;

  final List<FitNote> notes;

  String get rateCopy => role == Role.tutor ? '\$$rate/hr' : 'up to \$$rate/hr';

  String get modeCopy => switch (mode) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Online or in person',
      };
}

enum SessionMode { online, inPerson, both }

extension SessionModeCopy on SessionMode {
  String get label => switch (this) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Either is fine',
      };

  /// What to say when the two sides disagree.
  String get counterLabel => switch (this) {
        SessionMode.online => 'in person',
        SessionMode.inPerson => 'online',
        SessionMode.both => 'either way',
      };

  bool accepts(SessionMode other) =>
      this == other || this == SessionMode.both || other == SessionMode.both;
}

/// The viewer's own answers. In memory only, gone on reload. Named `Profile`
/// and not `User` because there are no users here.
class Profile {
  const Profile({
    required this.role,
    required this.name,
    required this.subjects,
    required this.style,
    required this.mode,
    required this.budget,
    required this.availability,
    required this.goal,
  });

  final Role role;
  final String name;
  final List<String> subjects;
  final String style;
  final SessionMode mode;
  final int budget;
  final List<bool> availability;
  final String goal;

  Profile copyWith({
    Role? role,
    String? name,
    List<String>? subjects,
    String? style,
    SessionMode? mode,
    int? budget,
    List<bool>? availability,
    String? goal,
  }) =>
      Profile(
        role: role ?? this.role,
        name: name ?? this.name,
        subjects: subjects ?? this.subjects,
        style: style ?? this.style,
        mode: mode ?? this.mode,
        budget: budget ?? this.budget,
        availability: availability ?? this.availability,
        goal: goal ?? this.goal,
      );
}

enum RequestStatus { pending, accepted, declined }

extension RequestStatusCopy on RequestStatus {
  String get label => switch (this) {
        RequestStatus.pending => 'Pending',
        RequestStatus.accepted => 'Accepted',
        RequestStatus.declined => 'Rejected',
      };

  StatusTone get tone => switch (this) {
        RequestStatus.pending => StatusTone.pending,
        RequestStatus.accepted => StatusTone.accepted,
        RequestStatus.declined => StatusTone.declined,
      };
}

/// A request that has left your outbox or arrived in your inbox.
class MatchRequest {
  const MatchRequest({
    required this.id,
    required this.counterpartId,
    required this.counterpartName,
    required this.counterpartRole,
    required this.subject,
    required this.score,
    required this.status,
    required this.sentOn,
    required this.note,
    this.reply,
    this.outgoing = true,
  });

  final String id;
  final String counterpartId;
  final String counterpartName;
  final Role counterpartRole;
  final String subject;
  final int score;
  final RequestStatus status;
  final String sentOn;
  final String note;

  /// The other side's answer, when there is one. Never "OK".
  final String? reply;
  final bool outgoing;
}

// ─────────────────────────────────────────────────────────────────────────────
// Scoring
// ─────────────────────────────────────────────────────────────────────────────

/// The time dimension, computed from the real overlap. Five shared cells in a
/// week is treated as full marks; below that it scales linearly. One line,
/// deliberately: this is the only arithmetic in the UI and it should be
/// readable by whoever has to defend it.
int _timeFit(int overlapSlots) => (overlapSlots * 25 ~/ 5).clamp(0, MatchDimension.time.max);

MatchScore scoreOf(Candidate candidate, Profile viewer) {
  final List<bool> overlap = overlapOf(viewer.availability, candidate.availability);
  return MatchScore(
    overlap: overlap,
    byDimension: <MatchDimension, int>{
      MatchDimension.subjects: candidate.fitSubjects,
      MatchDimension.time: _timeFit(overlap.where((bool c) => c).length),
      MatchDimension.style: candidate.fitStyle,
      MatchDimension.format: candidate.fitFormat,
      MatchDimension.budget: candidate.fitBudget,
    },
  );
}

/// A ranked row: the person, the score, and the three reasons that earned it.
class MatchResult {
  final Candidate candidate;
  final MatchScore score;

  const MatchResult({required this.candidate, required this.score});

  int get rankScore => score.total;
  MatchTier get tier => tierFor(score.total);

  /// The three highest-proportion dimensions, best first, each rendered as a
  /// sentence. Time always competes on the same footing as the rest, so a
  /// candidate with no shared hours cannot hide behind good subjects.
  List<FitNote> get reasons {
    final List<FitNote> pool = <FitNote>[
      _timeNote(),
      ...candidate.notes,
    ];
    final Map<MatchDimension, int> fit = score.byDimension;
    pool.sort((FitNote a, FitNote b) {
      final double ra = fit[a.dimension]! / a.dimension.max;
      final double rb = fit[b.dimension]! / b.dimension.max;
      return rb.compareTo(ra);
    });
    return pool.take(3).toList(growable: false);
  }

  FitNote _timeNote() {
    final String? when = describeOverlap(score.overlap);
    if (when == null) {
      return const FitNote(
        MatchDimension.time,
        'No shared hours',
        'You are never free at the same time in a normal week — the one hard blocker here.',
      );
    }
    return FitNote(
      MatchDimension.time,
      when,
      'Both of you are free then, ${score.overlapSlots} hour-blocks that line up in a normal week.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Narrowing a ranked list — the filters, and what to say when they exclude
// everyone. This is where the empty state gets its sentence.
// ─────────────────────────────────────────────────────────────────────────────

class MatchFilters {
  const MatchFilters({
    this.subjects = const <String>{},
    this.mode,
    this.maxRate = 80,
    this.requiredParts = const <int>{},
    this.mustBeFreeWhenIAm = false,
    this.minScore = 0,
  });

  /// Empty means "any subject".
  final Set<String> subjects;
  final SessionMode? mode;
  final int maxRate;

  /// Which parts of the day you insist on. Empty means "any time".
  final Set<int> requiredParts;

  /// Off by default, and that is a deliberate product decision: an untouched
  /// list shows the whole pool, ranked, including the people whose week never
  /// crosses yours. They score near the bottom, they say why, and the person
  /// reading learns what the pool is like. Hiding them by default would make
  /// the list look smaller than the pool and the ranking look like magic.
  final bool mustBeFreeWhenIAm;
  final double minScore;

  MatchFilters copyWith({
    Set<String>? subjects,
    SessionMode? mode,
    bool clearMode = false,
    int? maxRate,
    Set<int>? requiredParts,
    bool? mustBeFreeWhenIAm,
    double? minScore,
  }) =>
      MatchFilters(
        subjects: subjects ?? this.subjects,
        mode: clearMode ? null : (mode ?? this.mode),
        maxRate: maxRate ?? this.maxRate,
        requiredParts: requiredParts ?? this.requiredParts,
        mustBeFreeWhenIAm: mustBeFreeWhenIAm ?? this.mustBeFreeWhenIAm,
        minScore: minScore ?? this.minScore,
      );

  bool get isNarrowed =>
      subjects.isNotEmpty ||
      mode != null ||
      maxRate < 80 ||
      requiredParts.isNotEmpty ||
      minScore > 0;
}

/// Says which condition removed everyone, and what to do about it. The copy is
/// generated from the filters that actually fired, so it cannot go stale.
class EmptyExplanation {
  const EmptyExplanation({
    required this.headline,
    required this.body,
    required this.adjustLabel,
    required this.relaxed,
    required this.recovered,
  });

  final String headline;
  final String body;
  final String adjustLabel;
  final MatchFilters relaxed;

  /// How many candidates the suggested adjustment brings back.
  final int recovered;
}

class MatchOutcome {
  const MatchOutcome({required this.results, this.empty});

  final List<MatchResult> results;
  final EmptyExplanation? empty;
}

/// Narrows a ranked list. Rank order is preserved: filtering never re-sorts,
/// because the order is the recommender's opinion and the filters are yours.
MatchOutcome applyFilters(
  List<MatchResult> ranked,
  MatchFilters filters,
  Profile viewer,
) {
  final List<MatchResult> kept = ranked.where((MatchResult r) => _passes(r, filters)).toList();
  if (kept.isNotEmpty) return MatchOutcome(results: kept);
  return MatchOutcome(results: const <MatchResult>[], empty: _explain(ranked, filters, viewer));
}

bool _passes(MatchResult r, MatchFilters f) {
  final Candidate c = r.candidate;
  if (f.subjects.isNotEmpty && !f.subjects.any(c.subjects.contains)) return false;
  if (f.mode != null && !f.mode!.accepts(c.mode)) return false;
  if (f.maxRate < 80 && c.rate > f.maxRate) return false;
  if (f.requiredParts.isNotEmpty) {
    final bool free = f.requiredParts.any((int p) {
      for (int d = 0; d < Week.days.length; d++) {
        if (r.score.overlap[Week.index(d, p)]) return true;
      }
      return false;
    });
    if (!free) return false;
  }
  if (f.mustBeFreeWhenIAm && r.score.overlapSlots == 0) return false;
  if (r.score.total < f.minScore) return false;
  return true;
}

/// Tries each condition on its own and recommends the one that costs the least
/// and returns the most. A relaxed filter is always something a person can
/// reverse in one click, which is why the suggestion carries a whole
/// [MatchFilters] back rather than a sentence about one.
EmptyExplanation _explain(
  List<MatchResult> ranked,
  MatchFilters f,
  Profile viewer,
) {
  final List<({String headline, String body, String label, MatchFilters next, int n})> options =
      <({String headline, String body, String label, MatchFilters next, int n})>[];

  int count(MatchFilters candidate) =>
      ranked.where((MatchResult r) => _passes(r, candidate)).length;

  // 1. Time — the most common blocker and the one people least expect.
  if (f.mustBeFreeWhenIAm || f.requiredParts.isNotEmpty) {
    final MatchFilters next = f.copyWith(
      mustBeFreeWhenIAm: false,
      requiredParts: const <int>{},
    );
    final int n = count(next);
    if (n > 0) {
      final String? when = _partsPhrase(f.requiredParts);
      options.add((
        headline: when == null
            ? 'Nobody in this list is free when you are.'
            : 'No tutor in your results is free on your $when.',
        body:
            '$n of the ${ranked.length} candidates match you on subjects, style and budget — '
            'their week and yours just never cross${when == null ? '' : ' on a $when'}. '
            'Showing every hour they do have brings them back.',
        label: 'Show all their hours, not just mine',
        next: next,
        n: n,
      ));
    }
  }

  // 2. Budget.
  if (f.maxRate < 80) {
    final int cheapest = ranked.map((MatchResult r) => r.candidate.rate).reduce((int a, int b) => a < b ? a : b);
    if (cheapest > f.maxRate) {
      final MatchFilters next = f.copyWith(maxRate: cheapest);
      options.add((
        headline: 'Nothing at or under \$${f.maxRate} an hour.',
        body: 'The lowest rate in your results is \$$cheapest, a \$${cheapest - f.maxRate} gap. '
            'Raising your ceiling by that much shows ${count(next)} of the ${ranked.length}, '
            'and the top of that list still scores '
            '${ranked.firstWhere((MatchResult r) => r.candidate.rate <= cheapest).score.total}.',
        label: 'Raise my ceiling to \$$cheapest/hr',
        next: next,
        n: count(next),
      ));
    }
  }

  // 3. Mode.
  if (f.mode != null) {
    final MatchFilters next = f.copyWith(clearMode: true, mode: null);
    final int n = count(next);
    if (n > 0) {
      options.add((
        headline: 'Every candidate left is ${f.mode!.counterLabel}-only.',
        body: 'You asked for ${f.mode!.label.toLowerCase()}. $n people fit you on '
            'subjects, hours and budget and are only available ${f.mode!.counterLabel}. '
            'If you can be flexible on that, they are worth reading.',
        label: 'Allow ${f.mode!.counterLabel} as well',
        next: next,
        n: n,
      ));
    }
  }

  // 4. Score floor.
  if (f.minScore > 0 && ranked.isNotEmpty) {
    final int best = ranked.first.rankScore;
    if (best < f.minScore) {
      final MatchFilters next = f.copyWith(minScore: 0);
      options.add((
        headline: 'Nothing reaches ${f.minScore.round()} out of 100.',
        body: 'The best available fit scores $best. That is the honest ceiling of this pool — '
            'lowering the bar does not improve the candidates, it just lets you see them, '
            'with their weak points shown instead of hidden.',
        label: 'Show me the best $best anyway',
        next: next,
        n: count(next),
      ));
    }
  }

  // 5. Subjects.
  if (f.subjects.isNotEmpty) {
    final MatchFilters next = f.copyWith(subjects: const <String>{});
    final int n = count(next);
    if (n > 0) {
      final Set<String> near = <String>{
        for (final MatchResult r in ranked) ...r.candidate.subjects,
      }..removeAll(f.subjects);
      options.add((
        headline: 'None of your ${f.subjects.length} chosen subjects come up in this list.',
        body: 'Dropping the subject filter shows $n of the ${ranked.length} candidates, '
            'and ${near.take(3).join(', ')} are covered by someone in it. '
            'The order does not change — a candidate is still ranked on all five dimensions.',
        label: 'Search across every subject',
        next: next,
        n: n,
      ));
    }
  }

  if (options.isEmpty) {
    // Either the pool is genuinely empty, or every condition is firing at once
    // and no single relaxation is enough. Saying which one it is, is the whole
    // job of this screen.
    if (ranked.isEmpty) {
      return EmptyExplanation(
        headline: 'There is nobody in the pool to rank.',
        body: 'The recommender has nothing to compare you against, so the list '
            'is empty before any filter is applied. That is a data problem on '
            'our side, not something about your profile — there is no filter '
            'here that would fix it.',
        adjustLabel: 'Go back to the form',
        relaxed: const MatchFilters(),
        recovered: 0,
      );
    }
    return EmptyExplanation(
      headline: 'No single change is enough on its own.',
      body: 'Every condition below is excluding everybody, and relaxing any one '
          'of them by itself still leaves nothing. They are listed under this '
          'message with each one removable — clearing them all starts again '
          'from the full ranked pool of ${ranked.length}.',
      adjustLabel: 'Clear every filter',
      relaxed: const MatchFilters(),
      recovered: ranked.length,
    );
  }

  // The cheapest useful change: most results recovered, and when two conditions
  // recover the same number, the earlier one wins because it is the smaller ask.
  options.sort((a, b) => b.n.compareTo(a.n));
  final ({String headline, String body, String label, MatchFilters next, int n}) best = options.first;
  return EmptyExplanation(
    headline: best.headline,
    body: best.body,
    adjustLabel: best.label,
    relaxed: best.next,
    recovered: best.n,
  );
}

String? _partsPhrase(Set<int> parts) {
  if (parts.isEmpty) return null;
  final List<String> names = <String>[
    for (final int p in parts.toList()..sort()) Week.partLong[p],
  ];
  return switch (names.length) {
    1 => names.first,
    2 => '${names[0]} or ${names[1]}',
    _ => '${names.take(names.length - 1).join(', ')} or ${names.last}',
  };
}

/// Ranks a pool for a viewer. Sorted by score, then by rating, then by name so
/// the order is never arbitrary between two equal scores.
List<MatchResult> rank(List<Candidate> pool, Profile viewer) {
  final List<MatchResult> ranked = pool
      .map((Candidate c) => MatchResult(candidate: c, score: scoreOf(c, viewer)))
      .toList();
  ranked.sort((MatchResult a, MatchResult b) {
    final int byScore = b.rankScore.compareTo(a.rankScore);
    if (byScore != 0) return byScore;
    final int byRating = b.candidate.rating.compareTo(a.candidate.rating);
    if (byRating != 0) return byRating;
    return a.candidate.name.compareTo(b.candidate.name);
  });
  return ranked;
}

// ═════════════════════════════════════════════════════════════════════════════
// THE POOL
// ═════════════════════════════════════════════════════════════════════════════

/// Tutors, as a student would see them.
final List<Candidate> sampleTutors = <Candidate>[
  Candidate(
    id: 't-amara',
    role: Role.tutor,
    name: 'Amara Okonkwo',
    headline: 'Calculus and statistics, nine years, ex-exam marker',
    subjects: <String>['Calculus', 'Statistics', 'Algebra'],
    styleLabel: 'Structured worked examples',
    styleTags: <String>['Worked examples', 'Exam technique', 'Weekly problem sets'],
    mode: SessionMode.online,
    rate: 46,
    location: 'Online, from Manchester',
    rating: 4.9,
    reviews: 128,
    bio: 'I mark the papers your students are about to sit. After nine years of '
        'that, I teach the way the marks are actually given: one worked example, '
        'then you do the next one while I watch where it goes wrong. No lecture '
        'recordings, no slides.',
    credentials: <String>['MSc Mathematics, Manchester', 'A-level examiner since 2019'],
    languages: <String>['English', 'Igbo'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 14,
    fitFormat: 10,
    fitBudget: 9,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus, and it is the subject you flagged',
        'Nine years teaching it, plus exam-board marking since 2019 — she knows what the marks are awarded for.',
      ),
      FitNote(
        MatchDimension.style,
        'Worked examples, one at a time',
        'You said you learn by watching a problem solved and then doing the next one yourself.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$46 an hour',
        'One dollar above your ceiling. That is the only place this match costs you anything.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'Screen-shared working, with the recording kept for the week before an exam.',
      ),
    ],
  ),
  Candidate(
    id: 't-liang',
    role: Role.tutor,
    name: 'Liang Chen',
    headline: 'Calculus and physics through competition problems',
    subjects: <String>['Calculus', 'Physics', 'Algebra'],
    styleLabel: 'Hard problems, discussed',
    styleTags: <String>['Olympiad problems', 'Proof', 'Derivation'],
    mode: SessionMode.both,
    rate: 49,
    location: 'Riverside, and online',
    rating: 4.9,
    reviews: 74,
    bio: 'I coached the regional olympiad squad for four years. My first lesson '
        'is usually a problem you cannot solve, because the useful part of the '
        'hour is finding out exactly where your reasoning stops.',
    credentials: <String>['BSc Physics, Imperial', 'Regional olympiad coach 2020-2024'],
    languages: <String>['English', 'Mandarin'],
    availability: avail(const <String>['Tue-Eve', 'Fri-Eve', 'Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 12,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus and physics together',
        'Both of your focus subjects, and he teaches them as one subject rather than two.',
      ),
      FitNote(
        MatchDimension.style,
        'Starts from a problem you cannot do',
        'Harder than your stated preference, but it is the fastest route through the topics you named.',
      ),
      FitNote(
        MatchDimension.format,
        'Will travel or teach online',
        'You can move a session at a day\'s notice without losing the slot.',
      ),
    ],
  ),
  Candidate(
    id: 't-hana',
    role: Role.tutor,
    name: 'Hana Suzuki',
    headline: 'Physics, derived from first principles',
    subjects: <String>['Physics', 'Calculus'],
    styleLabel: 'Derivation before formula',
    styleTags: <String>['First principles', 'Diagrams', 'Exam technique'],
    mode: SessionMode.online,
    rate: 52,
    location: 'Online, from Leeds',
    rating: 4.9,
    reviews: 96,
    bio: 'Students arrive with a formula sheet and no idea where the formulas '
        'came from. We rebuild them. It is slower for three weeks and then '
        'noticeably faster for the rest of the year.',
    credentials: <String>['PhD Physics, Leeds', 'PGCE'],
    languages: <String>['English', 'Japanese'],
    availability: avail(const <String>['Tue-Eve', 'Wed-Eve', 'Fri-Eve', 'Sun-Aft']),
    fitSubjects: 40,
    fitStyle: 11,
    fitFormat: 10,
    fitBudget: 6,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Physics, and the calculus underneath it',
        'Exactly the pairing you asked for, taught by someone with a doctorate in it.',
      ),
      FitNote(
        MatchDimension.style,
        'Derives before using',
        'Close to your preference: still worked examples, but she builds each one from the definition up.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$52 an hour',
        'Six dollars above your ceiling, the largest budget gap in your top five.',
      ),
    ],
  ),
  Candidate(
    id: 't-greta',
    role: Role.tutor,
    name: 'Greta Lindqvist',
    headline: 'Statistics you can actually use, via real datasets',
    subjects: <String>['Statistics', 'Computer Science', 'Calculus'],
    styleLabel: 'Project-based',
    styleTags: <String>['Real datasets', 'R and Python', 'Write-ups'],
    mode: SessionMode.online,
    rate: 58,
    location: 'Online, from Edinburgh',
    rating: 5.0,
    reviews: 61,
    bio: 'We pick a dataset in week one — football results, your own sleep '
        'tracker, whatever — and every technique gets used on it. By the end you '
        'have one piece of work you understand completely.',
    credentials: <String>['MSc Data Science, Edinburgh', 'Statistical consultant'],
    languages: <String>['English', 'Swedish'],
    availability: avail(const <String>['Tue-Eve', 'Thu-Eve', 'Sat-Aft']),
    fitSubjects: 34,
    fitStyle: 9,
    fitFormat: 10,
    fitBudget: 4,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, applied rather than abstract',
        'One of your three subjects. She also covers the calculus that statistics leans on.',
      ),
      FitNote(
        MatchDimension.style,
        'Project-based, less exam drill',
        'A different approach from the worked examples you asked for. Better for understanding, weaker for sprinting to a test.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'Sessions are screen-share by default, which suits the coding side.',
      ),
    ],
  ),
  Candidate(
    id: 't-samir',
    role: Role.tutor,
    name: 'Samir Haddad',
    headline: 'SAT prep with an error log that does the work',
    subjects: <String>['SAT Prep', 'Algebra', 'Statistics'],
    styleLabel: 'Drill and review',
    styleTags: <String>['Timed sections', 'Error log', 'Weekly review'],
    mode: SessionMode.both,
    rate: 40,
    location: 'Fitzroy, and online',
    rating: 4.7,
    reviews: 143,
    bio: 'Every wrong answer gets written into a log with the reason it went '
        'wrong: misread, guessed, or genuinely did not know. Two weeks in, the '
        'log tells us what to study and I stop guessing.',
    credentials: <String>['BA Mathematics, Melbourne', 'Seven years of SAT coaching'],
    languages: <String>['English', 'Arabic'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Fri-Eve', 'Sun-Eve']),
    fitSubjects: 30,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Error logs and timed sections',
        'Very close to how you said you want to work: repetition, then a review of what broke.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Covers your algebra and statistics',
        'Not calculus, but both of the other subjects you listed, plus the SAT paper itself.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$40 an hour, under your ceiling',
        'Four full sessions a month still leaves room in the budget you gave.',
      ),
    ],
  ),
  Candidate(
    id: 't-tomas',
    role: Role.tutor,
    name: 'Tomás Ferreira',
    headline: 'Morning lessons before school, Spanish and history',
    subjects: <String>['Spanish', 'History'],
    styleLabel: 'Conversation first',
    styleTags: <String>['Speaking', 'Primary sources', 'No grammar drills'],
    mode: SessionMode.online,
    rate: 28,
    location: 'Online, from Porto',
    rating: 4.6,
    reviews: 52,
    bio: 'We talk for fifty minutes and I correct afterwards, in a list. Grammar '
        'comes last because it is the part you can look up.',
    credentials: <String>['BA Modern Languages, Porto'],
    languages: <String>['English', 'Portuguese', 'Spanish'],
    availability: avail(const <String>['Mon-Morn', 'Tue-Morn', 'Wed-Morn', 'Thu-Morn']),
    fitSubjects: 6,
    fitStyle: 4,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$28 an hour',
        'The cheapest option in this pool and comfortably inside your ceiling.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'His timezone is an hour ahead, which is what put his lessons in your mornings.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Spanish and history only',
        'Neither appears in your subject list. This is the main reason he ranks where he does.',
      ),
    ],
  ),
  // ── Candidates below the fold, kept in the pool so the list has a floor to
  // ── stand on and the weaker matches stay honest about why they are weaker.
  Candidate(
    id: 't-daniel',
    role: Role.tutor,
    name: 'Daniel Reyes',
    headline: 'Slow, patient algebra for students who got left behind',
    subjects: <String>['Algebra', 'Geometry'],
    styleLabel: 'Step by step, no rushing',
    styleTags: <String>['Foundations', 'Weekly homework', 'Parent updates'],
    mode: SessionMode.both,
    rate: 38,
    location: 'Camden, and online',
    rating: 4.8,
    reviews: 87,
    bio: 'Most of the students I see were marked down somewhere in year 8 and '
        'never caught up. We go back to that point and walk forward.',
    credentials: <String>['BEd Secondary Mathematics'],
    languages: <String>['English', 'Spanish'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Eve', 'Fri-Aft', 'Sat-Morn']),
    fitSubjects: 24,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Step by step and unhurried',
        'Very close to the worked-example style you picked.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$38 an hour',
        'Well inside your ceiling, with room for an extra session before exams.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Algebra and geometry, no calculus',
        'He does not teach either of your two main subjects, which caps the score.',
      ),
    ],
  ),
  Candidate(
    id: 't-priya',
    role: Role.tutor,
    name: 'Priya Raghavan',
    headline: 'Chemistry and biology, anchored in the lab work',
    subjects: <String>['Chemistry', 'Biology'],
    styleLabel: 'Diagrams and practicals',
    styleTags: <String>['Past papers', 'Required practicals', 'Mark schemes'],
    mode: SessionMode.both,
    rate: 44,
    location: 'Hackney, and online',
    rating: 4.8,
    reviews: 102,
    bio: 'The required practicals are where most marks quietly disappear. I '
        'teach them from the diagrams up, then we do past papers until the '
        'marks are boring.',
    credentials: <String>['BSc Biochemistry, UCL', 'PGCE'],
    languages: <String>['English', 'Tamil'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Sat-Aft', 'Sun-Aft']),
    fitSubjects: 10,
    fitStyle: 7,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Will teach online or in person',
        'You can switch to a call during exam week without changing tutor.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$44 an hour',
        'Inside the ceiling you set.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Chemistry and biology',
        'Neither is on your list. Strong tutor, wrong two subjects for you.',
      ),
    ],
  ),
  Candidate(
    id: 't-marcus',
    role: Role.tutor,
    name: 'Marcus Bell',
    headline: 'Essay writing by rewriting your own sentences',
    subjects: <String>['Essay Writing', 'English Literature', 'History'],
    styleLabel: 'Workshop and feedback loops',
    styleTags: <String>['Draft and redraft', 'Argument structure', 'Mark scheme'],
    mode: SessionMode.inPerson,
    rate: 34,
    location: 'Islington, in person only',
    rating: 4.7,
    reviews: 68,
    bio: 'You send me the draft. I mark it the way the exam board would, then we '
        'spend the hour cutting the two paragraphs that weaken the argument.',
    credentials: <String>['MA English, KCL'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft']),
    fitSubjects: 8,
    fitStyle: 6,
    fitFormat: 3,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$34 an hour',
        'Cheap for the experience. That is genuinely the strongest line here.',
      ),
      FitNote(
        MatchDimension.style,
        'Feedback loops, not worked examples',
        'You learn by iteration rather than by demonstration, which is a real difference.',
      ),
      FitNote(
        MatchDimension.format,
        'In person only, in Islington',
        'You said online. Travel is not optional with Marcus, which is what pushes him down the list.',
      ),
    ],
  ),
  Candidate(
    id: 't-jonah',
    role: Role.tutor,
    name: 'Jonah Pike',
    headline: 'Biology and chemistry for the year-10 jump',
    subjects: <String>['Biology', 'Chemistry'],
    styleLabel: 'Diagram-first',
    styleTags: <String>['Visual notes', 'Flashcard decks', 'Short sessions'],
    mode: SessionMode.online,
    rate: 30,
    location: 'Online, from Bristol',
    rating: 4.5,
    reviews: 29,
    bio: 'Three years in, still cheap while I build up reviews. I teach the '
        'diagram before the paragraph, because the paragraph is easier once the '
        'picture is there.',
    credentials: <String>['BSc Biomedical Science'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Thu-Eve', 'Fri-Eve']),
    fitSubjects: 8,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, and free every weeknight',
        'Widest availability in this pool, which is why the grid lights up even though the subjects do not.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$30 an hour',
        'The second cheapest in the list.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Biology and chemistry',
        'No overlap with what you asked for. Read the grid, not the score.',
      ),
    ],
  ),
  Candidate(
    id: 't-rachel',
    role: Role.tutor,
    name: 'Rachel Osei',
    headline: 'History essays: map the argument before writing',
    subjects: <String>['History', 'Essay Writing'],
    styleLabel: 'Argument mapping',
    styleTags: <String>['Source analysis', 'Planning', 'Timed essays'],
    mode: SessionMode.online,
    rate: 36,
    location: 'Online, from Birmingham',
    rating: 4.8,
    reviews: 54,
    bio: 'Nine times out of ten the problem is not the writing, it is that the '
        'argument has three claims in it. We map it on one page first, then the '
        'essay writes itself in half the time.',
    credentials: <String>['MA History, Warwick'],
    languages: <String>['English', 'Twi'],
    availability: avail(const <String>['Wed-Eve', 'Thu-Eve', 'Sun-Eve']),
    fitSubjects: 6,
    fitStyle: 6,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, in a timezone that matches yours',
        'No travel, and she keeps one evening slot free every week.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$36 an hour',
        'Comfortably inside your ceiling.',
      ),
      FitNote(
        MatchDimension.subjects,
        'History and essay writing',
        'Outside your stated subjects, which is the whole reason she is not higher.',
      ),
    ],
  ),
  Candidate(
    id: 't-nora',
    role: Role.tutor,
    name: 'Nora Bergman',
    headline: 'Geometry by construction, with compass and straight edge',
    subjects: <String>['Geometry', 'Algebra'],
    styleLabel: 'Visual proofs',
    styleTags: <String>['Constructions', 'Proof', 'No calculators'],
    mode: SessionMode.inPerson,
    rate: 42,
    location: 'Sheffield, in person only',
    rating: 4.8,
    reviews: 45,
    bio: 'We draw everything before we write anything. It is slower for a term, '
        'and then geometry stops being a memory test.',
    credentials: <String>['BSc Mathematics, Sheffield'],
    languages: <String>['English', 'German'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft', 'Sat-Morn']),
    fitSubjects: 24,
    fitStyle: 10,
    fitFormat: 7,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Algebra, and the geometry behind it',
        'One of your subjects, taught in a way that sticks.',
      ),
      FitNote(
        MatchDimension.style,
        'Draw it before you write it',
        'A cousin of worked examples, so it transfers.',
      ),
      FitNote(
        MatchDimension.format,
        'In person, in Sheffield',
        'Only workable if you are near her. That is the decision this match turns on.',
      ),
    ],
  ),
  Candidate(
    id: 't-ibrahim',
    role: Role.tutor,
    name: 'Ibrahim Touré',
    headline: 'Statistics and code, learned by building',
    subjects: <String>['Computer Science', 'Statistics'],
    styleLabel: 'Build first',
    styleTags: <String>['Python', 'Projects', 'Portfolio'],
    mode: SessionMode.online,
    rate: 55,
    location: 'Online, from Paris',
    rating: 4.9,
    reviews: 71,
    bio: 'You will write more code than you expect in the first hour. We only '
        'open the textbook when the code does something you cannot explain.',
    credentials: <String>['MEng Computer Science', 'Backend engineer'],
    languages: <String>['English', 'French'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Sat-Morn']),
    fitSubjects: 16,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 6,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Build first, explain second',
        'You asked for worked examples. This is the opposite order and it suits some people better.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, and generous with evenings',
        'Four evenings a week, including the two you are normally free.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$55 an hour',
        'The second largest gap to your ceiling in this list.',
      ),
    ],
  ),
  Candidate(
    id: 't-evelyn',
    role: Role.tutor,
    name: 'Evelyn Marsh',
    headline: 'Music theory, taught by ear first',
    subjects: <String>['Music Theory'],
    styleLabel: 'Ear first, notation second',
    styleTags: <String>['Listening', 'Harmony', 'Grade exams'],
    mode: SessionMode.inPerson,
    rate: 32,
    location: 'Bath, in person only',
    rating: 4.9,
    reviews: 158,
    bio: 'Fifteen years of grade-exam preparation. My students hear the cadence '
        'before they can name it, which is the right order.',
    credentials: <String>['ABRSM Grade 8 distinction', 'DipABRSM'],
    languages: <String>['English'],
    availability: avail(const <String>['Tue-Aft', 'Thu-Aft', 'Sat-Morn']),
    fitSubjects: 4,
    fitStyle: 3,
    fitFormat: 7,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$32 an hour',
        'Reasonable, and she has fifteen years behind it.',
      ),
      FitNote(
        MatchDimension.format,
        'In person only',
        'You asked for online. Ear training genuinely needs the room.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Music theory, nothing else',
        'One subject, and not one of yours. She is in this list so you can see that a five-star tutor can still be the wrong tutor.',
      ),
    ],
  ),
  Candidate(
    id: 't-claire',
    role: Role.tutor,
    name: 'Claire Dubois',
    headline: 'Literature by question, not by summary',
    subjects: <String>['English Literature', 'Essay Writing'],
    styleLabel: 'Socratic',
    styleTags: <String>['Discussion', 'Close reading', 'No notes given'],
    mode: SessionMode.online,
    rate: 33,
    location: 'Online, from Lyon',
    rating: 4.7,
    reviews: 39,
    bio: 'I will not give you a summary of the book. I will ask you questions '
        'until you produce one, and that one you will remember.',
    credentials: <String>['MA Comparative Literature'],
    languages: <String>['English', 'French'],
    availability: avail(const <String>['Thu-Eve', 'Fri-Eve', 'Sun-Eve']),
    fitSubjects: 6,
    fitStyle: 5,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, one evening a week',
        'A single usable slot, which makes scheduling brittle even though the format fits.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$33 an hour',
        'Inside your ceiling with room to spare.',
      ),
      FitNote(
        MatchDimension.subjects,
        'English literature and essay writing',
        'Not your subjects. The score is being honest about that.',
      ),
    ],
  ),
  Candidate(
    id: 't-victor',
    role: Role.tutor,
    name: 'Victor Alvarez',
    headline: 'History from primary sources, afternoons only',
    subjects: <String>['History', 'Spanish'],
    styleLabel: 'Primary sources',
    styleTags: <String>['Archive work', 'Source questions', 'Debate'],
    mode: SessionMode.inPerson,
    rate: 31,
    location: 'Oxford, in person only',
    rating: 4.6,
    reviews: 33,
    bio: 'We read what was actually written at the time, badly translated and '
        'all, and then argue about it. Source questions stop being a trick.',
    credentials: <String>['BA History, Salamanca'],
    languages: <String>['English', 'Spanish'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Aft', 'Fri-Aft']),
    fitSubjects: 6,
    fitStyle: 4,
    fitFormat: 3,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$31 an hour',
        'Cheap, and it is the only thing that lines up.',
      ),
      FitNote(
        MatchDimension.subjects,
        'History and Spanish',
        'No overlap with your subjects at all.',
      ),
      FitNote(
        MatchDimension.format,
        'Weekday afternoons only, in person',
        'Two independent blockers: the format and the hours. This is what a bottom-of-list match looks like.',
      ),
    ],
  ),
];

/// Students, as a tutor would see them.
final List<Candidate> sampleStudents = <Candidate>[
  Candidate(
    id: 's-maya',
    role: Role.student,
    name: 'Maya Chen',
    headline: 'Year 12, needs calculus from a B+ to an A before mocks',
    subjects: <String>['Calculus', 'Physics'],
    styleLabel: 'Watches one, then does one',
    styleTags: <String>['Worked examples', 'Weekly homework', 'Mock papers'],
    mode: SessionMode.both,
    rate: 45,
    location: 'Highbury, will travel 3 km',
    rating: 4.9,
    reviews: 3,
    bio: 'I am fine in class and then I freeze on the harder questions in the '
        'exam. I have the mock in eleven weeks and a folder of past papers '
        'already printed.',
    credentials: <String>['Year 12', 'Predicted A- in maths', 'A in physics'],
    languages: <String>['English', 'Mandarin'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 34,
    fitStyle: 14,
    fitFormat: 10,
    fitBudget: 9,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus, and physics that leans on it',
        'Your two subjects, and she already has the past papers printed.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants to watch one, then do one',
        'Identical to how you teach. Almost no adaptation needed on your side.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$45 an hour ceiling',
        'One dollar below your rate, and she said so plainly rather than haggling later.',
      ),
    ],
  ),
  Candidate(
    id: 's-aisha',
    role: Role.student,
    name: 'Aisha Rahman',
    headline: 'Year 13, statistics and algebra for a medicine application',
    subjects: <String>['Statistics', 'Algebra', 'SAT Prep'],
    styleLabel: 'Drills under time pressure',
    styleTags: <String>['Timed practice', 'Error log', 'Grade 9 target'],
    mode: SessionMode.online,
    rate: 50,
    location: 'Online only, two hours ahead of you',
    rating: 4.9,
    reviews: 4,
    bio: 'Grade 8 predicted, need a 9 for the course I want. I do not need '
        'understanding, I need speed and fewer careless errors.',
    credentials: <String>['Year 13', 'Predicted A in statistics'],
    languages: <String>['English', 'Bengali'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 30,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, your main subject',
        'Plus algebra, and a clear reason for wanting both.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants timed practice and an error log',
        'You can reuse the same error-log format you already run for exam students.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$50 an hour ceiling',
        'Above your rate, so no negotiation is needed at any point.',
      ),
    ],
  ),
  Candidate(
    id: 's-ethan',
    role: Role.student,
    name: 'Ethan Brooks',
    headline: 'Year 13, calculus and statistics, but only on Saturday mornings',
    subjects: <String>['Calculus', 'Statistics'],
    styleLabel: 'First principles',
    styleTags: <String>['Derivation', 'Proof', 'Long sessions'],
    mode: SessionMode.online,
    rate: 60,
    location: 'Online only',
    rating: 4.8,
    reviews: 5,
    bio: 'I want to understand where the results come from rather than memorise '
        'them. I have one free morning a week and I would rather use two hours '
        'of it than one.',
    credentials: <String>['Year 13', 'Further maths', 'Physics olympiad bronze'],
    languages: <String>['English'],
    availability: avail(const <String>['Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 11,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Exactly your two subjects, at a serious level',
        'Further maths and olympiad work — you would not be simplifying anything.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants derivations, not shortcuts',
        'Close to your worked-example approach; he will want the proof as well.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$60 an hour ceiling',
        'The highest budget in your inbox, and it is not the reason to take him.',
      ),
    ],
  ),
  Candidate(
    id: 's-kai',
    role: Role.student,
    name: 'Kai Nakamura',
    headline: 'Year 12, statistics through a project he already started',
    subjects: <String>['Statistics', 'Computer Science'],
    styleLabel: 'Learn by building',
    styleTags: <String>['Python', 'Own dataset', 'Portfolio'],
    mode: SessionMode.online,
    rate: 60,
    location: 'Online only, one hour ahead of you',
    rating: 4.7,
    reviews: 6,
    bio: 'I have three years of cycling data and a half-finished analysis. I '
        'want a tutor who will help me finish it properly rather than start a '
        'textbook from chapter one.',
    credentials: <String>['Year 12', 'Python since year 8'],
    languages: <String>['English', 'Japanese'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve']),
    fitSubjects: 26,
    fitStyle: 9,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, applied to his own data',
        'Your main subject, used immediately on something he cares about.',
      ),
      FitNote(
        MatchDimension.style,
        'Project-led rather than exercise-led',
        'The opposite of your usual format. It works, but it is a different lesson to plan.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in a timezone that mostly lines up',
        'Three evening slots a week, one hour ahead of you.',
      ),
    ],
  ),
  Candidate(
    id: 's-leo',
    role: Role.student,
    name: 'Leo Novak',
    headline: 'Year 11, chemistry and biology, revision in the evenings',
    subjects: <String>['Chemistry', 'Biology'],
    styleLabel: 'Flashcards and past papers',
    styleTags: <String>['Revision', 'Grade 6 target', 'Short sessions'],
    mode: SessionMode.online,
    rate: 35,
    location: 'Online only',
    rating: 4.6,
    reviews: 2,
    bio: 'I am on a grade 5 in both and I need a 6 to take either at A-level. '
        'I do not need to love it, I need to pass it.',
    credentials: <String>['Year 11'],
    languages: <String>['English', 'Polish'],
    availability: avail(const <String>['Tue-Eve', 'Wed-Eve', 'Thu-Eve']),
    fitSubjects: 8,
    fitStyle: 10,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$35 an hour ceiling',
        'Inside your rate with room for an extra session a month.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in the evenings',
        'Fits the three evenings you keep free.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Chemistry and biology',
        'Neither is a subject you teach. The budget line is the only strong one.',
      ),
    ],
  ),
  Candidate(
    id: 's-sofia',
    role: Role.student,
    name: 'Sofia Marino',
    headline: 'Year 12, essay writing for coursework deadlines',
    subjects: <String>['Essay Writing', 'English Literature'],
    styleLabel: 'Feedback on drafts',
    styleTags: <String>['Redrafting', 'Structure', 'Coursework'],
    mode: SessionMode.online,
    rate: 40,
    location: 'Online only',
    rating: 4.6,
    reviews: 3,
    bio: 'My ideas are fine and my structure is not. I need someone to read a '
        'draft and tell me which paragraph to cut, not to tell me to plan better.',
    credentials: <String>['Year 12', 'A in English literature'],
    languages: <String>['English', 'Italian'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Thu-Eve']),
    fitSubjects: 6,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$40 an hour ceiling',
        'Below your rate, so she can afford weekly rather than fortnightly.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in the evenings',
        'Overlaps two of your free evenings.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Essay writing and literature',
        'Not subjects you teach. She would be a poor fit for you despite being an easy student.',
      ),
    ],
  ),
  Candidate(
    id: 's-owen',
    role: Role.student,
    name: 'Owen Pratt',
    headline: 'Year 10, algebra in the afternoons, needs the basics rebuilt',
    subjects: <String>['Algebra', 'Geometry'],
    styleLabel: 'Slow and patient',
    styleTags: <String>['Foundations', 'Homework help', 'Weekly'],
    mode: SessionMode.inPerson,
    rate: 40,
    location: 'Camden, in person only',
    rating: 4.5,
    reviews: 2,
    bio: 'I lost the plot somewhere in year 8 and nobody noticed. I would rather '
        'go back and fix it than keep pretending.',
    credentials: <String>['Year 10'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Aft', 'Fri-Aft']),
    fitSubjects: 18,
    fitStyle: 12,
    fitFormat: 4,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Wants slow and patient',
        'A genuine match on temperament, with someone who has admitted the gap.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$40 an hour ceiling',
        'Inside your rate.',
      ),
      FitNote(
        MatchDimension.format,
        'In person, in the afternoons',
        'Not online, and not in the evening — two mismatches at once.',
      ),
    ],
  ),
  Candidate(
    id: 's-nadia',
    role: Role.student,
    name: 'Nadia Haddad',
    headline: 'Year 10, Spanish and history, after school',
    subjects: <String>['Spanish', 'History'],
    styleLabel: 'Conversation and reading',
    styleTags: <String>['Speaking', 'Source work', 'No exams yet'],
    mode: SessionMode.inPerson,
    rate: 30,
    location: 'Bath, in person only',
    rating: 4.4,
    reviews: 1,
    bio: 'Languages are the only lessons I look forward to. I want to actually '
        'speak it, not just pass the paper.',
    credentials: <String>['Year 10'],
    languages: <String>['English', 'Arabic'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft']),
    fitSubjects: 5,
    fitStyle: 9,
    fitFormat: 4,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Conversation-led, which matches how she is taught at school',
        'The clearest line in this match, and it is not the one that decides it.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Spanish and history',
        'Outside your subjects.',
      ),
      FitNote(
        MatchDimension.format,
        'In person, in Bath, on weekday afternoons',
        'Three mismatches on one line. This is the bottom of the list and it should be.',
      ),
    ],
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// Onboarding options — the answer sets the recommender can actually use
// ═════════════════════════════════════════════════════════════════════════════

abstract final class OnboardingOptions {
  static const List<String> subjects = <String>[
    'Algebra',
    'Geometry',
    'Calculus',
    'Statistics',
    'Physics',
    'Chemistry',
    'Biology',
    'English Literature',
    'Essay Writing',
    'History',
    'Spanish',
    'Computer Science',
    'Music Theory',
    'SAT Prep',
  ];

  static const List<String> studentStyles = <String>[
    'Watch one worked example, then do the next one myself',
    'Start from the theory and derive everything',
    'Talk it through until it makes sense',
    'Drill past papers under time pressure',
    'Learn it by building or making something',
  ];

  static const List<String> tutorStyles = <String>[
    'I work through examples slowly and let the student steer',
    'I go back to first principles and build up',
    'I teach by discussion and questioning',
    'I run timed practice and review the errors',
    'I teach by getting the student to build something',
  ];

  static const List<String> studentGoals = <String>[
    'Pass a specific exam that is coming up',
    'Move up a grade or two this year',
    'Understand the subject properly, not just pass it',
    'Catch up on foundations I missed earlier',
    'Decide whether to take this subject further',
  ];

  static const List<String> tutorGoals = <String>[
    'Fill a few steady evenings a week',
    'Take on one or two exam-year students before mocks',
    'Work with beginners who need foundations rebuilt',
    'Teach the hardest material to students who want it',
    'Build up reviews and a regular timetable',
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Requests — a static inbox per side, so the three tabs have something honest
// in them. A student reads [sampleRequests] (their outbox); a tutor reads
// [sampleReceivedRequests] (their inbox). Same six shapes either way, written
// from the side that actually wrote them.
// ═════════════════════════════════════════════════════════════════════════════

const List<MatchRequest> sampleRequests = <MatchRequest>[
  MatchRequest(
    id: 'r-1041',
    counterpartId: 't-amara',
    counterpartName: 'Amara Okonkwo',
    counterpartRole: Role.tutor,
    subject: 'Calculus',
    score: 93,
    status: RequestStatus.accepted,
    sentOn: 'Sent Mon 6 Oct',
    note: 'Mock in eleven weeks. Weekday evenings after 6, and I can do Saturday morning if that is easier for you.',
    reply: 'Yes — I have Tuesday and Thursday free from next week. Send me your last mock paper and I will look at it before we start.',
  ),
  MatchRequest(
    id: 'r-1038',
    counterpartId: 't-liang',
    counterpartName: 'Liang Chen',
    counterpartRole: Role.tutor,
    subject: 'Calculus and Physics',
    score: 82,
    status: RequestStatus.pending,
    sentOn: 'Sent Sun 5 Oct',
    note: 'Interested in both subjects together if that works. I am free Tuesday and Friday evenings.',
  ),
  MatchRequest(
    id: 'r-1036',
    counterpartId: 't-hana',
    counterpartName: 'Hana Suzuki',
    counterpartRole: Role.tutor,
    subject: 'Physics',
    score: 77,
    status: RequestStatus.pending,
    sentOn: 'Sent Fri 3 Oct',
    note: 'Would you start with mechanics or electricity? I am weaker on mechanics.',
  ),
  MatchRequest(
    id: 'r-1030',
    counterpartId: 't-marcus',
    counterpartName: 'Marcus Bell',
    counterpartRole: Role.tutor,
    subject: 'Essay Writing',
    score: 61,
    status: RequestStatus.declined,
    sentOn: 'Sent Tue 30 Sep',
    note: 'I know you are in person only — I could travel on Thursdays if that is possible.',
    reply: 'Afraid not — my Thursdays filled up for the term. Rachel Osei does the same work online and she is good. Worth trying her.',
  ),
  MatchRequest(
    id: 'r-1029',
    counterpartId: 't-evelyn',
    counterpartName: 'Evelyn Marsh',
    counterpartRole: Role.tutor,
    subject: 'Music Theory',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Mon 29 Sep',
    note: 'Long shot — you are in Bath and I am not, but I wanted to ask about online grade 5 theory.',
    reply: 'I only teach in person, I am afraid. For grade 5 theory online, try the ABRSM practice papers first — most people need less teaching than they think there.',
  ),
  MatchRequest(
    id: 'r-1044',
    counterpartId: 't-greta',
    counterpartName: 'Greta Lindqvist',
    counterpartRole: Role.tutor,
    subject: 'Statistics',
    score: 71,
    status: RequestStatus.pending,
    sentOn: 'Sent Wed 8 Oct',
    note: 'Are you taking on new students in January? I would rather wait for a slot than start with someone else.',
  ),
];

/// Students' requests, as the tutor sees them: the mirror of [sampleRequests].
/// Written from the side that actually wrote them, and scored against
/// [demoTutorProfile], so a tutor's inbox is never another tutor's outbox
/// wearing their name.
const List<MatchRequest> sampleReceivedRequests = <MatchRequest>[
  MatchRequest(
    id: 'r-2011',
    counterpartId: 's-maya',
    counterpartName: 'Maya Chen',
    counterpartRole: Role.student,
    subject: 'Calculus and Physics',
    score: 87,
    status: RequestStatus.accepted,
    sentOn: 'Sent Mon 6 Oct',
    outgoing: false,
    note: 'Mock in eleven weeks, so I am working backwards from it. I have all '
        'the past papers printed already — could we start Monday or Tuesday '
        'evening after six?',
    reply: 'Yes — Tuesday and Thursday evenings are free from next week. Send '
        'me your last mock paper and we will spend the first hour on the '
        'questions that cost you marks.',
  ),
  MatchRequest(
    id: 'r-2009',
    counterpartId: 's-aisha',
    counterpartName: 'Aisha Rahman',
    counterpartRole: Role.student,
    subject: 'Statistics',
    score: 83,
    status: RequestStatus.pending,
    sentOn: 'Sent Wed 8 Oct',
    outgoing: false,
    note: 'Grade 8 predicted and I need a 9 for the course I want. I do not '
        'need the ideas explained again — I need speed under time pressure '
        'and fewer careless errors.',
  ),
  MatchRequest(
    id: 'r-2006',
    counterpartId: 's-ethan',
    counterpartName: 'Ethan Brooks',
    counterpartRole: Role.student,
    subject: 'Calculus',
    score: 76,
    status: RequestStatus.pending,
    sentOn: 'Sent Sun 5 Oct',
    outgoing: false,
    note: 'I have exactly one free morning a week. I would rather use Saturday '
        'mornings properly, two hours at a time, than squeeze an evening in. '
        'I want the derivations, not shortcuts.',
  ),
  MatchRequest(
    id: 'r-2004',
    counterpartId: 's-kai',
    counterpartName: 'Kai Nakamura',
    counterpartRole: Role.student,
    subject: 'Statistics',
    score: 70,
    status: RequestStatus.pending,
    sentOn: 'Sent Fri 3 Oct',
    outgoing: false,
    note: 'Three years of cycling data and a half-finished analysis. Could the '
        'lessons be about finishing that properly rather than starting a '
        'textbook from chapter one?',
  ),
  MatchRequest(
    id: 'r-2001',
    counterpartId: 's-sofia',
    counterpartName: 'Sofia Marino',
    counterpartRole: Role.student,
    subject: 'Essay Writing',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Tue 30 Sep',
    outgoing: false,
    note: 'My ideas are fine and my structure falls apart. Could you read a '
        'draft and tell me which paragraph to cut?',
    reply: 'I only teach maths and the sciences, I am afraid. Claire Dubois '
        'and Rachel Osei both do this work online, and they are good.',
  ),
  MatchRequest(
    id: 'r-1998',
    counterpartId: 's-owen',
    counterpartName: 'Owen Pratt',
    counterpartRole: Role.student,
    subject: 'Algebra',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Mon 29 Sep',
    outgoing: false,
    note: 'I lost the thread somewhere in year 8 and nobody noticed. I would '
        'rather rebuild it than keep pretending. I can do weekday afternoons, '
        'in person if that is easier.',
    reply: 'I teach online, and my week is mostly evenings — Daniel Reyes '
        'teaches in Camden in the afternoons and would be the better fit.',
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// The two profiles you land on if you skip onboarding
// ═════════════════════════════════════════════════════════════════════════════

/// The student you are if you open the app and skip the form. Chosen so the
/// default list has a clear top, a muddle in the middle and some honest bad
/// matches at the bottom — a real ranking, not a wall of 99s.
final Profile demoStudentProfile = Profile(
  role: Role.student,
  name: 'Maya Chen',
  subjects: const <String>['Calculus', 'Physics', 'Algebra'],
  style: OnboardingOptions.studentStyles[0],
  mode: SessionMode.both,
  budget: 50,
  availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Thu-Eve', 'Sat-Morn']),
  goal: OnboardingOptions.studentGoals[1],
);

/// The tutor you are if you open the app and skip the form. Calibrated against
/// Amara Okonkwo's real availability, since her card is the landing specimen.
final Profile demoTutorProfile = Profile(
  role: Role.tutor,
  name: 'Amara Okonkwo',
  subjects: const <String>['Calculus', 'Statistics', 'Algebra'],
  style: OnboardingOptions.tutorStyles[0],
  mode: SessionMode.both,
  budget: 46,
  availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
  goal: OnboardingOptions.tutorGoals[0],
);

/// The specimen shown on the landing page: the top-ranked tutor for the demo
/// student, scored live so the landing page cannot drift from the product.
MatchResult landingSpecimen() => rank(sampleTutors, demoStudentProfile).first;

int get poolSize => sampleTutors.length + sampleStudents.length + 2;
