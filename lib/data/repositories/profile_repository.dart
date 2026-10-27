import 'dart:typed_data';

import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';

class ProfileRepository {
  const ProfileRepository(this.api);

  final ApiClient api;

  Future<Profile> getOwn() async =>
      Profile.fromJson(jsonObject(await api.getJson('/profile')));

  Future<Profile> update(Profile profile) async => Profile.fromJson(
        jsonObject(await api.putJson('/profile', body: profile.toUpdateJson())),
      );

  Future<Profile> uploadPhoto(Uint8List bytes, String filename) async =>
      Profile.fromJson(jsonObject(await api.postMultipart(
        '/profile/photo',
        bytes: bytes,
        filename: filename,
      )));

  Future<void> deletePhoto() async {
    await api.delete('/profile/photo');
  }

  Future<Uint8List> getPhoto(String userId) =>
      api.getBytes('/users/$userId/photo');

  Future<Candidate> getPublic(String userId) async =>
      Candidate.fromPublicJson(jsonObject(await api.getJson('/users/$userId')));
}
