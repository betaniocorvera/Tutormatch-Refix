// ─────────────────────────────────────────────────────────────────────────────
// Application state.
//
// The one object the interface reads. It owns the session, the signed-in
// profile, the ranked list, requests, conversations, and the catalogues. Every
// value here comes from the FastAPI service; the screens do not keep a second
// copy of the data they render.
//
// The state is deliberately optimistic only for profile edits: a control should
// move under the finger immediately, and the server's projection replaces the
// local value when the save returns. Everything else waits for the answer.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/data/repositories/auth_repository.dart';
import 'package:tutormatch/data/repositories/catalog_repository.dart';
import 'package:tutormatch/data/repositories/conversation_repository.dart';
import 'package:tutormatch/data/repositories/match_repository.dart';
import 'package:tutormatch/data/repositories/profile_repository.dart';
import 'package:tutormatch/data/repositories/request_repository.dart';
import 'package:tutormatch/theme/app_theme.dart';

/// The protected page a signed-out visitor asked for before being sent to sign
/// in. Kept with its arguments so a map node or chat URL survives the detour.
class PendingDestination {
  const PendingDestination(this.route, [this.arguments]);

  final String route;
  final Object? arguments;
}

class AppState extends ChangeNotifier {
  AppState({
    ApiClient? api,
    bool autoInitialize = true,
  }) : _api = api ?? ApiClient() {
    _api.onUnauthorized = _handleUnauthorized;
    _auth = AuthRepository(_api);
    _profiles = ProfileRepository(_api);
    _catalog = CatalogRepository(_api);
    _matchRepository = MatchRepository(_api);
    _requestRepository = RequestRepository(_api);
    _conversationRepository = ConversationRepository(_api);
    if (autoInitialize) unawaited(initialize());
  }

  final ApiClient _api;
  late final AuthRepository _auth;
  late final ProfileRepository _profiles;
  late final CatalogRepository _catalog;
  late final MatchRepository _matchRepository;
  late final RequestRepository _requestRepository;
  late final ConversationRepository _conversationRepository;

  // ── Startup ────────────────────────────────────────────────────────────────

  bool _ready = false;
  bool get isReady => _ready;
  bool _initializing = false;
  String? _startupError;
  String? get startupError => _startupError;

  /// Loads public catalogues first (the landing page can render signed out),
  /// then restores a stored refresh session. A network failure is reported as a
  /// startup error but never blocks the public pages.
  Future<void> initialize() async {
    if (_initializing || _ready) return;
    _initializing = true;
    notifyListeners();

    try {
      await _loadCatalog();
    } on ApiException catch (error) {
      _catalogError = error.message;
    }

    try {
      final tokens = await _api.readTokens();
      if (tokens != null) {
        final UserAccount user = await _auth.me();
        _user = user;
        _signedIn = true;
        _role = user.role;
        await _loadProfile();
        _ready = true;
        notifyListeners();
        unawaited(loadMatches());
        unawaited(loadRequests());
        unawaited(loadConversations());
        return;
      }
    } on ApiException catch (error) {
      _startupError = error.message;
      if (error.statusCode == 401) {
        await _api.clearTokens();
      }
    } finally {
      _ready = true;
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> retryInitialize() async {
    _ready = false;
    _startupError = null;
    await initialize();
  }

  // ── Catalogues ─────────────────────────────────────────────────────────────

  List<City> _cities = const <City>[];
  List<Place> _places = const <Place>[];
  List<String> _regions = const <String>[];
  List<SubjectOption> _subjectOptions = const <SubjectOption>[];
  List<SecurityQuestion> _securityQuestions = const <SecurityQuestion>[];
  String? _catalogError;

  List<City> get cities => _cities;
  List<Place> get places => _places;
  List<String> get regions => _regions;
  List<SubjectOption> get subjectOptions => _subjectOptions;
  List<String> get subjects => <String>[
        for (final SubjectOption subject in _subjectOptions) subject.name,
      ];
  List<SecurityQuestion> get securityQuestions => _securityQuestions;
  String? get catalogError => _catalogError;

  Place? placeById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final Place place in _places) {
      if (place.id == id) return place;
    }
    return null;
  }

