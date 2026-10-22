// ─────────────────────────────────────────────────────────────────────────────
// In-memory application state.
//
// This is the ONLY place the UI keeps anything. There is no persistence, no
// token and no network: reload the page and you are back to the demo profiles
// at the bottom of mock_data.dart. That is deliberate — it keeps the interface
// honest about being an interface. Signing in is an in-memory flag for this
// tab only; it is what the route guard reads and writes.
//
// Everything here is a plain ChangeNotifier behind an InheritedNotifier. No
// state-management package, because the whole surface is one object.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/theme/app_theme.dart';

/// The protected page a signed-out visitor asked for before being sent to sign
/// in. Kept with its arguments so a map node or chat URL survives the detour.
class PendingDestination {
  const PendingDestination(this.route, [this.arguments]);

  final String route;
  final Object? arguments;
}

class AppState extends ChangeNotifier {
  /// Which side of the marketplace you are standing on. Set once, by register,
  /// login or onboarding, and never switched from inside the app: the account
  /// type chosen when you signed up is the account type. It decides whose list
  /// you see, never who you are.
  Role _role = Role.student;
  Role get role => _role;
  set role(Role value) {
    if (value == _role) return;
    _role = value;
    // A role switch must not leave the other side's profile behind: a tutor
    // signing in with a student-shaped profile would see student-only fields
    // (and another person's saved area). If the profile already belongs to the
    // chosen side, keep it; otherwise start from that side's demo profile.
    if (_profile.role != value) {
      _profile = value == Role.student ? demoStudentProfile : demoTutorProfile;
    }
    notifyListeners();
  }

  Profile _profile = demoStudentProfile;
  Profile get profile => _profile;
  set profile(Profile value) {
    _profile = value;
    notifyListeners();
  }

  // ── Session ────────────────────────────────────────────────────────────────
  //
  // There is no real account behind the forms, but there is still a real
  // boundary between the public pages and the dashboard. One flag owns it, and
  // one route guard reads it, so Back and a typed URL cannot slip past.

  bool _signedIn = false;
  bool get isSignedIn => _signedIn;

  /// Called only after a form or demo sign-in has completed its field setup.
  void signIn() {
    if (_signedIn) return;
    _signedIn = true;
    notifyListeners();
  }

  /// Clearing this flag is what makes the dashboard unreachable until the next
  /// sign-in. The navigation itself lives in [AuthFlow.signOut].
  void signOut() {
    if (!_signedIn && _pendingDestination == null) return;
    _signedIn = false;
    _pendingDestination = null;
    notifyListeners();
  }

  PendingDestination? _pendingDestination;

  /// The page a signed-out visitor originally asked for. Never notified: it is
  /// consumed by the next route decision, not drawn by a widget.
  PendingDestination? get pendingDestination => _pendingDestination;

  void rememberDestination(String route, [Object? arguments]) {
    _pendingDestination = PendingDestination(route, arguments);
  }

  PendingDestination? takePendingDestination() {
    final PendingDestination? destination = _pendingDestination;
    _pendingDestination = null;
    return destination;
  }

  void clearPendingDestination() => _pendingDestination = null;

