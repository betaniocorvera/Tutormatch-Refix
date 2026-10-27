import 'package:shared_preferences/shared_preferences.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Refresh tokens live in platform storage so a browser reload does not throw
/// the session away. The access token is stored beside it because the API is
/// the only reader and the pair is always written together.
class TokenStore {
  static const String _accessKey = 'tutormatch.access_token';
  static const String _refreshKey = 'tutormatch.refresh_token';

  Future<AuthTokens?> read() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? access = preferences.getString(_accessKey);
    final String? refresh = preferences.getString(_refreshKey);
    if (access == null || refresh == null) return null;
    if (access.isEmpty || refresh.isEmpty) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> save(AuthTokens tokens) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessKey, tokens.accessToken);
    await preferences.setString(_refreshKey, tokens.refreshToken);
  }

  Future<void> clear() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessKey);
    await preferences.remove(_refreshKey);
  }
}