  PublicPlace? publicPlaceFor(String? placeId, LocationPrivacy privacy) {
    if (privacy == LocationPrivacy.hidden) return null;
    final Place? place = placeById(placeId);
    if (place == null) return null;
    if (privacy == LocationPrivacy.cityOnly) {
      return PublicPlace(
        label: place.city.name,
        city: place.city.name,
        region: place.city.region,
        latitude: place.city.latitude,
        longitude: place.city.longitude,
        cityOnly: true,
      );
    }
    return PublicPlace(
      label: place.label,
      city: place.city.name,
      region: place.city.region,
      latitude: place.latitude,
      longitude: place.longitude,
      cityOnly: false,
    );
  }

  Future<void> _loadCatalog() async {
    final List<dynamic> results = await Future.wait(<Future<dynamic>>[
      _catalog.areas(),
      _catalog.subjects(),
      _catalog.securityQuestions(),
    ]);
    final AreaCatalogue areas = results[0] as AreaCatalogue;
    _cities = areas.cities;
    _places = areas.places;
    _regions = areas.regions;
    _subjectOptions = results[1] as List<SubjectOption>;
    _securityQuestions = results[2] as List<SecurityQuestion>;
    _catalogError = null;
  }

  /// Retry the public catalogues after a network failure. The register form
  /// calls this from its inline retry action; it never throws.
  Future<void> reloadCatalog() async {
    try {
      await _loadCatalog();
    } on ApiException catch (error) {
      _catalogError = error.message;
    }
    notifyListeners();
  }

  // ── Session ────────────────────────────────────────────────────────────────

  bool _signedIn = false;
  bool get isSignedIn => _signedIn;

  UserAccount? _user;
  UserAccount? get user => _user;

  String? get currentUserId => _user?.id;

  Role _role = Role.student;
  Role get role => _role;

  PendingDestination? _pendingDestination;
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

  Future<UserAccount> login({
    required String email,
    required String password,
  }) async {
    final AuthSession session = await _auth.login(email: email, password: password);
    _user = session.user;
    _signedIn = true;
    _role = session.user.role;
    _startupError = null;
    notifyListeners();
    await _afterAuth();
    return session.user;
  }

  Future<UserAccount> verifyLoginOtp({
    required String challengeId,
    required String code,
  }) async {
    final AuthSession session = await _auth.verifyLoginOtp(
      challengeId: challengeId,
      code: code,
    );
    _user = session.user;
    _signedIn = true;
    _role = session.user.role;
    _startupError = null;
    notifyListeners();
    await _afterAuth();
    return session.user;
  }

  Future<UserAccount> register({
    required String email,
    required String password,
    required Role role,
    required String displayName,
    required String phone,
    required String areaId,
    required List<String> subjects,
    required List<SecurityAnswerInput> securityQuestions,
    required bool privacyConsent,
    required String privacyPolicyVersion,
  }) async {
    final AuthSession session = await _auth.register(
      email: email,
      password: password,
      role: role,
      displayName: displayName,
      phone: phone,
      areaId: areaId,
      subjects: subjects,
      securityQuestions: securityQuestions,
      privacyConsent: privacyConsent,
      privacyPolicyVersion: privacyPolicyVersion,
    );
    _user = session.user;
    _signedIn = true;
    _role = session.user.role;
    _startupError = null;
    notifyListeners();
    await _afterAuth();
    return session.user;
  }