  /// The viewer's own picture, in memory only: bytes, not a path and not a URL,
  /// because there is no filesystem and no server behind this prototype. Every
  /// avatar of the viewer reads it from here, so one pick lands in the profile
  /// header and in the preview at the same moment — and removing it puts the
  /// initials back everywhere at once.
  Uint8List? _photo;
  Uint8List? get photo => _photo;
  set photo(Uint8List? value) {
    if (identical(value, _photo)) return;
    _photo = value;
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

  /// The conversation with [id], whichever side it belongs to. A chat screen
  /// that stays open keeps working without needing to know which list it was
  /// opened from.
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

  /// Conversations where the scripted answer is being composed. The chat shows
  /// three moving dots while this is true; nothing else in the app reads it.
  final Set<String> _typing = <String>{};
  final Map<String, Timer> _typingTimers = <String, Timer>{};
  final Map<String, Timer> _replyTimers = <String, Timer>{};

  bool isTyping(String conversationId) => _typing.contains(conversationId);

  int _serial = 0;
  String _nextMessageId() =>
      'm-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

  /// Sends [text] from this side. It lands immediately; a moment later the
  /// other side starts typing, and about a second and a half after that they
  /// answer once — the whole of the other side's behaviour in this prototype.
  /// It answers only if the last word is still yours, so three quick lines earn
  /// one reply, not three.
  void sendMessage(String id, String text) {
    final String body = text.trim();
    if (body.isEmpty) return;
    _send(
      id,
      ChatMessage(
        id: _nextMessageId(),
        text: body,
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
      ),
    );
  }

  /// A picked picture. Bytes stay in the message, in memory, for as long as
  /// this tab is open; nothing is encoded, uploaded or written to disk.
  void sendImage(String id, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _send(
      id,
      ChatMessage(
        id: _nextMessageId(),
        text: 'Photo',
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
        kind: MessageKind.image,
        image: bytes,
      ),
    );
  }

  /// A simulated voice note. [seconds] is the length the bubble plays for;
  /// there is no audio anywhere in this prototype.
  void sendVoice(String id, int seconds) {
    final int length = seconds < 1 ? 1 : seconds;
    _send(
      id,
      ChatMessage(
        id: _nextMessageId(),
        text: 'Voice note · ${voiceLabel(length)}',
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
        kind: MessageKind.voice,
        seconds: length,
      ),
    );
  }

  /// A card, not a message: the date has already been chosen in the pickers.
  void proposeSession(String id, DateTime at) {
    _send(
      id,
      ChatMessage(
        id: _nextMessageId(),
        text: 'Session proposed · ${describeSession(at)}',
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
        kind: MessageKind.session,
        sessionWhen: describeSession(at),
      ),
    );
  }

  /// Answers a session card. Final, like the request's own answer: a second tap
  /// cannot undo the first.
  void answerSession(
    String conversationId,
    String messageId,
    SessionState answer,
  ) {
    if (answer == SessionState.proposed) return;
    for (final List<Conversation> list
        in <List<Conversation>>[_studentChats, _tutorChats]) {
      final int i = list.indexWhere((Conversation c) => c.id == conversationId);
      if (i < 0) continue;
      final Conversation c = list[i];
      if (c.status != RequestStatus.accepted) return;
      final int m = c.messages.indexWhere(
        (ChatMessage message) =>
            message.id == messageId && message.kind == MessageKind.session,
      );
      if (m < 0 || c.messages[m].sessionState != SessionState.proposed) return;
      final List<ChatMessage> messages = List<ChatMessage>.of(c.messages);
      messages[m] = messages[m].copyWith(sessionState: answer);
      list[i] = c.copyWith(messages: messages);
      notifyListeners();
      return;
    }
  }

  /// Records a call the way the thread will read it: a length when it
  /// connected, "Missed call" when it was hung up while still ringing.
  void logCall(
    String id, {
    required bool video,
    required bool connected,
    required Duration duration,
  }) {
    final Conversation? current = conversation(id);
    if (current == null || current.status != RequestStatus.accepted) return;
    _appendMessage(
      id,
      ChatMessage(
        text: connected
            ? '${video ? 'Video' : 'Voice'} call · ${elapsedClock(duration)}'
            : 'Missed call',
        fromMe: true,
        sentAt: clockLabel(DateTime.now()),
        kind: MessageKind.call,
      ),
    );
  }

  /// The one door all outgoing messages use: validate the open thread, land the
  /// message, then schedule the scripted answer.
  void _send(String id, ChatMessage message) {
    final Conversation? current = conversation(id);
    if (current == null || current.status != RequestStatus.accepted) return;
    _appendMessage(id, message);
    _scheduleReply(id);
  }

  void _scheduleReply(String id) {
    _typingTimers[id]?.cancel();
    _replyTimers[id]?.cancel();
    if (_typing.remove(id)) notifyListeners();

    _typingTimers[id] = Timer(const Duration(milliseconds: 450), () {
      if (!_canReply(id)) return;
      _typing.add(id);
      notifyListeners();
    });
    _replyTimers[id] = Timer(const Duration(milliseconds: 1600), () {
      final bool wasTyping = _typing.remove(id);
      if (!_canReply(id)) {
        if (wasTyping) notifyListeners();
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

  bool _canReply(String id) {
    final Conversation? latest = conversation(id);
    return latest != null &&
        latest.status == RequestStatus.accepted &&
        latest.messages.isNotEmpty &&
        latest.messages.last.fromMe;
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

  @override
  void dispose() {
    // A queued reply must not call notifyListeners on a disposed state.
    for (final Timer timer in <Timer>[
      ..._typingTimers.values,
      ..._replyTimers.values,
    ]) {
      timer.cancel();
    }
    _typingTimers.clear();
    _replyTimers.clear();
    _typing.clear();
    super.dispose();
  }
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
