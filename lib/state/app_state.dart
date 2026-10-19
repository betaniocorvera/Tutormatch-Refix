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

  // ── Conversations ──────────────────────────────────────────────────────────
  //
  // The one place in this prototype where sending something does more than
  // change the screen it was sent from: a request becomes a conversation, the
  // other side's answer opens it, and what is typed into it stays until reload.
  // Either side can send, either side can answer — every entry says which way
  // the asking went. Seeded from the sample lists, then edited in memory only.

  final List<Conversation> _studentChats =
      List<Conversation>.of(sampleConversations);
  final List<Conversation> _tutorChats =
      List<Conversation>.of(sampleReceivedConversations);

  /// The conversations for the side you are standing on: what a student sees on
  /// their messages, and what a tutor sees on theirs.
  List<Conversation> get conversations =>
      _role == Role.student ? _studentChats : _tutorChats;

  /// The conversation with [id], whichever side it belongs to. The screen that
  /// is open must keep working if the role is switched underneath it.
  Conversation? conversation(String id) {
    for (final List<Conversation> list
        in <List<Conversation>>[_studentChats, _tutorChats]) {
      for (final Conversation c in list) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  /// Puts a request into the current side's list as a pending conversation,
  /// with the note as its first message — from this side, whoever this side is.
  /// Asking again re-opens that person's conversation rather than stacking a
  /// second one — one conversation per person, in every state — and a
  /// conversation that is already accepted is left alone, because there is
  /// nothing left to ask for.
  void startConversation(Candidate counterpart, {String? note}) {
    final List<Conversation> list = conversations;
    final int existing =
        list.indexWhere((Conversation c) => c.counterpartId == counterpart.id);
    if (existing >= 0 && list[existing].status == RequestStatus.accepted) {
      return;
    }
    if (existing >= 0) list.removeAt(existing);
    list.insert(
      0,
      Conversation(
        id: 'c-${counterpart.id}',
        counterpartId: counterpart.id,
        counterpartName: counterpart.name,
        counterpartRole: counterpart.role,
        subject: counterpart.subjects.first,
        status: RequestStatus.pending,
        requestedByMe: true,
        messages: <ChatMessage>[
          if (note != null && note.trim().isNotEmpty)
            ChatMessage(
              text: note.trim(),
              fromMe: true,
              sentAt: clockLabel(DateTime.now()),
            ),
        ],
      ),
    );
    notifyListeners();
  }

  /// The receiver's two answers. Both unlock or close the chat; neither can be
  /// taken back here, which is what makes the status worth reading.
  void acceptConversation(String id) =>
      _setConversationStatus(id, RequestStatus.accepted);
  void declineConversation(String id) =>
      _setConversationStatus(id, RequestStatus.declined);

  void _setConversationStatus(String id, RequestStatus status) {
    for (final List<Conversation> list
        in <List<Conversation>>[_studentChats, _tutorChats]) {
      final int i = list.indexWhere((Conversation c) => c.id == id);
      if (i < 0) continue;
      if (list[i].status == status) return;
      list[i] = list[i].copyWith(status: status);
      notifyListeners();
      return;
    }
  }

  /// Sends [text] from this side. It lands immediately; about a second and a
  /// half later the other side answers once — the whole of the other side's
  /// behaviour in this prototype. It answers only if the last word is still
  /// yours, so three quick lines earn one reply, not three.
  void sendMessage(String id, String text) {
    final String body = text.trim();
    final Conversation? current = conversation(id);
    if (body.isEmpty ||
        current == null ||
        current.status != RequestStatus.accepted) {
      return;
    }
    _appendMessage(
      id,
      ChatMessage(
        text: body,
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      final Conversation? latest = conversation(id);
      if (latest == null ||
          latest.status != RequestStatus.accepted ||
          latest.messages.isEmpty ||
          !latest.messages.last.fromMe) {
        return;
      }
      _appendMessage(
        id,
        ChatMessage(
          text: _autoReply,
          fromMe: false,
          sentAt: clockLabel(DateTime.now()),
        ),
      );
    });
  }

  /// The other side's entire vocabulary here: one line, sent once, after every
  /// message you write. There is nobody at the other end of this prototype.
  static const String _autoReply =
      'Got it — give me a moment and I will come back to you properly.';

  void _appendMessage(String id, ChatMessage message) {
    for (final List<Conversation> list
        in <List<Conversation>>[_studentChats, _tutorChats]) {
      final int i = list.indexWhere((Conversation c) => c.id == id);
      if (i < 0) continue;
      list[i] = list[i].copyWith(
        messages: <ChatMessage>[...list[i].messages, message],
      );
      notifyListeners();
      return;
    }
  }

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
