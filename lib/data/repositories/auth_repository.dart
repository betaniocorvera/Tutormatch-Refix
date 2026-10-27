import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';

class AuthRepository {
  const AuthRepository(this.api);

  final ApiClient api;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> json = jsonObject(await api.postJson(
      '/auth/login',
      body: <String, String>{'email': email, 'password': password},
      auth: false,
    ));
    return _store(AuthSession.fromJson(json));
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    required Role role,
    required String displayName,
  }) async {
    final Map<String, dynamic> json = jsonObject(await api.postJson(
      '/auth/register',
      body: <String, String>{
        'email': email,
        'password': password,
        'role': roleToApi(role),
        'display_name': displayName,
      },
      auth: false,
    ));
    return _store(AuthSession.fromJson(json));
  }

  Future<UserAccount> me() async =>
      UserAccount.fromJson(jsonObject(await api.getJson('/auth/me')));

  Future<void> logout() async {
    final String? refresh = (await api.readTokens())?.refreshToken;
    try {
      await api.postJson(
        '/auth/logout',
        body: refresh == null
            ? null
            : <String, String>{'refresh_token': refresh},
      );
    } on ApiException {
      // Signing out locally must succeed even when the server is unreachable.
    }
    await api.clearTokens();
  }

  Future<AuthSession> _store(AuthSession session) async {
    await api.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    return session;
  }
}