  Future<void> _afterAuth() async {
    try {
      await _loadProfile();
      unawaited(loadMatches());
      unawaited(loadRequests());
      unawaited(loadConversations());
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        _handleUnauthorized();
      } else {
        _startupError = error.message;
      }
      notifyListeners();
    }
  }

  void signOut() {
    _signedIn = false;
    _user = null;
    _profile = Profile.blank(_role);
    _savedProfile = _profile;
    _profileSaveGeneration++;
    _photo = null;
    _personPhotos.clear();
    _matches = const <MatchResult>[];
    _matchesLoaded = false;
    _requests = const <MatchRequest>[];
    _conversations = const <Conversation>[];
    _pendingDestination = null;
    _startupError = null;
    notifyListeners();
    unawaited(_auth.logout());
  }

  void _handleUnauthorized() {
    if (!_signedIn && _user == null) return;
    _signedIn = false;
    _user = null;
    _profile = Profile.blank(_role);
    _savedProfile = _profile;
    _profileSaveGeneration++;
    _photo = null;
    _personPhotos.clear();
    _matches = const <MatchResult>[];
    _matchesLoaded = false;
    _requests = const <MatchRequest>[];
    _conversations = const <Conversation>[];
    _pendingDestination = null;
    notifyListeners();
  }

  // ── Profile ────────────────────────────────────────────────────────────────

  Profile _profile = Profile.blank(Role.student);
  Profile _savedProfile = Profile.blank(Role.student);
  Profile get profile => _profile;
  int _profileSaveGeneration = 0;

  bool get profileAnswered => _profile.onboardingComplete;

  Uint8List? _photo;
  Uint8List? get photo => _photo;

  final Map<String, Uint8List> _personPhotos = <String, Uint8List>{};
  final Set<String> _photoRequests = <String>{};

  Uint8List? photoFor(String userId) => _personPhotos[userId];

  Future<void> _loadProfile() async {
    _profile = await _profiles.getOwn();
    _savedProfile = _profile;
    _role = _profile.role;
    _matchesLoaded = false;
    await _loadOwnPhoto();
    notifyListeners();
  }

  Future<void> _loadOwnPhoto() async {
    if (!_profile.hasPhoto) {
      _photo = null;
      return;
    }
    try {
      _photo = await _profiles.getPhoto(_profile.userId);
    } on ApiException {
      _photo = null;
    }
  }

  /// Optimistically applies a profile edit and persists the whole profile. A
  /// failed save restores the previous values, so a control never claims a
  /// change the server rejected.
  Future<Profile> updateProfile(Profile next) async {
    final int generation = ++_profileSaveGeneration;
    _profile = next;
    notifyListeners();
    try {
      final Profile saved = await _profiles.update(next);
      if (generation == _profileSaveGeneration) {
        _profile = saved;
        _savedProfile = saved;
        _matchesLoaded = false;
        _scheduleMatchReload();
        notifyListeners();
      }
      return saved;
    } on ApiException {
      if (generation == _profileSaveGeneration) {
        _profile = _savedProfile;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Applies a local answer immediately while the screen debounces the save.
  /// It is the same profile object the server returns, just before the round
  /// trip; [saveProfile] persists it.
  void previewProfile(Profile next) {
    _profile = next;
    notifyListeners();
  }

  Future<Profile> saveProfile() => updateProfile(_profile);

  Future<void> uploadPhoto(Uint8List bytes, String filename) async {
    final Profile saved = await _profiles.uploadPhoto(bytes, filename);
    _profile = saved;
    _savedProfile = saved;
    _photo = await _profiles.getPhoto(saved.userId);
    _personPhotos[saved.userId] = _photo!;
    notifyListeners();
  }

  Future<void> deletePhoto() async {
    await _profiles.deletePhoto();
    _profile = _profile.copyWith(clearPhoto: true);
    _savedProfile = _profile;
    _photo = null;
    if (currentUserId != null) _personPhotos.remove(currentUserId);
    notifyListeners();
  }

  Future<void> loadPhotoFor(String userId, {String? photoUrl}) async {
    if (userId.isEmpty || photoUrl == null || photoUrl.isEmpty) return;
    if (_personPhotos.containsKey(userId) || _photoRequests.contains(userId)) {
      return;
    }
    _photoRequests.add(userId);
    try {
      _personPhotos[userId] = await _profiles.getPhoto(userId);
      notifyListeners();
    } on ApiException {
      // A missing picture falls back to initials; it is not a screen error.
    } finally {
      _photoRequests.remove(userId);
    }
  }

  Candidate candidateForProfile(Profile profile) =>
      candidateFromProfile(profile, photo: _photo);

  // ── Matches ────────────────────────────────────────────────────────────────

  List<MatchResult> _matches = const <MatchResult>[];
  List<MatchResult> get matches => _matches;

  List<Candidate> get pool => <Candidate>[
        for (final MatchResult result in _matches) result.candidate,
      ];

  int _poolSize = 0;
  int get poolSize => _poolSize;
  int _rankedCount = 0;
  int get rankedCount => _rankedCount;
  ColdStart? _coldStart;
  ColdStart? get coldStart => _coldStart;

  bool _matchesLoading = false;
  bool get matchesLoading => _matchesLoading;
  bool _matchesLoaded = false;
  bool get matchesLoaded => _matchesLoaded;
  String? _matchesError;
  String? get matchesError => _matchesError;

  int _matchGeneration = 0;
  Timer? _matchTimer;

  MatchFilters _filters = const MatchFilters();
  MatchFilters get filters => _filters;
  set filters(MatchFilters value) {
    if (value == _filters) return;
    _filters = value;
    notifyListeners();
    _scheduleMatchReload();
  }

  void _scheduleMatchReload() {
    _matchTimer?.cancel();
    _matchTimer = Timer(const Duration(milliseconds: 350), () {
      if (_signedIn) unawaited(loadMatches());
    });
  }

  Future<void> ensureMatches() async {
    if (!_signedIn || _matchesLoading || _matchesLoaded) return;
    await loadMatches();
  }

  Future<void> loadMatches() async {
    if (!_signedIn) return;
    final int generation = ++_matchGeneration;
    _matchesLoading = true;
    _matchesError = null;
    notifyListeners();
    try {
      final MatchBatch batch = await _matchRepository.fetch(_filters);
      if (generation != _matchGeneration) return;
      _matches = batch.matches;
      _poolSize = batch.poolSize;
      _rankedCount = batch.rankedCount;
      _coldStart = batch.coldStart;
      _matchesLoaded = true;
      notifyListeners();
      unawaited(_hydrateMatchPhotos(batch.matches));
    } on ApiException catch (error) {
      if (generation != _matchGeneration) return;
      _matchesError = error.message;
      _matchesLoaded = true;
    } finally {
      if (generation == _matchGeneration) {
        _matchesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _hydrateMatchPhotos(List<MatchResult> matches) async {
    final List<MatchResult> current = List<MatchResult>.of(_matches);
    for (final MatchResult result in matches) {
      final Candidate candidate = result.candidate;
      if (candidate.photoUrl == null || candidate.photoUrl!.isEmpty) continue;
      if (_personPhotos.containsKey(candidate.id)) continue;
      await loadPhotoFor(candidate.id, photoUrl: candidate.photoUrl);
      final Uint8List? bytes = _personPhotos[candidate.id];
      if (bytes == null) continue;
      for (int i = 0; i < current.length; i++) {
        if (current[i].candidate.id == candidate.id) {
          current[i] = current[i].copyWith(
            candidate: current[i].candidate.copyWith(photo: bytes),
          );
        }
      }
    }
    if (current.isNotEmpty) {
      _matches = current;
      notifyListeners();
    }
  }

  void clearFilters() => filters = const MatchFilters();
  void relaxFilters(MatchFilters relaxed) => filters = relaxed;

  MatchResult? matchFor(String candidateId) {
    for (final MatchResult result in _matches) {
      if (result.candidate.id == candidateId) return result;
    }
    return null;
  }

  String? sharedSubjectFor(Candidate candidate) {
    for (final String subject in candidate.subjects) {
      if (_profile.subjects.contains(subject)) return subject;
    }
    return null;
  }

  MatchRequest? requestWith(String candidateId) {
    for (final MatchRequest request in _requests) {
      if (request.counterpartId == candidateId) return request;
    }
    return null;
  }

  bool canRequest(Candidate candidate) {
    if (!_profile.onboardingComplete) return false;
    if (candidate.role == _profile.role) return false;
    if (sharedSubjectFor(candidate) == null) return false;
    final MatchRequest? existing = requestWith(candidate.id);
    return existing == null || existing.status == RequestStatus.declined;
  }

  String get profileSummary {
    final List<bool> availability = _profile.availability;
    final List<String> parts = <String>[
      for (int p = 0; p < Week.partLong.length; p++)
        if (List<int>.generate(Week.days.length, (int d) => d)
            .any((int d) =>
                availability.length == Week.cells &&
                availability[Week.index(d, p)]))
          Week.partLong[p],
    ];
    final String where = parts.isEmpty ? 'no set hours' : parts.join(' and ');
    return '$where, ${_profile.mode.label.toLowerCase()}, up to \$${_profile.budget}/hr';
  }

  // ── Requests ───────────────────────────────────────────────────────────────

  List<MatchRequest> _requests = const <MatchRequest>[];
  List<MatchRequest> get requests => _requests;
  bool _requestsLoading = false;
  bool get requestsLoading => _requestsLoading;
  String? _requestsError;
  String? get requestsError => _requestsError;

  String? _lastRequestReference;
  String? get lastRequestReference => _lastRequestReference;
  set lastRequestReference(String? value) {
    _lastRequestReference = value;
    notifyListeners();
  }

  Future<void> loadRequests() async {
    if (!_signedIn) return;
    _requestsLoading = true;
    _requestsError = null;
    notifyListeners();
    try {
      final List<MatchRequest> list = await _requestRepository.list();
      list.sort((MatchRequest a, MatchRequest b) =>
          b.updatedAt.compareTo(a.updatedAt));
      _requests = list;
    } on ApiException catch (error) {
      _requestsError = error.message;
    } finally {
      _requestsLoading = false;
      notifyListeners();
    }
  }

  Future<MatchRequest> createRequest({
    required Candidate candidate,
    required String subject,
    required String note,
  }) async {
    final MatchRequest request = await _requestRepository.create(
      counterpartId: candidate.id,
      subject: subject,
      note: note,
    );
    _requests = <MatchRequest>[
      request,
      for (final MatchRequest existing in _requests)
        if (existing.id != request.id) existing,
    ];
    _lastRequestReference = _referenceFor(request.id);
    final Conversation conversation = Conversation(
      id: request.conversationId,
      counterpartId: request.counterpartId,
      counterpartName: request.counterpartName,
      counterpartRole: request.counterpartRole,
      subject: request.subject,
      status: request.status,
      requestedByMe: true,
      score: request.score,
      requestNote: request.note,
      counterpartPhotoUrl: request.counterpartPhotoUrl,
      updatedAt: request.updatedAt,
    );
    _conversations = <Conversation>[
      conversation,
      for (final Conversation existing in _conversations)
        if (existing.id != conversation.id) existing,
    ];
    notifyListeners();
    return request;
  }

  Future<void> acceptConversation(String id) async {
    final MatchRequest request = await _requestRepository.accept(id);
    _replaceRequest(request);
    _setConversationStatus(id, RequestStatus.accepted);
    notifyListeners();
  }

  Future<void> declineConversation(
    String id, {
    String reason = 'Not the right fit right now.',
  }) async {
    final MatchRequest request = await _requestRepository.decline(id, reason);
    _replaceRequest(request);
    _setConversationStatus(id, RequestStatus.declined);
    notifyListeners();
  }

  void _replaceRequest(MatchRequest request) {
    _requests = <MatchRequest>[
      for (final MatchRequest existing in _requests)
        if (existing.id == request.id) request else existing,
    ];
  }

  void _setConversationStatus(String id, RequestStatus status) {
    _conversations = <Conversation>[
      for (final Conversation conversation in _conversations)
        if (conversation.id == id)
          conversation.copyWith(status: status)
        else
          conversation,
    ];
  }

  // ── Conversations ──────────────────────────────────────────────────────────

  List<Conversation> _conversations = const <Conversation>[];
  List<Conversation> get conversations => _conversations;
  bool _conversationsLoading = false;
  bool get conversationsLoading => _conversationsLoading;
  String? _conversationsError;
  String? get conversationsError => _conversationsError;
  final Set<String> _conversationLoading = <String>{};

  int get unreadCount => _conversations.fold<int>(
        0,
        (int total, Conversation conversation) =>
            total + conversation.unreadCount,
      );

  Conversation? conversation(String id) {
    for (final Conversation conversation in _conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  bool isTyping(String conversationId) => false;

  Future<void> loadConversations() async {
    if (!_signedIn) return;
    _conversationsLoading = true;
    _conversationsError = null;
    notifyListeners();
    try {
      final List<Conversation> summaries = await _conversationRepository.list();
      final Map<String, Conversation> existing = <String, Conversation>{
        for (final Conversation conversation in _conversations)
          conversation.id: conversation,
      };
      final List<Conversation> merged = <Conversation>[];
      for (final Conversation summary in summaries) {
        final Conversation? loaded = existing[summary.id];
        merged.add(loaded == null
            ? summary
            : summary.copyWith(
                messages: loaded.messages,
                requestNote: loaded.requestNote,
                responseNote: loaded.responseNote,
              ));
      }
      merged.sort((Conversation a, Conversation b) {
        final DateTime left =
            a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime right =
            b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      _conversations = merged;
      unawaited(_hydrateConversationPhotos());
    } on ApiException catch (error) {
      _conversationsError = error.message;
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _hydrateConversationPhotos() async {
    for (final Conversation conversation
        in List<Conversation>.of(_conversations)) {
      if (conversation.counterpartPhotoUrl == null) continue;
      await loadPhotoFor(
        conversation.counterpartId,
        photoUrl: conversation.counterpartPhotoUrl,
      );
    }
  }

  Future<Conversation?> loadConversation(String id) async {
    if (_conversationLoading.contains(id)) return conversation(id);
    _conversationLoading.add(id);
    try {
      final Conversation detail = await _conversationRepository.get(id);
      final MessagePageData page =
          await _conversationRepository.messages(id);
      Conversation loaded = detail.copyWith(
        messages: page.messages,
        unreadCount: page.unreadCount,
        latestMessageSequence: page.latestSequence,
        readThroughSequence: page.readThroughSequence,
      );
      _upsertConversation(loaded);
      notifyListeners();
      unawaited(_hydrateMessageMedia(id, page.messages));
      if (loaded.unreadCount > 0 && loaded.latestMessageSequence > 0) {
        loaded = await _markRead(id, loaded.latestMessageSequence);
      }
      return loaded;
    } on ApiException catch (error) {
      _conversationsError = error.message;
      notifyListeners();
      return null;
    } finally {
      _conversationLoading.remove(id);
    }
  }

  Future<Conversation?> refreshConversation(String id) async {
    final Conversation? current = conversation(id);
    if (current == null) return loadConversation(id);
    try {
      final Conversation detail = await _conversationRepository.get(id);
      final MessagePageData page = await _conversationRepository.messages(
        id,
        after: current.messages.isEmpty ? null : current.latestMessageSequence,
      );
      final List<ChatMessage> messages = <ChatMessage>[
        ...current.messages,
        for (final ChatMessage message in page.messages)
          if (!current.messages.any((ChatMessage existing) =>
              existing.id == message.id))
            message,
      ];
      messages.sort((ChatMessage a, ChatMessage b) =>
          a.sequence.compareTo(b.sequence));
      final Conversation merged = detail.copyWith(
        messages: messages,
        unreadCount: page.unreadCount,
        latestMessageSequence: page.latestSequence,
        readThroughSequence: page.readThroughSequence,
      );
      _upsertConversation(merged);
      notifyListeners();
      unawaited(_hydrateMessageMedia(id, page.messages));
      if (merged.unreadCount > 0) {
        final Conversation marked =
            await _markRead(id, merged.latestMessageSequence);
        return marked;
      }
      return merged;
    } on ApiException {
      return current;
    }
  }

  Future<void> _hydrateMessageMedia(
    String conversationId,
    List<ChatMessage> messages,
  ) async {
    for (final ChatMessage message in messages) {
      if (message.kind != MessageKind.image ||
          message.mediaUrl == null ||
          message.image != null) {
        continue;
      }
      try {
        final Uint8List bytes =
            await _conversationRepository.media(message.mediaUrl!);
        _replaceMessage(conversationId, message.id, (ChatMessage existing) {
          return existing.copyWith(image: bytes);
        });
        notifyListeners();
      } on ApiException {
        // The bubble keeps its caption when the private media cannot load.
      }
    }
  }

  void _replaceMessage(
    String conversationId,
    String? messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    _conversations = <Conversation>[
      for (final Conversation conversation in _conversations)
        if (conversation.id == conversationId)
          conversation.copyWith(
            messages: <ChatMessage>[
              for (final ChatMessage message in conversation.messages)
                if (message.id == messageId) update(message) else message,
            ],
          )
        else
          conversation,
    ];
  }

  Future<void> sendMessage(String id, String text) async {
    final ChatMessage message =
        await _conversationRepository.sendText(id, text);
    _appendMessage(id, message);
    notifyListeners();
  }

  Future<void> sendImage(
    String id,
    Uint8List bytes, {
    String filename = 'photo.jpg',
  }) async {
    final ChatMessage message =
        await _conversationRepository.sendImage(id, bytes, filename);
    _appendMessage(id, message);
    notifyListeners();
    unawaited(_hydrateMessageMedia(id, <ChatMessage>[message]));
  }

  Future<void> sendVoice(String id, int seconds) async {
    final ChatMessage message =
        await _conversationRepository.sendVoiceNote(id, seconds);
    _appendMessage(id, message);
    notifyListeners();
  }

  Future<void> proposeSession(String id, DateTime at) async {
    final ChatMessage message =
        await _conversationRepository.proposeSession(id, at);
    _appendMessage(id, message);
    notifyListeners();
  }

  Future<void> answerSession(
    String conversationId,
    String messageId,
    SessionState state,
  ) async {
    final ChatMessage message = await _conversationRepository.respondToSession(
      conversationId,
      messageId,
      state,
    );
    _replaceMessage(
      conversationId,
      messageId,
      (ChatMessage existing) =>
          existing.copyWith(sessionState: message.sessionState),
    );
    notifyListeners();
  }

  Future<void> logCall(
    String id, {
    required String kind,
    required bool connected,
    required int durationSeconds,
  }) async {
    final ChatMessage message = await _conversationRepository.logCall(
      id,
      kind: kind,
      connected: connected,
      durationSeconds: durationSeconds,
    );
    _appendMessage(id, message);
    notifyListeners();
  }

  Future<Conversation> _markRead(String id, int sequence) async {
    final ReadStateData state =
        await _conversationRepository.markRead(id, throughSequence: sequence);
    Conversation? updated;
    _conversations = <Conversation>[
      for (final Conversation conversation in _conversations)
        if (conversation.id == id)
          updated = conversation.copyWith(
            unreadCount: state.unreadCount,
            readThroughSequence: state.readThroughSequence,
            latestMessageSequence: state.latestMessageSequence,
          )
        else
          conversation,
    ];
    notifyListeners();
    return updated ?? conversation(id)!;
  }

  void _appendMessage(String id, ChatMessage message) {
    final Conversation? current = conversation(id);
    if (current == null) return;
    final List<ChatMessage> messages = <ChatMessage>[
      ...current.messages,
      message,
    ]..sort((ChatMessage a, ChatMessage b) =>
        a.sequence.compareTo(b.sequence));
    _upsertConversation(current.copyWith(
      messages: messages,
      latestMessageSequence: message.sequence,
      readThroughSequence: message.sequence,
      unreadCount: 0,
    ));
  }

  void _upsertConversation(Conversation conversation) {
    _conversations = <Conversation>[
      conversation,
      for (final Conversation existing in _conversations)
        if (existing.id != conversation.id) existing,
    ];
  }

  String _referenceFor(String id) {
    final String compact = id.replaceAll('-', '').toUpperCase();
    final String tail =
        compact.length > 6 ? compact.substring(compact.length - 6) : compact;
    return 'TM-$tail';
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
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
    assert(scope != null, 'No AppStateScope found in context');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final AppStateScope? scope =
        context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in context');
    return scope!.notifier!;
  }
}
