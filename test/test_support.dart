// Shared test fixtures for the HTTP-backed Flutter app.
//
// Every test talks to a real ApiClient and the real repositories. Only the
// socket is replaced: MockClient answers the same JSON the FastAPI service
// returns, so the models, token handling, retries and screens are exercised
// end to end without a running server.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/data/token_store.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

const String fakeBaseUrl = 'http://tutor.test';

/// A valid 1x1 red PNG, used wherever the API would return a profile picture.
final Uint8List redDot = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);

const List<bool> _week = <bool>[
  true, false, false,
  true, false, false,
  true, false, false,
  true, false, false,
  true, false, false,
  false, true, false,
  false, false, false,
];

Map<String, dynamic> publicProfile({
  String id = 'u-tutor',
  Role role = Role.tutor,
  String name = 'Amara Okonkwo',
  List<String> subjects = const <String>['Calculus', 'Statistics'],
  String style = 'I work through examples slowly and let the student steer',
  int budget = 38,
  String? photoUrl,
  double? distanceKm,
}) =>
    <String, dynamic>{
      'id': id,
      'role': roleToApi(role),
      'name': name,
      'subjects': subjects,
      'style': style,
      'mode': 'both',
      'budget': budget,
      'availability': _week,
      'goal': role == Role.student
          ? 'Move up a grade or two this year'
          : 'Fill a few steady evenings a week',
      'status_text': role == Role.tutor
          ? 'Calculus and statistics, evenings'
          : 'Year 12, calculus and physics',
      'presence': 'available',
      'bio': 'Worked examples first, then you do the next one.',
      'gender': 'Prefer not to say',
      'languages': <String>['English'],
      'years': role == Role.tutor ? 6 : null,
      'education': role == Role.tutor ? 'MSc Mathematics, UCL' : '',
      'grade': role == Role.student ? 'Year 12' : '',
      'age': role == Role.tutor ? 29 : 17,
      'photo_url': photoUrl,
      'distance_km': distanceKm,
      'public_location': <String, dynamic>{
        'label': 'Hackney, London',
        'city': 'London',
        'region': 'London',
        'latitude': 51.5450,
        'longitude': -0.0553,
        'city_only': false,
      },
    };

Map<String, dynamic> ownProfile({
  String id = 'u-student',
  Role role = Role.student,
  String name = 'Maya Chen',
  bool complete = true,
  String? photoUrl,
  String bio = 'Worked examples, mostly.',
}) =>
    <String, dynamic>{
      'user_id': id,
      'role': roleToApi(role),
      'name': name,
      'subjects': <String>['Calculus', 'Physics'],
      'style': 'Watch one worked example, then do the next one myself',
      'mode': 'both',
      'budget': 40,
      'availability': _week,
      'goal': 'Move up a grade or two this year',
      'birthdate': '2008-01-14',
      'lives_in': 'Hackney, London',
      'area_id': 'london-hackney',
      'location_privacy': 'area',
      'public_location': <String, dynamic>{
        'label': 'Hackney, London',
        'city': 'London',
        'region': 'London',
        'latitude': 51.5450,
        'longitude': -0.0553,
        'city_only': false,
      },
      'status_text': 'Year 12, calculus and physics',
      'presence': 'available',
      'bio': bio,
      'gender': 'Prefer not to say',
      'languages': <String>['English'],
      'years': null,
      'education': '',
      'grade': 'Year 12',
      'age': 18,
      'photo_url': photoUrl,
      'onboarding_complete': complete,
      'completeness': <String, dynamic>{
        'filled': complete ? 10 : 2,
        'total': 12,
        'missing': complete ? <String>['a picture'] : <String>['a picture'],
      },
    };

