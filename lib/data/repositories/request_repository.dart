import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';

class RequestRepository {
  const RequestRepository(this.api);

  final ApiClient api;

  Future<List<MatchRequest>> list() async {
    final dynamic body = await api.getJson(
      '/requests',
      query: const <String, Object?>{'direction': 'all'},
    );
    return <MatchRequest>[
      for (final dynamic item in jsonList(body))
        MatchRequest.fromJson(jsonObject(item)),
    ];
  }

  Future<MatchRequest> create({
    required String counterpartId,
    required String subject,
    required String note,
  }) async =>
      MatchRequest.fromJson(jsonObject(await api.postJson(
        '/requests',
        body: <String, String>{
          'counterpart_id': counterpartId,
          'subject': subject,
          'note': note,
        },
      )));

  Future<MatchRequest> accept(String id, {String? note}) async =>
      MatchRequest.fromJson(jsonObject(await api.postJson(
        '/requests/$id/accept',
        body: note == null ? null : <String, String>{'note': note},
      )));

  Future<MatchRequest> decline(String id, String reason) async =>
      MatchRequest.fromJson(jsonObject(await api.postJson(
        '/requests/$id/decline',
        body: <String, String>{'reason': reason},
      )));
}
