import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';

class CatalogRepository {
  const CatalogRepository(this.api);

  final ApiClient api;

  Future<AreaCatalogue> areas() async {
    final Map<String, dynamic> json =
        jsonObject(await api.getJson('/areas', auth: false));
    final List<City> cities = <City>[
      for (final dynamic city in jsonList(json['cities']))
        City.fromJson(jsonObject(city)),
    ];
    final Map<String, City> byId = <String, City>{
      for (final City city in cities) city.id: city,
    };
    return AreaCatalogue(
      regions: <String>[
        for (final dynamic region in jsonList(json['regions']))
          jsonString(region),
      ],
      cities: cities,
      places: <Place>[
        for (final dynamic area in jsonList(json['areas']))
          _place(jsonObject(area), byId),
      ],
    );
  }

  Future<List<SubjectOption>> subjects() async {
    final Map<String, dynamic> json =
        jsonObject(await api.getJson('/subjects', auth: false));
    return <SubjectOption>[
      for (final dynamic subject in jsonList(json['subjects']))
        SubjectOption.fromJson(jsonObject(subject)),
    ];
  }

  Place _place(Map<String, dynamic> json, Map<String, City> cities) {
    final String cityId = jsonString(json['city_id']);
    final City city = cities[cityId] ??
        City(
          id: cityId,
          region: jsonString(json['region']),
          name: jsonString(json['city']),
          latitude: jsonDouble(json['latitude']),
          longitude: jsonDouble(json['longitude']),
        );
    return Place(
      id: jsonString(json['id']),
      city: city,
      name: jsonString(json['name']),
      latitude: jsonDouble(json['latitude']),
      longitude: jsonDouble(json['longitude']),
    );
  }
}