Map<String, dynamic> userJson({
  String id = 'u-student',
  String email = 'maya@tutormatch.local',
  Role role = Role.student,
  String name = 'Maya Chen',
  bool complete = true,
}) =>
    <String, dynamic>{
      'id': id,
      'email': email,
      'role': roleToApi(role),
      'display_name': name,
      'onboarding_complete': complete,
      'created_at': '2026-10-01T10:00:00Z',
    };

Map<String, dynamic> matchJson({
  int rank = 1,
  int score = 84,
  String id = 'u-tutor',
  String name = 'Amara Okonkwo',
  Role role = Role.tutor,
  List<String> subjects = const <String>['Calculus', 'Statistics'],
  String? photoUrl,
  double? distanceKm,
}) =>
    <String, dynamic>{
      'rank': rank,
      'score': score,
      'tier': score >= 80 ? 'strong' : (score >= 60 ? 'good' : 'possible'),
      'dimensions': <String, dynamic>{
        'subjects': <String, dynamic>{'score': 34},
        'time': <String, dynamic>{'score': 20},
        'style': <String, dynamic>{'score': 12},
        'format': <String, dynamic>{'score': 10},
        'budget': <String, dynamic>{'score': 8},
      },
      'overlap': _week,
      'reasons': <Map<String, String>>[
        <String, String>{
          'dimension': 'subjects',
          'signal': 'Calculus is shared',
          'detail': 'You both chose Calculus.',
        },
        <String, String>{
          'dimension': 'time',
          'signal': 'Five shared hours',
          'detail': 'Weekday evenings overlap.',
        },
      ],
      'profile': publicProfile(
        id: id,
        role: role,
        name: name,
        subjects: subjects,
        photoUrl: photoUrl,
        distanceKm: distanceKm,
      ),
    };

Map<String, dynamic> requestJson({
  String id = 'c-1',
  String conversationId = 'c-1',
  String status = 'pending',
  bool outgoing = true,
  String subject = 'Calculus',
  int score = 84,
}) =>
    <String, dynamic>{
      'id': id,
      'conversation_id': conversationId,
      'counterpart': <String, dynamic>{
        'id': 'u-tutor',
        'name': 'Amara Okonkwo',
        'role': 'tutor',
      },
      'subject': subject,
      'score': score,
      'status': status,
      'note': 'Could we start with derivatives?',
      'response_note': status == 'declined' ? 'Not the right fit.' : null,
      'direction': outgoing ? 'sent' : 'received',
      'created_at': '2026-10-20T18:00:00Z',
      'updated_at': '2026-10-21T18:00:00Z',
    };

Map<String, dynamic> messageJson({
  String id = 'm-1',
  int sequence = 1,
  String text = 'Hello, Maya.',
  bool fromMe = false,
  String kind = 'text',
  bool read = false,
  String? mediaUrl,
  int? voiceSeconds,
  String? callKind,
  bool? callConnected,
  int? callSeconds,
}) =>
    <String, dynamic>{
      'id': id,
      'sequence': sequence,
      'text': text,
      'kind': kind,
      'from_me': fromMe,
      'read_by_recipient': read,
      'created_at': '2026-10-20T18:0${sequence % 10}:00Z',
      'media_url': mediaUrl,
      'media_content_type': mediaUrl == null ? null : 'image/png',
      'voice_seconds': voiceSeconds,
      'call_kind': callKind,
      'call_connected': callConnected,
      'call_duration_seconds': callSeconds,
    };

Map<String, dynamic> conversationSummary({
  String id = 'c-1',
  String status = 'accepted',
  bool requestedByMe = true,
  int unread = 0,
  String? photoUrl,
}) =>
    <String, dynamic>{
      'id': id,
      'counterpart': <String, dynamic>{
        'id': 'u-tutor',
        'name': 'Amara Okonkwo',
        'role': 'tutor',
        'photo_url': photoUrl,
      },
      'subject': 'Calculus',
      'status': status,
      'requested_by_me': requestedByMe,
      'score': 84,
      'unread_count': unread,
      'last_event_sequence': 1,
      'updated_at': '2026-10-21T18:00:00Z',
      'last_message': messageJson(
        id: 'm-1',
        sequence: 1,
        text: 'Hello, Maya.',
        fromMe: false,
      ),
    };

