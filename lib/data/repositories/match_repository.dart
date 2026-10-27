import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';

class MatchRepository {
  const MatchRepository(this.api);

  final ApiClient api;

  Future<MatchBatch> fetch(MatchFilters filters) async {
    final Map<String, Object?> query = <String, Object?>{
      if (filters.subjects.isNotEmpty) 'subjects': filters.subjects.toList(),
      if (filters.mode != null) 'mode': filters.mode!.apiValue,
      if (filters.maxRate < 80) 'max_rate': filters.maxRate,
      if (filters.requiredParts.isNotEmpty)
        'required_parts': filters.requiredParts.toList()..sort(),
      if (filters.mustBeFreeWhenIAm) 'must_be_free_when_i_am': true,
      if (filters.maxDistanceKm != null)
        'max_distance_km': filters.maxDistanceKm,
      if (filters.minScore > 0) 'min_score': filters.minScore,
      'limit': 100,
    };
    return MatchBatch.fromJson(
      jsonObject(await api.getJson('/matches', query: query)),
    );
  }
}
