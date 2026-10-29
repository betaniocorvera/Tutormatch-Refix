import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:tutormatch/data/token_store.dart';

/// The one address the app talks to. Override it at build time:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const <String, String>{},
  });

  final String message;
  final int? statusCode;

  /// FastAPI 422 entries keyed by a dotted field path, for example
  /// `email` or `security_questions.0.answer`. Values are already cleaned of
  /// the Pydantic "Value error, " prefix so they can be shown inline.
  final Map<String, String> fieldErrors;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Low-level HTTP transport. It knows about JSON, bearer tokens, one retry
/// after a refresh, and multipart uploads — nothing about profiles or matches.
class ApiClient {
  ApiClient({
    String baseUrl = apiBaseUrl,
    http.Client? client,
    TokenStore? tokenStore,
    this.onUnauthorized,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _tokens = tokenStore ?? TokenStore();

  final String _baseUrl;
  final http.Client _client;
  final TokenStore _tokens;
  void Function()? onUnauthorized;

  Future<AuthTokens?> readTokens() => _tokens.read();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      _tokens.save(AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ));

  Future<void> clearTokens() => _tokens.clear();

  Uri resolve(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.parse('$_baseUrl${path.startsWith('/') ? path : '/$path'}');
  }

  Future<dynamic> getJson(
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    bool auth = true,
  }) async {
    final http.Response response = await _send(
      (String? token) => _client.get(
        _uri(path, query),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 25)),
      auth: auth,
    );
    return _decode(response);
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, Object?> query = const <String, Object?>{},
    bool auth = true,
  }) async {
    final http.Response response = await _send(
      (String? token) => _client
          .post(
            _uri(path, query),
            headers: _headers(token, json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25)),
      auth: auth,
    );
    return _decode(response);
  }

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Map<String, Object?> query = const <String, Object?>{},
    bool auth = true,
  }) async {
    final http.Response response = await _send(
      (String? token) => _client
          .put(
            _uri(path, query),
            headers: _headers(token, json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25)),
      auth: auth,
    );
    return _decode(response);
  }

  Future<dynamic> delete(
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    bool auth = true,
  }) async {
    final http.Response response = await _send(
      (String? token) => _client.delete(
        _uri(path, query),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 25)),
      auth: auth,
    );
    return _decode(response);
  }

  Future<Uint8List> getBytes(String path, {bool auth = true}) async {
    final http.Response response = await _send(
      (String? token) => _client.get(
        resolve(path),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 25)),
      auth: auth,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response);
    }
    return response.bodyBytes;
  }

  Future<dynamic> postMultipart(
    String path, {
    required Uint8List bytes,
    required String filename,
    String field = 'file',
  }) async {
    Future<http.Response> send(String? token) async {
      final http.MultipartRequest request =
          http.MultipartRequest('POST', resolve(path));
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
      ));
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(const Duration(seconds: 45));
      return http.Response.fromStream(streamed);
    }

    final http.Response response = await _send(send);
    return _decode(response);
  }

  Uri _uri(String path, Map<String, Object?> query) {
    final Uri base = resolve(path);
    if (query.isEmpty) return base;
    final List<String> parts = <String>[];
    void add(String key, Object? value) {
      if (value == null) return;
      if (value is Iterable && value is! String) {
        for (final Object? item in value) {
          if (item != null) add(key, item);
        }
        return;
      }
      parts.add('${Uri.encodeQueryComponent(key)}='
          '${Uri.encodeQueryComponent(value.toString())}');
    }

    query.forEach(add);
    if (parts.isEmpty) return base;
    return base.replace(query: parts.join('&'));
  }

  Map<String, String> _headers(String? token, {bool json = false}) => <String, String>{
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _send(
    Future<http.Response> Function(String? token) request, {
    bool auth = true,
  }) async {
    String? token;
    if (auth) {
      token = (await _tokens.read())?.accessToken;
    }

    http.Response response;
    try {
      response = await request(token);
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to answer. Check that it is running and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the TutorMatch server. Check the API address and your connection.',
      );
    } on Exception {
      throw const ApiException(
        'Cannot reach the TutorMatch server. Check the API address and your connection.',
      );
    }

    if (response.statusCode == 401 && auth) {
      final bool refreshed = await _refresh();
      if (refreshed) {
        token = (await _tokens.read())?.accessToken;
        try {
          response = await request(token);
        } on Exception {
          throw const ApiException(
            'Cannot reach the TutorMatch server. Check the API address and your connection.',
          );
        }
      } else {
        await _tokens.clear();
        onUnauthorized?.call();
      }
    }

    if (response.statusCode == 401 && auth) {
      await _tokens.clear();
      onUnauthorized?.call();
    }
    return response;
  }

  Future<bool> _refresh() async {
    final AuthTokens? current = await _tokens.read();
    if (current == null) return false;
    try {
      final http.Response response = await _client
          .post(
            resolve('/auth/refresh'),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'refresh_token': current.refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? access = body['access_token'] as String?;
      final String? refresh = body['refresh_token'] as String?;
      if (access == null || refresh == null) return false;
      await _tokens.save(AuthTokens(
        accessToken: access,
        refreshToken: refresh,
      ));
      return true;
    } on Exception {
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 204) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response);
    }
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        'The server returned an unexpected response.',
        statusCode: response.statusCode,
      );
    }
  }

  ApiException _error(http.Response response) {
    String message = switch (response.statusCode) {
      401 => 'Your session has expired. Sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'That item no longer exists.',
      409 => 'That action is not available in the current state.',
      413 => 'That file is too large.',
      422 => 'Check the highlighted fields and try again.',
      429 => 'Too many attempts. Wait a moment and try again.',
      >= 500 => 'The server could not complete that request.',
      _ => 'The request could not be completed.',
    };
    final Map<String, String> fieldErrors = <String, String>{};
    try {
      final dynamic body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        final dynamic detail = body['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          final List<String> messages = <String>[];
          for (final dynamic item in detail) {
            if (item is! Map) continue;
            final dynamic rawMessage = item['msg'];
            if (rawMessage is! String) continue;
            final String cleaned = rawMessage
                .replaceFirst(RegExp(r'^Value error,\s*'), '')
                .trim();
            if (cleaned.isEmpty) continue;
            messages.add(cleaned);

            final dynamic loc = item['loc'];
            if (loc is List) {
              final List<String> parts = <String>[
                for (final dynamic part in loc)
                  if (part != 'body' && (part is String || part is int))
                    part.toString(),
              ];
              if (parts.isNotEmpty) {
                fieldErrors.putIfAbsent(parts.join('.'), () => cleaned);
              }
            }
          }
          if (messages.isNotEmpty) message = messages.join(' ');
        }
      }
    } on FormatException {
      // Keep the status-specific fallback.
    }
    return ApiException(
      message,
      statusCode: response.statusCode,
      fieldErrors: fieldErrors,
    );
  }
}