Map<String, dynamic> conversationDetail({
  String id = 'c-1',
  String status = 'accepted',
  bool requestedByMe = true,
  int readThrough = 0,
  int latest = 1,
}) =>
    <String, dynamic>{
      ...conversationSummary(
        id: id,
        status: status,
        requestedByMe: requestedByMe,
      ),
      'request_note': 'Could we start with derivatives?',
      'response_note': status == 'declined' ? 'Not the right fit.' : null,
      'read_through_sequence': readThrough,
      'latest_message_sequence': latest,
    };

Map<String, dynamic> messagePage({
  List<Map<String, dynamic>>? messages,
  int readThrough = 0,
  int unread = 0,
}) {
  final List<Map<String, dynamic>> list = messages ??
      <Map<String, dynamic>>[
        messageJson(),
      ];
  final int latest = list.isEmpty
      ? 0
      : list.map((Map<String, dynamic> m) => m['sequence'] as int).reduce(
            (int a, int b) => a > b ? a : b,
          );
  return <String, dynamic>{
    'messages': list,
    'latest_sequence': latest,
    'read_through_sequence': readThrough,
    'unread_count': unread,
    'has_more': false,
  };
}

/// An in-memory imitation of the FastAPI service.
class FakeApi {
  FakeApi({
    this.role = Role.student,
    this.complete = true,
  })  : profile = ownProfile(role: role, complete: complete),
        profileRole = role;

  final Role role;
  final bool complete;
  final List<Map<String, dynamic>> matches = <Map<String, dynamic>>[
    matchJson(),
  ];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> conversations = <Map<String, dynamic>>[
    conversationSummary(),
  ];
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[
    messageJson(),
  ];
  Map<String, dynamic> profile;
  final Role profileRole;

  int matchCalls = 0;
  int profilePuts = 0;
  int requestCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int readCalls = 0;
  int messageCalls = 0;
  int unread = 0;
  Map<String, String> lastMatchQuery = <String, String>{};

  bool failMatches = false;
  bool failProfileSave = false;
  bool failLogin = false;
  bool failRefresh = false;
  bool requireAuth = true;
  bool expireSession = false;

  late final http.Client client = MockClient(_handle);

  AppState state({bool autoInitialize = false}) => AppState(
        api: ApiClient(
          baseUrl: fakeBaseUrl,
          client: client,
          tokenStore: TokenStore(),
        ),
        autoInitialize: autoInitialize,
      );

