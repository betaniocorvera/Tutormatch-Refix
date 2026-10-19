// ─────────────────────────────────────────────────────────────────────────────
// In-memory application state.
//
// This is the ONLY place the UI keeps anything. There is no persistence, no
// session, no token and no network: reload the page and you are back to the
// demo profiles at the bottom of mock_data.dart. That is deliberate — it keeps
// the interface honest about being an interface.
//
// Everything here is a plain ChangeNotifier behind an InheritedNotifier. No
// state-management package, because the whole surface is one object.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';

class AppState extends ChangeNotifier {
  /// Which side of the marketplace you are standing on. Set by register, login
  /// and onboarding; it decides whose list you see, never who you are.
  Role _role = Role.student;
  Role get role => _role;
  set role(Role value) {
    if (value == _role) return;
    _role = value;
    notifyListeners();
  }

  Profile _profile = demoStudentProfile;
  Profile get profile => _profile;
  set profile(Profile value) {
    _profile = value;
    notifyListeners();
  }

  MatchFilters _filters = const MatchFilters();
  MatchFilters get filters => _filters;
  set filters(MatchFilters value) {
    _filters = value;
    notifyListeners();
  }

  /// True once somebody has actually answered the onboarding questions. Drives
  /// the "based on your profile" label on the match cards, which is the only
  /// honest thing to show a person whose answers we just used.
  bool _profileAnswered = false;
  bool get profileAnswered => _profileAnswered;
  set profileAnswered(bool value) {
    _profileAnswered = value;
    notifyListeners();
  }

  /// Set, then cleared, when a request is sent. The confirmation lives on the
  /// detail screen rather than in a modal, so this only carries the reference.
  String? _lastRequestReference;
  String? get lastRequestReference => _lastRequestReference;
  set lastRequestReference(String? value) {
    _lastRequestReference = value;
    notifyListeners();
  }

  /// The pool the current role is browsing. A student browses tutors.
  List<Candidate> get pool =>
      _role == Role.student ? sampleTutors : sampleStudents;

  /// A one-line description of the answers the ranking actually used. Shown on
  /// the "based on your profile" chip and in the empty state, so the label is
  /// never a vague assurance.
  String get profileSummary {
    final List<bool> a = _profile.availability;
    final List<String> parts = <String>[
      for (int p = 0; p < Week.partLong.length; p++)
        if (List<int>.generate(Week.days.length, (int d) => d)
            .any((int d) => a[Week.index(d, p)]))
          Week.partLong[p],
    ];
    final String where = parts.isEmpty ? 'no set hours' : parts.join(' and ');
    return '$where, ${_profile.mode.label.toLowerCase()}, up to \$${_profile.budget}/hr';
  }

  /// Resets the filters to "show me everything ranked". Used by the empty state
  /// and by the filter rail's reset.
  void clearFilters() => filters = const MatchFilters();

  /// Applies the adjustment the empty state suggested.
  void relaxFilters(MatchFilters relaxed) => filters = relaxed;
}

/// Reads [AppState] from the tree and rebuilds the caller when it changes.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    required AppState super.notifier,
    required super.child,
    super.key,
  });

  static AppState of(BuildContext context) {
    final AppStateScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope above this widget.');
    return scope!.notifier!;
  }

  /// For widgets that only need to call a method, never to rebuild.
  static AppState read(BuildContext context) {
    final AppStateScope? scope =
        context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope above this widget.');
    return scope!.notifier!;
  }
}
