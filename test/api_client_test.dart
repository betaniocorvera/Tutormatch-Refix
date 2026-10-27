import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/token_store.dart';

import 'test_support.dart';

void main() {
  setUp(mockPreferences);

  test('attaches the stored bearer token to authenticated requests', () async {
    final TokenStore store = TokenStore();
    await store.save(const AuthTokens(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    ));

    String? seen;
    final ApiClient api = ApiClient(
      baseUrl: fakeBaseUrl,
      tokenStore: store,
      client: MockClient((http.Request request) async {
        seen = request.headers['Authorization'];
        return http.Response(jsonEncode(<String, dynamic>{'ok': true}), 200);
      }),
    );

    expect(await api.getJson('/profile'), <String, dynamic>{'ok': true});
    expect(seen, 'Bearer access-1');
  });

  test('refreshes once on 401, stores the new pair and retries', () async {
    final TokenStore store = TokenStore();
    await store.save(const AuthTokens(
      accessToken: 'expired',
      refreshToken: 'refresh-1',
    ));

    int profileCalls = 0;
    int refreshCalls = 0;
    bool unauthorized = false;
    final ApiClient api = ApiClient(
      baseUrl: fakeBaseUrl,
      tokenStore: store,
      onUnauthorized: () => unauthorized = true,
      client: MockClient((http.Request request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          expect(
            jsonDecode(request.body),
            <String, dynamic>{'refresh_token': 'refresh-1'},
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'access-2',
              'refresh_token': 'refresh-2',
            }),
            200,
          );
        }
        profileCalls++;
        if (request.headers['Authorization'] == 'Bearer access-2') {
          return http.Response(
            jsonEncode(<String, dynamic>{'name': 'Maya'}),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'detail': 'expired'}),
          401,
        );
      }),
    );

    expect(
      await api.getJson('/profile'),
      <String, dynamic>{'name': 'Maya'},
    );
    expect(profileCalls, 2);
    expect(refreshCalls, 1);
    expect(unauthorized, isFalse);
    expect((await store.read())?.accessToken, 'access-2');
    expect((await store.read())?.refreshToken, 'refresh-2');
  });

  test('clears tokens and reports logout when the refresh fails', () async {
    final TokenStore store = TokenStore();
    await store.save(const AuthTokens(
      accessToken: 'expired',
      refreshToken: 'bad-refresh',
    ));

    bool unauthorized = false;
    final ApiClient api = ApiClient(
      baseUrl: fakeBaseUrl,
      tokenStore: store,
      onUnauthorized: () => unauthorized = true,
      client: MockClient((http.Request request) async {
        if (request.url.path == '/auth/refresh') {
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'Invalid refresh token'}),
            401,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Not authenticated'}),
          401,
        );
      }),
    );

    await expectLater(
      api.getJson('/profile'),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.statusCode, 'status', 401)),
    );
    expect(unauthorized, isTrue);
    expect(await store.read(), isNull);
  });

  test('surfaces the server detail and falls back on network failure', () async {
    final ApiClient api = ApiClient(
      baseUrl: fakeBaseUrl,
      tokenStore: TokenStore(),
      client: MockClient((http.Request request) async {
        if (request.url.path == '/missing') {
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'That request is closed.'}),
            409,
          );
        }
        throw http.ClientException('offline');
      }),
    );

    await expectLater(
      api.getJson('/missing'),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.message, 'message',
              'That request is closed.')
          .having((ApiException e) => e.statusCode, 'status', 409)),
    );
    await expectLater(
      api.getJson('/offline'),
      throwsA(isA<ApiException>().having(
        (ApiException e) => e.message,
        'message',
        contains('Cannot reach the TutorMatch server'),
      )),
    );
  });
}