  Future<http.Response> _handle(http.Request request) async {
    final String path = request.url.path;
    final String method = request.method;
    final String? auth = request.headers['Authorization'];
    final bool authed = auth != null && auth.startsWith('Bearer ');
    if (expireSession && path != '/auth/refresh') {
      return _json(<String, dynamic>{'detail': 'Session expired'}, 401);
    }
    if (requireAuth &&
        path != '/auth/login' &&
        path != '/auth/register' &&
        path != '/auth/refresh' &&
        path != '/areas' &&
        path != '/subjects' &&
        !path.startsWith('/users/') &&
        !path.startsWith('/media/') &&
        !authed) {
      return _json(<String, dynamic>{'detail': 'Not authenticated'}, 401);
    }

    if (method == 'GET' && path == '/areas') {
      return _json(<String, dynamic>{
        'regions': <String>['London'],
        'cities': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'london',
            'region': 'London',
            'name': 'London',
            'latitude': 51.5072,
            'longitude': -0.1276,
          },
        ],
        'areas': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'london-hackney',
            'city_id': 'london',
            'name': 'Hackney',
            'city': 'London',
            'region': 'London',
            'latitude': 51.5450,
            'longitude': -0.0553,
          },
        ],
      });
    }
    if (method == 'GET' && path == '/subjects') {
      return _json(<String, dynamic>{
        'subjects': <Map<String, String>>[
          <String, String>{'id': 'calculus', 'name': 'Calculus'},
          <String, String>{'id': 'physics', 'name': 'Physics'},
          <String, String>{'id': 'statistics', 'name': 'Statistics'},
        ],
      });
    }
    if (method == 'POST' && path == '/auth/login') {
      if (failLogin) {
        return _json(<String, dynamic>{'detail': 'Email or password is incorrect.'}, 401);
      }
      final Map<String, dynamic> body = _body(request);
      final bool tutor = (body['email'] as String? ?? '').contains('amara');
      final Role loginRole = tutor ? Role.tutor : Role.student;
      if (loginRole != role) {
        return _json(<String, dynamic>{'detail': 'Wrong account.'}, 401);
      }
      return _json(<String, dynamic>{
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'user': userJson(role: role, complete: complete),
      });
    }
    if (method == 'POST' && path == '/auth/refresh') {
      refreshCalls++;
      if (failRefresh) {
        return _json(<String, dynamic>{'detail': 'Invalid refresh token'}, 401);
      }
      return _json(<String, dynamic>{
        'access_token': 'access-2',
        'refresh_token': 'refresh-2',
      });
    }
    if (method == 'GET' && path == '/auth/me') {
      return _json(userJson(role: role, complete: complete));
    }
    if (method == 'POST' && path == '/auth/logout') {
      logoutCalls++;
      return http.Response('', 204);
    }
    if (method == 'GET' && path == '/profile') {
      return _json(profile);
    }
    if (method == 'PUT' && path == '/profile') {
      profilePuts++;
      if (failProfileSave) {
        return _json(<String, dynamic>{'detail': 'The profile could not be saved.'}, 500);
      }
      final Map<String, dynamic> body = _body(request);
      profile = <String, dynamic>{
        ...profile,
        ...body,
        'public_location': body['area_id'] == null
            ? null
            : profile['public_location'],
      };
      return _json(profile);
    }
    if (method == 'GET' && path == '/matches') {
      matchCalls++;
      lastMatchQuery = request.url.queryParameters;
      if (failMatches) {
        return _json(<String, dynamic>{'detail': 'Matching is unavailable.'}, 503);
      }
      return _json(<String, dynamic>{
        'matches': matches,
        'pool_size': 1,
        'ranked_count': 1,
        'cold_start': null,
      });
    }
    if (method == 'GET' && path == '/requests') {
      requestCalls++;
      return _json(requests);
    }
    if (method == 'POST' && path == '/requests') {
      final Map<String, dynamic> body = _body(request);
      final String createdId = 'c-${requests.length + 1}';
      final Map<String, dynamic> created = requestJson(
        id: createdId,
        conversationId: createdId,
        subject: body['subject'] as String? ?? 'Calculus',
      );
      requests.insert(0, created);
      conversations.insert(
        0,
        conversationSummary(
          id: created['conversation_id'] as String,
          status: 'pending',
          requestedByMe: true,
        ),
      );
      return _json(created);
    }
    final RegExp accept = RegExp(r'^/requests/([^/]+)/accept$');
    final RegExp decline = RegExp(r'^/requests/([^/]+)/decline$');
    if (method == 'POST' && accept.hasMatch(path)) {
      final String id = accept.firstMatch(path)!.group(1)!;
      return _json(_updateRequest(id, 'accepted'));
    }
    if (method == 'POST' && decline.hasMatch(path)) {
      final String id = decline.firstMatch(path)!.group(1)!;
      return _json(_updateRequest(id, 'declined'));
    }
    if (method == 'GET' && path == '/conversations') {
      return _json(conversations);
    }
    final RegExp conversation = RegExp(r'^/conversations/([^/]+)$');
    if (method == 'GET' && conversation.hasMatch(path)) {
      final String id = conversation.firstMatch(path)!.group(1)!;
      final Map<String, dynamic> summary = conversations.firstWhere(
        (Map<String, dynamic> c) => c['id'] == id,
        orElse: () => conversationSummary(id: id, unread: unread),
      );
      return _json(<String, dynamic>{
        ...summary,
        'unread_count': unread,
        'request_note': 'Could we start with derivatives?',
        'response_note': null,
        'read_through_sequence': 0,
        'latest_message_sequence': messages.isEmpty ? 0 : 1,
      });
    }
    final RegExp messagesPath = RegExp(r'^/conversations/([^/]+)/messages$');
    if (method == 'GET' && messagesPath.hasMatch(path)) {
      messageCalls++;
      final String? after = request.url.queryParameters['after'];
      final List<Map<String, dynamic>> visible = after == null
          ? messages
          : messages
              .where((Map<String, dynamic> m) =>
                  (m['sequence'] as int) > int.parse(after))
              .toList();
      return _json(messagePage(messages: visible, unread: unread));
    }
    if (method == 'POST' && messagesPath.hasMatch(path)) {
      final Map<String, dynamic> body = _body(request);
      final Map<String, dynamic> sent = messageJson(
        id: 'm-${messages.length + 1}',
        sequence: messages.length + 1,
        text: body['text'] as String? ?? '',
        fromMe: true,
        read: false,
      );
      messages.add(sent);
      return _json(sent);
    }
    final RegExp readPath = RegExp(r'^/conversations/([^/]+)/read$');
    if (method == 'POST' && readPath.hasMatch(path)) {
      readCalls++;
      return _json(<String, dynamic>{
        'read_through_sequence': 1,
        'latest_message_sequence': 1,
        'unread_count': 0,
      });
    }
    final RegExp photoPath = RegExp(r'^/users/([^/]+)/photo$');
    if (method == 'GET' && photoPath.hasMatch(path)) {
      return http.Response.bytes(redDot, 200, headers: <String, String>{
        'content-type': 'image/png',
      });
    }
    if (method == 'GET' && path.startsWith('/media/')) {
      return http.Response.bytes(redDot, 200, headers: <String, String>{
        'content-type': 'image/png',
      });
    }
    return _json(<String, dynamic>{'detail': 'No route for $method $path'}, 404);
  }

  Map<String, dynamic> _updateRequest(String id, String status) {
    for (int i = 0; i < requests.length; i++) {
      if (requests[i]['id'] == id) {
        requests[i] = <String, dynamic>{
          ...requests[i],
          'status': status,
          'updated_at': '2026-10-22T18:00:00Z',
        };
        return requests[i];
      }
    }
    final Map<String, dynamic> made = requestJson(id: id, status: status);
    requests.add(made);
    return made;
  }

  Map<String, dynamic> _body(http.Request request) {
    if (request.body.isEmpty) return <String, dynamic>{};
    final dynamic decoded = jsonDecode(request.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}

/// Installs the shared-preferences shim every token-store test needs.
void mockPreferences() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

/// Loads the bundled faces so widget measurements match the browser.
Future<void> loadBundledFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final FontLoader loader = FontLoader(name);
    for (final String asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('Bricolage Grotesque', <String>[
    'assets/fonts/BricolageGrotesque-Variable.ttf',
  ]);
  await family('Figtree', <String>['assets/fonts/Figtree-Variable.ttf']);
  await family('IBM Plex Mono', <String>[
    'assets/fonts/IBMPlexMono-Regular.ttf',
    'assets/fonts/IBMPlexMono-Medium.ttf',
  ]);
  await family('PhosphorRegular', <String>[
    'assets/fonts/PhosphorRegular.ttf',
  ]);
  await family('PhosphorBold', <String>['assets/fonts/PhosphorBold.ttf']);
}

/// Pumps a widget inside the real theme and state scope.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen,
  AppState state, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppStateScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
