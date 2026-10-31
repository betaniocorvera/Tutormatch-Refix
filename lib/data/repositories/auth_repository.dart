import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';

class LoginOtpRequired implements Exception {
  const LoginOtpRequired({
    required this.challengeId,
    this.expiresAt,
  });

  final String challengeId;
  final DateTime? expiresAt;
}

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
    if (json['otp_required'] == true) {
      throw LoginOtpRequired(
        challengeId: jsonString(json['challenge_id']),
        expiresAt: jsonDate(json['expires_at']),
      );
    }
    return _store(AuthSession.fromJson(json));
  }

  Future<AuthSession> verifyLoginOtp({
    required String challengeId,
    required String code,
  }) async {
    final Map<String, dynamic> json = jsonObject(await api.postJson(
      '/auth/login/otp/verify',
      body: <String, String>{
        'challenge_id': challengeId,
        'code': code,
      },
      auth: false,
    ));
    return _store(AuthSession.fromJson(json));
  }

  Future<AuthSession> register({
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
    final Map<String, dynamic> json = jsonObject(await api.postJson(
      '/auth/register',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        'role': roleToApi(role),
        'display_name': displayName,
        'phone': phone,
        'area_id': areaId,
        'subjects': subjects,
        'security_questions': <Map<String, String>>[
          for (final SecurityAnswerInput item in securityQuestions)
            <String, String>{
              'question_id': item.questionId,
              'answer': item.answer,
            },
        ],
        'privacy_consent': privacyConsent,
        'privacy_policy_version': privacyPolicyVersion,
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
