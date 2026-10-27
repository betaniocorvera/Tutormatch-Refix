import 'dart:typed_data';

import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';

class ConversationRepository {
  const ConversationRepository(this.api);

  final ApiClient api;

  Future<List<Conversation>> list({RequestStatus? status}) async {
    final dynamic body = await api.getJson(
      '/conversations',
      query: <String, Object?>{
        if (status != null) 'status': status.apiValue,
      },
    );
    return <Conversation>[
      for (final dynamic item in jsonList(body))
        Conversation.fromSummaryJson(jsonObject(item)),
    ];
  }

  Future<Conversation> get(String id) async => Conversation.fromDetailJson(
        jsonObject(await api.getJson('/conversations/$id')),
      );

  Future<MessagePageData> messages(
    String id, {
    int limit = 100,
    int? before,
    int? after,
  }) async =>
      MessagePageData.fromJson(jsonObject(await api.getJson(
        '/conversations/$id/messages',
        query: <String, Object?>{
          'limit': limit,
          'before': ?before,
          'after': ?after,
        },
      )));

  Future<ChatMessage> sendText(String id, String text) async =>
      ChatMessage.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/messages',
        body: <String, String>{'text': text},
      )));

  Future<ChatMessage> sendImage(
    String id,
    Uint8List bytes,
    String filename,
  ) async =>
      ChatMessage.fromJson(jsonObject(await api.postMultipart(
        '/conversations/$id/messages/image',
        bytes: bytes,
        filename: filename,
      )));

  Future<ChatMessage> sendVoiceNote(String id, int seconds) async =>
      ChatMessage.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/messages/voice-note',
        body: <String, int>{'duration_seconds': seconds},
      )));

  Future<ChatMessage> proposeSession(String id, DateTime at) async =>
      ChatMessage.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/sessions',
        body: <String, String>{
          'proposed_for': at.toUtc().toIso8601String(),
        },
      )));

  Future<ChatMessage> respondToSession(
    String id,
    String messageId,
    SessionState state,
  ) async =>
      ChatMessage.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/sessions/$messageId/respond',
        body: <String, String>{'state': state.name},
      )));

  Future<ChatMessage> logCall(
    String id, {
    required String kind,
    required bool connected,
    required int durationSeconds,
  }) async =>
      ChatMessage.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/calls',
        body: <String, Object>{
          'kind': kind,
          'connected': connected,
          'duration_seconds': durationSeconds,
        },
      )));

  Future<ReadStateData> markRead(String id, {int? throughSequence}) async =>
      ReadStateData.fromJson(jsonObject(await api.postJson(
        '/conversations/$id/read',
        body: <String, Object?>{
          'through_sequence': ?throughSequence,
        },
      )));

  Future<Uint8List> media(String mediaUrl) => api.getBytes(mediaUrl);
}
