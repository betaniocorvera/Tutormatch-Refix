// ─────────────────────────────────────────────────────────────────────────────
// Data-layer checks.
//
// There is no widget test here on purpose: rendering depends on two web fonts
// being fetched from Google, which makes a rendering test a test of the network.
// What is worth pinning down is the part of this prototype that is real logic —
// the availability parser, the overlap arithmetic, the ranking order, and the
// generated empty-state sentence. Those are the things a later swap to a real
// service must not silently break.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';

void main() {
  group('availability', () {
    test('parses readable slot strings into the 21-cell week', () {
      final List<bool> grid = avail(const <String>['Mon-Eve', 'Sat-Morn']);
      expect(grid.length, Week.cells);
      expect(grid.where((bool c) => c).length, 2);
      expect(grid[Week.index(0, 2)], isTrue); // Monday evening
      expect(grid[Week.index(5, 0)], isTrue); // Saturday morning
      expect(grid[Week.index(0, 0)], isFalse);
    });

    test('rejects a slot that is not a real slot', () {
      expect(() => avail(const <String>['Funday-Eve']), throwsArgumentError);
      expect(() => avail(const <String>['Mon-Brunch']), throwsArgumentError);
    });

    test('overlap is the hour blocks both people keep free', () {
      final List<bool> mine = avail(const <String>['Mon-Eve', 'Tue-Eve']);
      final List<bool> theirs = avail(const <String>['Tue-Eve', 'Sat-Morn']);
      expect(overlapOf(mine, theirs).where((bool c) => c).length, 1);
      expect(describeOverlap(overlapOf(mine, theirs)), 'Tue evenings');
    });

    test('a week with no shared hour says so rather than counting to zero', () {
      final List<bool> none = overlapOf(
        avail(const <String>['Mon-Morn']),
        avail(const <String>['Fri-Eve']),
      );
      expect(describeOverlap(none), isNull);
    });
  });

  group('ranking', () {
    test('scores are the five dimensions and never exceed 100', () {
      for (final MatchResult r in rank(sampleTutors, demoStudentProfile)) {
        expect(r.score.byDimension.length, MatchDimension.values.length);
        expect(r.score.total, greaterThanOrEqualTo(0));
        expect(r.score.total, lessThanOrEqualTo(100));
      }
    });

    test('the order is descending, so the best fit is first', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      for (int i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].rankScore, greaterThanOrEqualTo(ranked[i].rankScore));
      }
      expect(ranked.first.candidate.name, 'Amara Okonkwo');
    });

    test('every match can state three reasons, best fit first', () {
      for (final MatchResult r in rank(sampleTutors, demoStudentProfile)) {
        expect(r.reasons.length, 3);
        final List<double> fits = r.reasons
            .map((FitNote n) => r.score.byDimension[n.dimension]! / n.dimension.max)
            .toList();
        expect(fits[0], greaterThanOrEqualTo(fits[1]));
        expect(fits[1], greaterThanOrEqualTo(fits[2]));
      }
    });

    test('a tutor with no shared hour cannot outrank one who has them', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      final int blocked = ranked.indexWhere((MatchResult r) => r.score.overlapSlots == 0);
      final int open = ranked.indexWhere((MatchResult r) => r.score.overlapSlots > 0);
      expect(blocked, greaterThan(open));
    });

    test('a tutor is ranked for a student, a student for a tutor', () {
      expect(sampleTutors.every((Candidate c) => c.role == Role.tutor), isTrue);
      expect(sampleStudents.every((Candidate c) => c.role == Role.student), isTrue);
      expect(rank(sampleStudents, demoTutorProfile).first.candidate.role, Role.student);
    });
  });

  group('filters and the empty state', () {
    test('filtering narrows without reordering', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      final MatchOutcome out = applyFilters(
        ranked,
        const MatchFilters(maxRate: 40),
        demoStudentProfile,
      );
      expect(out.results, isNotEmpty);
      final List<String> expected = ranked
          .where((MatchResult r) => r.candidate.rate <= 40)
          .map((MatchResult r) => r.candidate.id)
          .toList();
      expect(out.results.map((MatchResult r) => r.candidate.id).toList(), expected);
    });

    test('an impossible ceiling names the condition and offers a way back', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      final MatchOutcome out = applyFilters(
        ranked,
        const MatchFilters(maxRate: 25),
        demoStudentProfile,
      );
      expect(out.results, isEmpty);
      final EmptyExplanation empty = out.empty!;
      expect(empty.headline, contains('25'));
      expect(empty.recovered, greaterThan(0));
      // The suggested change has to be reversible and to actually work.
      expect(empty.relaxed.maxRate, greaterThan(25));
      expect(
        applyFilters(ranked, empty.relaxed, demoStudentProfile).results.length,
        empty.recovered,
      );
    });

    test('the whole pool passes an untouched filter set', () {
      final List<MatchResult> ranked = rank(sampleTutors, demoStudentProfile);
      final MatchOutcome out =
          applyFilters(ranked, const MatchFilters(), demoStudentProfile);
      expect(out.empty, isNull);
      expect(out.results.length, ranked.length);
    });
  });
}
