import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/data/token_store.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

import 'test_support.dart';

Future<void> _settle([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(mockPreferences);

  AppState makeState(FakeApi fake) => AppState(
        api: ApiClient(
          baseUrl: fakeBaseUrl,
          client: fake.client,
          tokenStore: TokenStore(),
        ),
        autoInitialize: false,
      );

  Future<AppState> signedIn(FakeApi fake) async {
    final AppState state = makeState(fake);
    await state.initialize();
    await state.login(
      email: 'maya@tutormatch.local',
      password: 'TutorMatch123!',
    );
    await _settle();
    return state;
  }

  test('startup loads the public catalogue before a session exists', () async {
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.isReady, isTrue);
    expect(state.isSignedIn, isFalse);
    expect(state.subjects, contains('Calculus'));
    expect(state.places.single.label, 'Hackney, London');
    expect(state.startupError, isNull);
  });

  test('login stores tokens, restores the profile and loads the lists', () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    expect(state.isSignedIn, isTrue);
    expect(state.role, Role.student);
    expect(state.profile.name, 'Maya Chen');
    expect(state.profileAnswered, isTrue);
    expect(state.matches.single.candidate.name, 'Amara Okonkwo');
    expect(state.matches.single.score.total, 84);
    expect(await TokenStore().read(), isNotNull);
  });

  test('a stored refresh session is restored without a login screen', () async {
    await TokenStore().save(const AuthTokens(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    ));
    final FakeApi fake = FakeApi();
    final AppState state = makeState(fake);
    addTearDown(state.dispose);

    await state.initialize();
    await _settle();

    expect(state.isSignedIn, isTrue);
    expect(state.profile.userId, 'u-student');
    expect(state.matches, isNotEmpty);
  });

  test('a rejected session on restore clears tokens and stays signed out',
      () async {
    await TokenStore().save(const AuthTokens(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    ));
    final FakeApi fake = FakeApi()
      ..expireSession = true
      ..failRefresh = true;
    final AppState state = makeState(fake);
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.isSignedIn, isFalse);
    expect(await TokenStore().read(), isNull);
    expect(state.startupError, isNotNull);
  });

  test('a 401 during a protected load signs the account out', () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    fake
      ..expireSession = true
      ..failRefresh = true;
    await state.loadMatches();
    await _settle();

    expect(state.isSignedIn, isFalse);
    expect(state.matches, isEmpty);
    expect(await TokenStore().read(), isNull);
  });

  test('a failed profile save restores the last server profile', () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    final Profile before = state.profile;
    fake.failProfileSave = true;
    await expectLater(
      state.updateProfile(before.copyWith(name: 'Not saved')),
      throwsA(isA<ApiException>()),
    );
    expect(state.profile.name, before.name);

    fake.failProfileSave = false;
    final Profile saved =
        await state.updateProfile(before.copyWith(name: 'Maya C.'));
    expect(saved.name, 'Maya C.');
    expect(state.profile.name, 'Maya C.');

    fake.failProfileSave = true;
    await expectLater(
      state.updateProfile(state.profile.copyWith(name: 'Lost again')),
      throwsA(isA<ApiException>()),
    );
    expect(state.profile.name, 'Maya C.');
  });

  test('server-side filters are debounced and sent as query parameters',
      () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);
    await _settle();

    fake.matchCalls = 0;
    state.filters = const MatchFilters(minScore: 60, maxRate: 50);
    expect(fake.matchCalls, 0);

    await _settle(450);

    expect(fake.matchCalls, 1);
    expect(fake.lastMatchQuery['min_score'], '60');
    expect(fake.lastMatchQuery['max_rate'], '50');
    expect(fake.lastMatchQuery['limit'], '100');
  });

  test('a failed match load exposes an error rather than an empty success',
      () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    fake.failMatches = true;
    await state.loadMatches();

    expect(state.matchesError, 'Matching is unavailable.');
    expect(state.matchesLoaded, isTrue);
    expect(state.matchesLoading, isFalse);
  });

  test('creating a request also creates its pending conversation', () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    final Candidate candidate = state.matches.first.candidate;
    expect(state.canRequest(candidate), isTrue);

    final MatchRequest request = await state.createRequest(
      candidate: candidate,
      subject: 'Calculus',
      note: 'Could we start with derivatives?',
    );

    expect(state.requests.first.id, request.id);
    expect(state.lastRequestReference, startsWith('TM-'));
    final Conversation conversation = state.conversation(request.conversationId)!;
    expect(conversation.status, RequestStatus.pending);
    expect(conversation.requestedByMe, isTrue);
  });

  test('accepting and declining update both the request and the thread',
      () async {
    final FakeApi fake = FakeApi();
    fake.requests.add(requestJson(status: 'pending', outgoing: false));
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    await state.acceptConversation('c-1');
    expect(state.requests.single.status, RequestStatus.accepted);
    expect(state.conversation('c-1')!.status, RequestStatus.accepted);

    await state.declineConversation('c-1', reason: 'Not the right fit.');
    expect(state.requests.single.status, RequestStatus.declined);
    expect(state.conversation('c-1')!.status, RequestStatus.declined);
  });

  test('opening an unread conversation marks it read and sends a message',
      () async {
    final FakeApi fake = FakeApi()..unread = 2;
    fake.conversations[0]['unread_count'] = 2;
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);
    await state.loadConversations();
    expect(state.unreadCount, 2);

    await state.loadConversation('c-1');
    await _settle();

    expect(fake.readCalls, 1);
    expect(state.unreadCount, 0);
    expect(state.conversation('c-1')!.messages, hasLength(1));

    await state.sendMessage('c-1', 'See you Thursday.');
    final Conversation conversation = state.conversation('c-1')!;
    expect(conversation.messages.last.text, 'See you Thursday.');
    expect(conversation.messages.last.fromMe, isTrue);
    expect(conversation.messages, hasLength(2));
  });

  test('sign out clears every account-owned list and the tokens', () async {
    final FakeApi fake = FakeApi();
    final AppState state = await signedIn(fake);
    addTearDown(state.dispose);

    state.signOut();
    await _settle();

    expect(state.isSignedIn, isFalse);
    expect(state.profile.name, isEmpty);
    expect(state.matches, isEmpty);
    expect(state.requests, isEmpty);
    expect(state.conversations, isEmpty);
    expect(await TokenStore().read(), isNull);
    expect(fake.logoutCalls, 1);
  });
}
