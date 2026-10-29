// Domain models shared by the API layer and the interface.
//
// The shapes here mirror the FastAPI responses. Display-only values that the
// backend deliberately does not expose (ratings, review counts, decorative
// profile tints) either stay empty or are derived from a real field; nothing in
// this file invents a person, a score, or a social-proof figure.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:tutormatch/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JSON helpers
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> jsonList(Object? value) =>
    value is List ? value : const <dynamic>[];

String jsonString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int jsonInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? jsonIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double jsonDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? jsonDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool jsonBool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

DateTime? jsonDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

DateTime? jsonDateOnly(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final List<String> parts = value.split('-');
  if (parts.length == 3) {
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }
  return jsonDate(value);
}

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

Role roleFromApi(Object? value) =>
    jsonString(value) == 'tutor' ? Role.tutor : Role.student;

String roleToApi(Role role) => role == Role.tutor ? 'tutor' : 'student';

// ─────────────────────────────────────────────────────────────────────────────
// Time
// ─────────────────────────────────────────────────────────────────────────────

/// One half of the week's timetable: seven days by three parts of the day.
/// Stored as a flat 21-cell grid in day-major order.
abstract final class Week {
  static const List<String> days = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> dayLong = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> partKeys = <String>['Morn', 'Aft', 'Eve'];
  static const List<String> partShort = <String>['AM', 'PM', 'EVE'];
  static const List<String> partLong = <String>['mornings', 'afternoons', 'evenings'];

  static const int cells = 21;
  static int index(int day, int part) => day * 3 + part;
}

List<bool> avail(List<String> keys) {
  final List<bool> grid = List<bool>.filled(Week.cells, false);
  for (final String key in keys) {
    final List<String> parts = key.split('-');
    if (parts.length != 2) {
      throw ArgumentError.value(key, 'key', 'Expected a slot like "Mon-Eve"');
    }
    final int day = Week.days.indexOf(parts[0]);
    final int part = Week.partKeys.indexOf(parts[1]);
    if (day < 0 || part < 0) {
      throw ArgumentError.value(key, 'key', 'Unknown day or part of day');
    }
    grid[Week.index(day, part)] = true;
  }
  return grid;
}

List<bool> availabilityFromJson(Object? value) {
  final List<bool> cells = <bool>[
    for (final dynamic cell in jsonList(value)) jsonBool(cell),
  ];
  if (cells.length == Week.cells) return cells;
  return List<bool>.filled(Week.cells, false);
}

List<bool> overlapOf(List<bool> a, List<bool> b) =>
    List<bool>.generate(Week.cells, (int i) => a[i] && b[i]);

String? describeOverlap(List<bool> grid) {
  if (grid.length != Week.cells || !grid.contains(true)) return null;
  final List<String> dayNames = <String>[];
  final Set<String> parts = <String>{};
  for (int d = 0; d < Week.days.length; d++) {
    final List<int> hit = <int>[
      for (int p = 0; p < Week.partKeys.length; p++)
        if (grid[Week.index(d, p)]) p,
    ];
    if (hit.isEmpty) continue;
    dayNames.add(Week.days[d]);
    for (final int p in hit) {
      parts.add(Week.partLong[p]);
    }
  }
  final String days = switch (dayNames.length) {
    1 => dayNames.first,
    2 => '${dayNames[0]} and ${dayNames[1]}',
    _ => '${dayNames.take(dayNames.length - 1).join(', ')} and ${dayNames.last}',
  };
  return '$days ${parts.length == 1 ? parts.first : 'at various times'}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Matching
// ─────────────────────────────────────────────────────────────────────────────

enum MatchDimension {
  subjects(
    'Subjects',
    40,
    'What you need help with, set against what they actually teach or want to learn.',
    'Add one more subject and the list grows quickly — most tutors cover three or four.',
  ),
  time(
    'Available time',
    25,
    'The hours you are both free in a normal week, counted cell by cell.',
    'This is the dimension that empties a list. One shared block a week is often enough to start.',
  ),
  style(
    'Style',
    15,
    'How you like to work: worked examples, first principles, discussion, drill.',
    'Worth compromising last. A mismatch here is felt in every single session.',
  ),
  format(
    'Online or in person',
    10,
    'Whether either of you is willing to travel, or would rather stay on a call.',
    'Online widens the list more than any other single change on this page.',
  ),
  budget(
    'Budget',
    10,
    'The hourly rate against what the other side can spend.',
    'A five-dollar gap is usually one session a month, not a decision about quality.',
  );

  const MatchDimension(this.label, this.max, this.explainer, this.widening);

  final String label;
  final int max;
  final String explainer;
  final String widening;

  String get weightCopy => '$max of 100';

  static MatchDimension fromApi(String value) => switch (value) {
        'time' => MatchDimension.time,
        'style' => MatchDimension.style,
        'format' => MatchDimension.format,
        'budget' => MatchDimension.budget,
        _ => MatchDimension.subjects,
      };
}

class MatchScore {
  const MatchScore({
    required this.byDimension,
    required this.overlap,
    this.totalOverride,
  });

  final Map<MatchDimension, int> byDimension;
  final List<bool> overlap;

  /// The server's total when the score came over the wire; null for scores
  /// assembled locally, in which case the dimensions are summed.
  final int? totalOverride;

  int get total =>
      totalOverride ?? byDimension.values.fold(0, (int a, int b) => a + b);
  int get overlapSlots => overlap.where((bool c) => c).length;

  factory MatchScore.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> dimensions = jsonObject(json['dimensions']);
    return MatchScore(
      byDimension: <MatchDimension, int>{
        for (final MatchDimension dimension in MatchDimension.values)
          dimension: jsonInt(jsonObject(dimensions[dimension.name])['score']),
      },
      overlap: availabilityFromJson(json['overlap']),
      totalOverride: jsonInt(json['score']),
    );
  }
}

enum MatchTier { strong, good, possible, weak }

MatchTier tierFor(int score) => switch (score) {
      >= 80 => MatchTier.strong,
      >= 60 => MatchTier.good,
      >= 40 => MatchTier.possible,
      _ => MatchTier.weak,
    };

MatchTier matchTierFromApi(Object? value) => switch (jsonString(value)) {
      'strong' => MatchTier.strong,
      'good' => MatchTier.good,
      'possible' => MatchTier.possible,
      _ => MatchTier.weak,
    };

extension MatchTierCopy on MatchTier {
  String get label => switch (this) {
        MatchTier.strong => 'Strong match',
        MatchTier.good => 'Good match',
        MatchTier.possible => 'Worth a look',
        MatchTier.weak => 'Long shot',
      };

  String get meaning => switch (this) {
        MatchTier.strong => 'Close on nearly everything that matters to you.',
        MatchTier.good => 'Solid on the important parts, with one real gap.',
        MatchTier.possible => 'Some overlap, but you would be compromising.',
        MatchTier.weak => 'Little in common. Shown so you can see the spread.',
      };

  StatusTone get tone => switch (this) {
        MatchTier.strong || MatchTier.good => StatusTone.accepted,
        MatchTier.possible => StatusTone.pending,
        MatchTier.weak => StatusTone.neutral,
      };
}

class FitNote {
  const FitNote(this.dimension, this.signal, this.detail, {this.label});

  final String signal;
  final String detail;
  final MatchDimension dimension;
  final String? label;

  String get dimensionLabel => label ?? dimension.label;

  factory FitNote.fromJson(Map<String, dynamic> json) => FitNote(
        MatchDimension.fromApi(jsonString(json['dimension'])),
        jsonString(json['signal']),
        jsonString(json['detail']),
        label: jsonString(json['label']).isEmpty
            ? null
            : jsonString(json['label']),
      );
}

enum SessionMode { online, inPerson, both }

extension SessionModeCopy on SessionMode {
  String get label => switch (this) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Either is fine',
      };

  String get counterLabel => switch (this) {
        SessionMode.online => 'in person',
        SessionMode.inPerson => 'online',
        SessionMode.both => 'either way',
      };

  String get apiValue => switch (this) {
        SessionMode.online => 'online',
        SessionMode.inPerson => 'in_person',
        SessionMode.both => 'both',
      };

  bool accepts(SessionMode other) =>
      this == other || this == SessionMode.both || other == SessionMode.both;
}

SessionMode sessionModeFromApi(Object? value) => switch (jsonString(value)) {
      'online' => SessionMode.online,
      'in_person' => SessionMode.inPerson,
      _ => SessionMode.both,
    };

enum PresenceStatus { available, busy, away }

extension PresenceStatusCopy on PresenceStatus {
  String get label => switch (this) {
        PresenceStatus.available => 'Available',
        PresenceStatus.busy => 'Busy',
        PresenceStatus.away => 'Away',
      };

  String get apiValue => switch (this) {
        PresenceStatus.available => 'available',
        PresenceStatus.busy => 'busy',
        PresenceStatus.away => 'away',
      };

  StatusTone get tone => switch (this) {
        PresenceStatus.available => StatusTone.accepted,
        PresenceStatus.busy => StatusTone.pending,
        PresenceStatus.away => StatusTone.neutral,
      };
}

PresenceStatus presenceFromApi(Object? value) => switch (jsonString(value)) {
      'busy' => PresenceStatus.busy,
      'away' => PresenceStatus.away,
      _ => PresenceStatus.available,
    };

// ─────────────────────────────────────────────────────────────────────────────
// Places
// ─────────────────────────────────────────────────────────────────────────────

enum LocationPrivacy {
  area(
    'Show my area on my profile and in Search',
    'People see the neighbourhood and a circle of about 1–2 km. Never a '
        'street, a building or a house number.',
  ),
  cityOnly(
    'Show city only',
    'People see the city and a circle around its centre. The neighbourhood is '
        'not shown.',
  ),
  hidden(
    'Hide my location',
    'People see no map, no area and no distance. You will not appear in '
        'distance-filtered results.',
  );

  const LocationPrivacy(this.label, this.explanation);

  final String label;
  final String explanation;

  String get apiValue => switch (this) {
        LocationPrivacy.area => 'area',
        LocationPrivacy.cityOnly => 'city_only',
        LocationPrivacy.hidden => 'hidden',
      };
}

LocationPrivacy locationPrivacyFromApi(Object? value) =>
    switch (jsonString(value)) {
      'area' => LocationPrivacy.area,
      'hidden' => LocationPrivacy.hidden,
      _ => LocationPrivacy.cityOnly,
    };

class City {
  const City({
    required this.id,
    required this.region,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String region;
  final String name;
  final double latitude;
  final double longitude;

  factory City.fromJson(Map<String, dynamic> json) => City(
        id: jsonString(json['id']),
        region: jsonString(json['region']),
        name: jsonString(json['name']),
        latitude: jsonDouble(json['latitude']),
        longitude: jsonDouble(json['longitude']),
      );
}

class Place {
  const Place({
    required this.id,
    required this.city,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final City city;
  final String name;
  final double latitude;
  final double longitude;

  String get label => '$name, ${city.name}';
}

class PublicPlace {
  const PublicPlace({
    required this.label,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.cityOnly,
    this.region = '',
  });

  final String label;
  final String city;
  final String region;
  final double latitude;
  final double longitude;
  final bool cityOnly;

  factory PublicPlace.fromJson(Map<String, dynamic> json) => PublicPlace(
        label: jsonString(json['label']),
        city: jsonString(json['city']),
        region: jsonString(json['region']),
        latitude: jsonDouble(json['latitude']),
        longitude: jsonDouble(json['longitude']),
        cityOnly: jsonBool(json['city_only']),
      );
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusKm = 6371.0088;
  final double dLat = _radians(lat2 - lat1);
  final double dLon = _radians(lon2 - lon1);
  final double a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusKm * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

double _radians(double degrees) => degrees * math.pi / 180;

double? distanceBetween(PublicPlace? from, PublicPlace? to) {
  if (from == null || to == null) return null;
  return haversineKm(from.latitude, from.longitude, to.latitude, to.longitude);
}

String describeDistance(double km) =>
    km < 1 ? 'less than 1 km away' : 'about ${km.round()} km away';

const int nearbyDistanceKm = 5;

// ─────────────────────────────────────────────────────────────────────────────
// Profiles
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String describeDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

String describeShortDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1].substring(0, 3)} ${date.year}';

int ageOn(DateTime birthdate, DateTime on) {
  final int years = on.year - birthdate.year;
  final bool hadBirthday = on.month > birthdate.month ||
      (on.month == birthdate.month && on.day >= birthdate.day);
  return hadBirthday ? years : years - 1;
}

class Profile {
  const Profile({
    required this.role,
    required this.name,
    required this.subjects,
    required this.style,
    required this.mode,
    required this.budget,
    required this.availability,
    required this.goal,
    this.userId = '',
    this.birthdate,
    this.livesIn = '',
    this.placeId = '',
    this.locationPrivacy = LocationPrivacy.cityOnly,
    this.publicPlaceValue,
    this.statusText = '',
    this.presence = PresenceStatus.available,
    this.bio = '',
    this.gender = Profile.noAnswer,
    this.languages = const <String>[],
    this.years,
    this.education = '',
    this.grade = '',
    this.age,
    this.photoUrl,
    this.onboardingComplete = false,
    this.completeness = 0,
    this.completenessTotal = 0,
    this.missing = const <String>[],
  });

  static const String noAnswer = 'Prefer not to say';

  final String userId;
  final Role role;
  final String name;
  final List<String> subjects;
  final String style;
  final SessionMode mode;
  final int budget;
  final List<bool> availability;
  final String goal;
  final DateTime? birthdate;
  final String livesIn;
  final String placeId;
  final LocationPrivacy locationPrivacy;
  final PublicPlace? publicPlaceValue;
  final String statusText;
  final PresenceStatus presence;
  final String bio;
  final String gender;
  final List<String> languages;
  final int? years;
  final String education;
  final String grade;
  final int? age;
  final String? photoUrl;
  final bool onboardingComplete;
  final int completeness;
  final int completenessTotal;
  final List<String> missing;

  PublicPlace? get publicPlace => publicPlaceValue;
  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
  int get answeredCount => <bool>[
        subjects.isNotEmpty,
        style.isNotEmpty,
        availability.any((bool cell) => cell),
        goal.isNotEmpty,
        budget > 0,
      ].where((bool answered) => answered).length;

  factory Profile.blank(Role role) => Profile(
        role: role,
        name: '',
        subjects: const <String>[],
        style: '',
        mode: SessionMode.both,
        budget: 0,
        availability: List<bool>.filled(Week.cells, false),
        goal: '',
      );

  factory Profile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> completeness = jsonObject(json['completeness']);
    final Map<String, dynamic>? publicLocation =
        json['public_location'] == null
            ? null
            : jsonObject(json['public_location']);
    return Profile(
      userId: jsonString(json['user_id']),
      role: roleFromApi(json['role']),
      name: jsonString(json['name']),
      subjects: <String>[
        for (final dynamic subject in jsonList(json['subjects']))
          jsonString(subject),
      ],
      style: jsonString(json['style']),
      mode: sessionModeFromApi(json['mode']),
      budget: jsonInt(json['budget']),
      availability: availabilityFromJson(json['availability']),
      goal: jsonString(json['goal']),
      birthdate: jsonDateOnly(json['birthdate']),
      livesIn: jsonString(json['lives_in']),
      placeId: jsonString(json['area_id']),
      locationPrivacy: locationPrivacyFromApi(json['location_privacy']),
      publicPlaceValue:
          publicLocation == null ? null : PublicPlace.fromJson(publicLocation),
      statusText: jsonString(json['status_text']),
      presence: presenceFromApi(json['presence']),
      bio: jsonString(json['bio']),
      gender: jsonString(json['gender'], Profile.noAnswer),
      languages: <String>[
        for (final dynamic language in jsonList(json['languages']))
          jsonString(language),
      ],
      years: jsonIntOrNull(json['years']),
      education: jsonString(json['education']),
      grade: jsonString(json['grade']),
      age: jsonIntOrNull(json['age']),
      photoUrl: jsonString(json['photo_url']).isEmpty
          ? null
          : jsonString(json['photo_url']),
      onboardingComplete: jsonBool(json['onboarding_complete']),
      completeness: jsonInt(completeness['filled']),
      completenessTotal: jsonInt(completeness['total']),
      missing: <String>[
        for (final dynamic item in jsonList(completeness['missing']))
          jsonString(item),
      ],
    );
  }

  Profile copyWith({
    Role? role,
    String? name,
    List<String>? subjects,
    String? style,
    SessionMode? mode,
    int? budget,
    List<bool>? availability,
    String? goal,
    DateTime? birthdate,
    bool clearBirthdate = false,
    String? livesIn,
    String? placeId,
    bool clearPlace = false,
    LocationPrivacy? locationPrivacy,
    PublicPlace? publicPlaceValue,
    bool clearPublicPlace = false,
    String? statusText,
    PresenceStatus? presence,
    String? bio,
    String? gender,
    List<String>? languages,
    int? years,
    bool clearYears = false,
    String? education,
    String? grade,
    int? age,
    String? photoUrl,
    bool clearPhoto = false,
    bool? onboardingComplete,
    int? completeness,
    int? completenessTotal,
    List<String>? missing,
  }) =>
      Profile(
        userId: userId,
        role: role ?? this.role,
        name: name ?? this.name,
        subjects: subjects ?? this.subjects,
        style: style ?? this.style,
        mode: mode ?? this.mode,
        budget: budget ?? this.budget,
        availability: availability ?? this.availability,
        goal: goal ?? this.goal,
        birthdate: clearBirthdate ? null : (birthdate ?? this.birthdate),
        livesIn: clearPlace ? '' : (livesIn ?? this.livesIn),
        placeId: clearPlace ? '' : (placeId ?? this.placeId),
        locationPrivacy: locationPrivacy ?? this.locationPrivacy,
        publicPlaceValue: clearPublicPlace
            ? null
            : (publicPlaceValue ?? this.publicPlaceValue),
        statusText: statusText ?? this.statusText,
        presence: presence ?? this.presence,
        bio: bio ?? this.bio,
        gender: gender ?? this.gender,
        languages: languages ?? this.languages,
        years: clearYears ? null : (years ?? this.years),
        education: education ?? this.education,
        grade: grade ?? this.grade,
        age: age ?? this.age,
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        completeness: completeness ?? this.completeness,
        completenessTotal: completenessTotal ?? this.completenessTotal,
        missing: missing ?? this.missing,
      );

  /// The details a reader would look for, and whether this profile has them.
  /// This is a presentation checklist, not the backend's onboarding rule: the
  /// five ranking answers are checked separately by [onboardingComplete].
  List<(String, bool)> profileGaps({required bool hasPicture}) {
    final bool student = role == Role.student;
    return <(String, bool)>[
      ('a picture', hasPicture),
      ('a display name', name.trim().isNotEmpty),
      ('a birthdate', birthdate != null),
      ('where you live', livesIn.trim().isNotEmpty),
      ('a status line', statusText.trim().isNotEmpty),
      ('a bio', bio.trim().isNotEmpty),
      ('your gender', gender != noAnswer),
      ('the languages you speak', languages.isNotEmpty),
      if (student) ...<(String, bool)>[
        ('your year level', grade.trim().isNotEmpty),
        ('what you need help with', subjects.isNotEmpty),
        ('a budget', budget > 0),
        ('what you are aiming at', goal.trim().isNotEmpty),
      ] else ...<(String, bool)>[
        ('the subjects you teach', subjects.isNotEmpty),
        ('your hourly rate', budget > 0),
        ('your years of experience', years != null),
        ('your education', education.trim().isNotEmpty),
      ],
    ];
  }

  Map<String, dynamic> toUpdateJson() => <String, dynamic>{
        'name': name,
        'subjects': subjects,
        'style': style,
        'mode': mode.apiValue,
        'budget': budget,
        'availability': availability,
        'goal': goal,
        'birthdate': birthdate == null ? null : dateOnly(birthdate!),
        'area_id': placeId.isEmpty ? null : placeId,
        'location_privacy': locationPrivacy.apiValue,
        'status_text': statusText,
        'presence': presence.apiValue,
        'bio': bio,
        'gender': gender,
        'languages': languages,
        'years': years,
        'education': education,
        'grade': grade,
      };
}

class Candidate {
  const Candidate({
    required this.id,
    required this.role,
    required this.name,
    required this.headline,
    required this.subjects,
    required this.styleLabel,
    required this.styleTags,
    required this.mode,
    required this.rate,
    required this.location,
    required this.rating,
    required this.reviews,
    required this.bio,
    required this.credentials,
    required this.languages,
    required this.availability,
    this.publicPlaceValue,
    this.age,
    this.statusText = '',
    this.presence = PresenceStatus.available,
    this.gender = '',
    this.years,
    this.grade = '',
    this.goal = '',
    this.photoTint,
    this.photo,
    this.photoUrl,
    this.distanceKm,
  });

  final String id;
  final Role role;
  final String name;
  final String headline;
  final List<String> subjects;
  final String styleLabel;
  final List<String> styleTags;
  final SessionMode mode;
  final int rate;
  final String location;
  final int rating;
  final int reviews;
  final String bio;
  final List<String> credentials;
  final List<String> languages;
  final List<bool> availability;
  final PublicPlace? publicPlaceValue;
  final int? age;
  final String statusText;
  final PresenceStatus presence;
  final String gender;
  final int? years;
  final String grade;
  final String goal;
  final Color? photoTint;
  final Uint8List? photo;
  final String? photoUrl;
  final double? distanceKm;

  PublicPlace? get publicPlace => publicPlaceValue;
  bool get hasReviews => reviews > 0;

  String get rateCopy => role == Role.tutor ? '\$$rate/hr' : 'up to \$$rate/hr';

  String get modeCopy => switch (mode) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Online or in person',
      };

  factory Candidate.fromPublicJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? publicLocation =
        json['public_location'] == null
            ? null
            : jsonObject(json['public_location']);
    final PublicPlace? place =
        publicLocation == null ? null : PublicPlace.fromJson(publicLocation);
    final String name = jsonString(json['name']).isNotEmpty
        ? jsonString(json['name'])
        : jsonString(json['display_name']);
    final List<String> subjects = <String>[
      for (final dynamic subject in jsonList(json['subjects']))
        jsonString(subject),
    ];
    final String statusText = jsonString(json['status_text']);
    final Role role = roleFromApi(json['role']);
    final String education = jsonString(json['education']);
    final int? years = jsonIntOrNull(json['years']);
    final String headline = statusText.isNotEmpty
        ? statusText
        : role == Role.tutor
            ? 'Tutor${place == null ? '' : ' · ${place.city}'}'
            : 'Student${place == null ? '' : ' · ${place.city}'}';
    return Candidate(
      id: jsonString(json['id']),
      role: role,
      name: name,
      headline: headline,
      subjects: subjects,
      styleLabel: jsonString(json['style']),
      styleTags: const <String>[],
      mode: sessionModeFromApi(json['mode']),
      rate: jsonInt(json['budget']),
      location: place?.label ?? 'Location hidden',
      rating: 0,
      reviews: 0,
      bio: jsonString(json['bio']),
      credentials: <String>[
        if (education.isNotEmpty) education,
        if (years != null && years > 0)
          '$years ${years == 1 ? 'year' : 'years'} of experience',
      ],
      languages: <String>[
        for (final dynamic language in jsonList(json['languages']))
          jsonString(language),
      ],
      availability: availabilityFromJson(json['availability']),
      publicPlaceValue: place,
      age: jsonIntOrNull(json['age']),
      statusText: statusText,
      presence: presenceFromApi(json['presence']),
      gender: jsonString(json['gender']),
      years: years,
      grade: jsonString(json['grade']),
      goal: jsonString(json['goal']),
      photoUrl: jsonString(json['photo_url']).isEmpty
          ? null
          : jsonString(json['photo_url']),
      distanceKm: jsonDoubleOrNull(json['distance_km']),
    );
  }

  Candidate copyWith({
    Uint8List? photo,
    bool clearPhoto = false,
    String? photoUrl,
    double? distanceKm,
  }) =>
      Candidate(
        id: id,
        role: role,
        name: name,
        headline: headline,
        subjects: subjects,
        styleLabel: styleLabel,
        styleTags: styleTags,
        mode: mode,
        rate: rate,
        location: location,
        rating: rating,
        reviews: reviews,
        bio: bio,
        credentials: credentials,
        languages: languages,
        availability: availability,
        publicPlaceValue: publicPlaceValue,
        age: age,
        statusText: statusText,
        presence: presence,
        gender: gender,
        years: years,
        grade: grade,
        goal: goal,
        photoTint: photoTint,
        photo: clearPhoto ? null : (photo ?? this.photo),
        photoUrl: photoUrl ?? this.photoUrl,
        distanceKm: distanceKm ?? this.distanceKm,
      );
}

Candidate candidateFromProfile(Profile profile, {Uint8List? photo}) =>
    Candidate(
      id: profile.userId,
      role: profile.role,
      name: profile.name,
      headline: profile.statusText.isNotEmpty
          ? profile.statusText
          : profile.role == Role.tutor
              ? 'Tutor${profile.publicPlace == null ? '' : ' · ${profile.publicPlace!.city}'}'
              : 'Student${profile.publicPlace == null ? '' : ' · ${profile.publicPlace!.city}'}',
      subjects: profile.subjects,
      styleLabel: profile.style,
      styleTags: const <String>[],
      mode: profile.mode,
      rate: profile.budget,
      location: profile.publicPlace?.label ?? 'Location hidden',
      rating: 0,
      reviews: 0,
      bio: profile.bio,
      credentials: <String>[
        if (profile.education.isNotEmpty) profile.education,
        if (profile.years != null && profile.years! > 0)
          '${profile.years} ${profile.years == 1 ? 'year' : 'years'} of experience',
      ],
      languages: profile.languages,
      availability: profile.availability,
      publicPlaceValue: profile.publicPlace,
      age: profile.age ??
          (profile.birthdate == null
              ? null
              : ageOn(profile.birthdate!, DateTime.now())),
      statusText: profile.statusText,
      presence: profile.presence,
      gender: profile.gender,
      years: profile.years,
      grade: profile.grade,
      goal: profile.goal,
      photo: photo,
      photoUrl: profile.photoUrl,
    );

class MatchResult {
  const MatchResult({
    required this.candidate,
    required this.score,
    required this.reasons,
    required this.rank,
    required this.tier,
  });

  final Candidate candidate;
  final MatchScore score;
  final List<FitNote> reasons;
  final int rank;
  final MatchTier tier;

  int get rankScore => score.total;
  double? get distanceKm => candidate.distanceKm;

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profile = jsonObject(json['profile']);
    return MatchResult(
      candidate: Candidate.fromPublicJson(profile),
      score: MatchScore.fromJson(json),
      reasons: <FitNote>[
        for (final dynamic reason in jsonList(json['reasons']))
          FitNote.fromJson(jsonObject(reason)),
      ],
      rank: jsonInt(json['rank'], 1),
      tier: matchTierFromApi(json['tier']),
    );
  }

  MatchResult copyWith({Candidate? candidate}) => MatchResult(
        candidate: candidate ?? this.candidate,
        score: score,
        reasons: reasons,
        rank: rank,
        tier: tier,
      );
}

class ColdStart {
  const ColdStart({
    required this.reason,
    required this.message,
    required this.missing,
  });

  final String reason;
  final String message;
  final List<String> missing;

  factory ColdStart.fromJson(Map<String, dynamic> json) => ColdStart(
        reason: jsonString(json['reason']),
        message: jsonString(json['message']),
        missing: <String>[
          for (final dynamic item in jsonList(json['missing']))
            jsonString(item),
        ],
      );
}

class MatchBatch {
  const MatchBatch({
    required this.matches,
    required this.poolSize,
    required this.rankedCount,
    this.coldStart,
  });

  final List<MatchResult> matches;
  final int poolSize;
  final int rankedCount;
  final ColdStart? coldStart;

  factory MatchBatch.fromJson(Map<String, dynamic> json) => MatchBatch(
        matches: <MatchResult>[
          for (final dynamic item in jsonList(json['matches']))
            MatchResult.fromJson(jsonObject(item)),
        ],
        poolSize: jsonInt(json['pool_size']),
        rankedCount: jsonInt(json['ranked_count']),
        coldStart: json['cold_start'] == null
            ? null
            : ColdStart.fromJson(jsonObject(json['cold_start'])),
      );
}

class MatchFilters {
  const MatchFilters({
    this.subjects = const <String>{},
    this.mode,
    this.maxRate = 80,
    this.requiredParts = const <int>{},
    this.mustBeFreeWhenIAm = false,
    this.maxDistanceKm,
    this.minScore = 0,
  });

  final Set<String> subjects;
  final SessionMode? mode;
  final int maxRate;
  final Set<int> requiredParts;
  final bool mustBeFreeWhenIAm;
  final int? maxDistanceKm;
  final int minScore;

  MatchFilters copyWith({
    Set<String>? subjects,
    SessionMode? mode,
    bool clearMode = false,
    int? maxRate,
    Set<int>? requiredParts,
    bool? mustBeFreeWhenIAm,
    int? maxDistanceKm,
    bool clearDistance = false,
    int? minScore,
  }) =>
      MatchFilters(
        subjects: subjects ?? this.subjects,
        mode: clearMode ? null : (mode ?? this.mode),
        maxRate: maxRate ?? this.maxRate,
        requiredParts: requiredParts ?? this.requiredParts,
        mustBeFreeWhenIAm: mustBeFreeWhenIAm ?? this.mustBeFreeWhenIAm,
        maxDistanceKm:
            clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
        minScore: minScore ?? this.minScore,
      );

  bool get isNarrowed =>
      subjects.isNotEmpty ||
      mode != null ||
      maxRate < 80 ||
      requiredParts.isNotEmpty ||
      maxDistanceKm != null ||
      minScore > 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Requests and conversations
// ─────────────────────────────────────────────────────────────────────────────

enum RequestStatus { pending, accepted, declined }

extension RequestStatusCopy on RequestStatus {
  String get label => switch (this) {
        RequestStatus.pending => 'Pending',
        RequestStatus.accepted => 'Accepted',
        RequestStatus.declined => 'Declined',
      };

  String get apiValue => switch (this) {
        RequestStatus.pending => 'pending',
        RequestStatus.accepted => 'accepted',
        RequestStatus.declined => 'declined',
      };

  StatusTone get tone => switch (this) {
        RequestStatus.pending => StatusTone.pending,
        RequestStatus.accepted => StatusTone.accepted,
        RequestStatus.declined => StatusTone.declined,
      };
}

RequestStatus requestStatusFromApi(Object? value) => switch (jsonString(value)) {
      'accepted' => RequestStatus.accepted,
      'declined' => RequestStatus.declined,
      _ => RequestStatus.pending,
    };

class MatchRequest {
  const MatchRequest({
    required this.id,
    required this.conversationId,
    required this.counterpartId,
    required this.counterpartName,
    required this.counterpartRole,
    required this.subject,
    required this.score,
    required this.status,
    required this.sentOn,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.reply,
    this.outgoing = true,
    this.counterpartPhotoUrl,
  });

  final String id;
  final String conversationId;
  final String counterpartId;
  final String counterpartName;
  final Role counterpartRole;
  final String subject;
  final int score;
  final RequestStatus status;
  final String sentOn;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reply;
  final bool outgoing;
  final String? counterpartPhotoUrl;

  String get reference {
    final String compact = id.replaceAll('-', '').toUpperCase();
    final String tail =
        compact.length > 6 ? compact.substring(compact.length - 6) : compact;
    return 'TM-$tail';
  }

  factory MatchRequest.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> counterpart = jsonObject(json['counterpart']);
    final DateTime created =
        jsonDate(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return MatchRequest(
      id: jsonString(json['id']),
      conversationId: jsonString(json['conversation_id']),
      counterpartId: jsonString(counterpart['id']),
      counterpartName: jsonString(counterpart['name']).isNotEmpty
          ? jsonString(counterpart['name'])
          : jsonString(counterpart['display_name']),
      counterpartRole: roleFromApi(counterpart['role']),
      subject: jsonString(json['subject']),
      score: jsonInt(json['score']),
      status: requestStatusFromApi(json['status']),
      sentOn: describeShortDate(created),
      note: jsonString(json['note']),
      createdAt: created,
      updatedAt: jsonDate(json['updated_at']) ?? created,
      reply: jsonString(json['response_note']).isEmpty
          ? null
          : jsonString(json['response_note']),
      outgoing: jsonString(json['direction']) == 'sent',
      counterpartPhotoUrl: jsonString(counterpart['photo_url']).isEmpty
          ? null
          : jsonString(counterpart['photo_url']),
    );
  }

  MatchRequest copyWith({
    RequestStatus? status,
    String? reply,
    DateTime? updatedAt,
  }) =>
      MatchRequest(
        id: id,
        conversationId: conversationId,
        counterpartId: counterpartId,
        counterpartName: counterpartName,
        counterpartRole: counterpartRole,
        subject: subject,
        score: score,
        status: status ?? this.status,
        sentOn: sentOn,
        note: note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        reply: reply ?? this.reply,
        outgoing: outgoing,
        counterpartPhotoUrl: counterpartPhotoUrl,
      );
}

enum MessageKind { text, image, voice, call, session }

MessageKind messageKindFromApi(Object? value) => switch (jsonString(value)) {
      'image' => MessageKind.image,
      'voice' => MessageKind.voice,
      'call' => MessageKind.call,
      'session' => MessageKind.session,
      _ => MessageKind.text,
    };

enum SessionState { proposed, accepted, declined }

SessionState sessionStateFromApi(Object? value) => switch (jsonString(value)) {
      'accepted' => SessionState.accepted,
      'declined' => SessionState.declined,
      _ => SessionState.proposed,
    };

extension SessionStateCopy on SessionState {
  String get label => switch (this) {
        SessionState.proposed => 'Proposed',
        SessionState.accepted => 'Accepted',
        SessionState.declined => 'Declined',
      };

  StatusTone get tone => switch (this) {
        SessionState.proposed => StatusTone.pending,
        SessionState.accepted => StatusTone.accepted,
        SessionState.declined => StatusTone.declined,
      };
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromMe,
    required this.sentAt,
    this.id,
    this.kind = MessageKind.text,
    this.image,
    this.seconds = 0,
    this.sessionWhen = '',
    this.sessionState = SessionState.proposed,
    this.sequence = 0,
    this.readByRecipient = false,
    this.mediaUrl,
    this.mediaContentType,
    this.callKind,
    this.callConnected,
    this.callDurationSeconds = 0,
    this.createdAt,
  });

  final String? id;
  final String text;
  final bool fromMe;
  final String sentAt;
  final MessageKind kind;
  final Uint8List? image;
  final int seconds;
  final String sessionWhen;
  final SessionState sessionState;
  final int sequence;
  final bool readByRecipient;
  final String? mediaUrl;
  final String? mediaContentType;
  final String? callKind;
  final bool? callConnected;
  final int callDurationSeconds;
  final DateTime? createdAt;

  ChatMessage copyWith({
    SessionState? sessionState,
    Uint8List? image,
    bool clearImage = false,
    bool? readByRecipient,
    int? sequence,
  }) =>
      ChatMessage(
        id: id,
        text: text,
        fromMe: fromMe,
        sentAt: sentAt,
        kind: kind,
        image: clearImage ? null : (image ?? this.image),
        seconds: seconds,
        sessionWhen: sessionWhen,
        sessionState: sessionState ?? this.sessionState,
        sequence: sequence ?? this.sequence,
        readByRecipient: readByRecipient ?? this.readByRecipient,
        mediaUrl: mediaUrl,
        mediaContentType: mediaContentType,
        callKind: callKind,
        callConnected: callConnected,
        callDurationSeconds: callDurationSeconds,
        createdAt: createdAt,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final MessageKind kind = messageKindFromApi(json['kind']);
    final DateTime? created = jsonDate(json['created_at']);
    final int seconds = jsonInt(json['voice_seconds']);
    final DateTime? sessionAt = jsonDate(json['session_at']);
    final String rawText = jsonString(json['text']);
    final bool? connected = json['call_connected'] == null
        ? null
        : jsonBool(json['call_connected']);
    final int callSeconds = jsonInt(json['call_duration_seconds']);
    final String callKind = jsonString(json['call_kind']);
    return ChatMessage(
      id: jsonString(json['id']),
      text: rawText.isNotEmpty ? rawText : _messageText(
        kind: kind,
        seconds: seconds,
        sessionAt: sessionAt,
        callKind: callKind,
        connected: connected,
        callSeconds: callSeconds,
      ),
      fromMe: jsonBool(json['from_me']),
      sentAt: created == null ? '' : clockLabel(created),
      kind: kind,
      seconds: seconds,
      sessionWhen: sessionAt == null ? '' : describeSession(sessionAt),
      sessionState: sessionStateFromApi(json['session_state']),
      sequence: jsonInt(json['sequence']),
      readByRecipient: jsonBool(json['read_by_recipient']),
      mediaUrl: jsonString(json['media_url']).isEmpty
          ? null
          : jsonString(json['media_url']),
      mediaContentType: jsonString(json['media_content_type']).isEmpty
          ? null
          : jsonString(json['media_content_type']),
      callKind: callKind.isEmpty ? null : callKind,
      callConnected: connected,
      callDurationSeconds: callSeconds,
      createdAt: created,
    );
  }

  static String _messageText({
    required MessageKind kind,
    required int seconds,
    required DateTime? sessionAt,
    required String callKind,
    required bool? connected,
    required int callSeconds,
  }) =>
      switch (kind) {
        MessageKind.image => 'Photo',
        MessageKind.voice => 'Voice note · ${voiceLabel(seconds)}',
        MessageKind.session => sessionAt == null
            ? 'Session proposed'
            : 'Session proposed · ${describeSession(sessionAt)}',
        MessageKind.call => connected == false
            ? 'Missed ${callKind.isEmpty ? 'call' : '$callKind call'}'
            : '${callKind.isEmpty ? 'Call' : '${callKind[0].toUpperCase()}${callKind.substring(1)} call'} · ${elapsedClock(Duration(seconds: callSeconds))}',
        MessageKind.text => '',
      };
}

class MessagePageData {
  const MessagePageData({
    required this.messages,
    required this.latestSequence,
    required this.readThroughSequence,
    required this.unreadCount,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final int latestSequence;
  final int readThroughSequence;
  final int unreadCount;
  final bool hasMore;

  factory MessagePageData.fromJson(Map<String, dynamic> json) =>
      MessagePageData(
        messages: <ChatMessage>[
          for (final dynamic item in jsonList(json['messages']))
            ChatMessage.fromJson(jsonObject(item)),
        ],
        latestSequence: jsonInt(json['latest_sequence']),
        readThroughSequence: jsonInt(json['read_through_sequence']),
        unreadCount: jsonInt(json['unread_count']),
        hasMore: jsonBool(json['has_more']),
      );
}

class ReadStateData {
  const ReadStateData({
    required this.readThroughSequence,
    required this.latestMessageSequence,
    required this.unreadCount,
  });

  final int readThroughSequence;
  final int latestMessageSequence;
  final int unreadCount;

  factory ReadStateData.fromJson(Map<String, dynamic> json) => ReadStateData(
        readThroughSequence: jsonInt(json['read_through_sequence']),
        latestMessageSequence: jsonInt(json['latest_message_sequence']),
        unreadCount: jsonInt(json['unread_count']),
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.counterpartId,
    required this.counterpartName,
    required this.counterpartRole,
    required this.subject,
    required this.status,
    required this.requestedByMe,
    this.messages = const <ChatMessage>[],
    this.preview,
    this.score = 0,
    this.unreadCount = 0,
    this.lastEventSequence = 0,
    this.readThroughSequence = 0,
    this.latestMessageSequence = 0,
    this.requestNote = '',
    this.responseNote,
    this.counterpartPhotoUrl,
    this.updatedAt,
  });

  final String id;
  final String counterpartId;
  final String counterpartName;
  final Role counterpartRole;
  final String subject;
  final RequestStatus status;
  final bool requestedByMe;
  final List<ChatMessage> messages;
  final ChatMessage? preview;
  final int score;
  final int unreadCount;
  final int lastEventSequence;
  final int readThroughSequence;
  final int latestMessageSequence;
  final String requestNote;
  final String? responseNote;
  final String? counterpartPhotoUrl;
  final DateTime? updatedAt;

  ChatMessage? get lastMessage =>
      messages.isNotEmpty ? messages.last : preview;

  ChatMessage? get lastMine {
    for (int i = messages.length - 1; i >= 0; i--) {
      final ChatMessage message = messages[i];
      if (message.fromMe && message.kind != MessageKind.call) return message;
    }
    return null;
  }

  bool seen(ChatMessage message) => message.fromMe && message.readByRecipient;

  factory Conversation.fromSummaryJson(Map<String, dynamic> json) {
    final Map<String, dynamic> counterpart = jsonObject(json['counterpart']);
    final Map<String, dynamic>? last = json['last_message'] == null
        ? null
        : jsonObject(json['last_message']);
    final MessageKind kind =
        last == null ? MessageKind.text : messageKindFromApi(last['kind']);
    final DateTime? created = last == null ? null : jsonDate(last['created_at']);
    return Conversation(
      id: jsonString(json['id']),
      counterpartId: jsonString(counterpart['id']),
      counterpartName: jsonString(counterpart['name']).isNotEmpty
          ? jsonString(counterpart['name'])
          : jsonString(counterpart['display_name']),
      counterpartRole: roleFromApi(counterpart['role']),
      subject: jsonString(json['subject']),
      status: requestStatusFromApi(json['status']),
      requestedByMe: jsonBool(json['requested_by_me']),
      preview: last == null
          ? null
          : ChatMessage(
              id: jsonString(last['id']),
              text: jsonString(last['text']).isNotEmpty
                  ? jsonString(last['text'])
                  : ChatMessage._messageText(
                      kind: kind,
                      seconds: 0,
                      sessionAt: null,
                      callKind: '',
                      connected: null,
                      callSeconds: 0,
                    ),
              fromMe: jsonBool(last['from_me']),
              sentAt: created == null ? '' : clockLabel(created),
              kind: kind,
              sequence: jsonInt(last['sequence']),
              createdAt: created,
            ),
      score: jsonInt(json['score']),
      unreadCount: jsonInt(json['unread_count']),
      lastEventSequence: jsonInt(json['last_event_sequence']),
      counterpartPhotoUrl: jsonString(counterpart['photo_url']).isEmpty
          ? null
          : jsonString(counterpart['photo_url']),
      updatedAt: jsonDate(json['updated_at']),
    );
  }

  factory Conversation.fromDetailJson(Map<String, dynamic> json) {
    final Conversation summary = Conversation.fromSummaryJson(json);
    return summary.copyWith(
      requestNote: jsonString(json['request_note']),
      responseNote: jsonString(json['response_note']).isEmpty
          ? null
          : jsonString(json['response_note']),
      readThroughSequence: jsonInt(json['read_through_sequence']),
      latestMessageSequence: jsonInt(json['latest_message_sequence']),
    );
  }

  Conversation copyWith({
    RequestStatus? status,
    List<ChatMessage>? messages,
    ChatMessage? preview,
    int? unreadCount,
    int? lastEventSequence,
    int? readThroughSequence,
    int? latestMessageSequence,
    String? requestNote,
    String? responseNote,
    bool clearResponseNote = false,
  }) =>
      Conversation(
        id: id,
        counterpartId: counterpartId,
        counterpartName: counterpartName,
        counterpartRole: counterpartRole,
        subject: subject,
        status: status ?? this.status,
        requestedByMe: requestedByMe,
        messages: messages ?? this.messages,
        preview: preview ?? this.preview,
        score: score,
        unreadCount: unreadCount ?? this.unreadCount,
        lastEventSequence: lastEventSequence ?? this.lastEventSequence,
        readThroughSequence: readThroughSequence ?? this.readThroughSequence,
        latestMessageSequence:
            latestMessageSequence ?? this.latestMessageSequence,
        requestNote: requestNote ?? this.requestNote,
        responseNote:
            clearResponseNote ? null : (responseNote ?? this.responseNote),
        counterpartPhotoUrl: counterpartPhotoUrl,
        updatedAt: updatedAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Accounts and formatting
// ─────────────────────────────────────────────────────────────────────────────

/// One public security question. The catalogue contains only the id and text;
/// answers never leave the client except as a hash input on the server.
class SecurityQuestion {
  const SecurityQuestion({required this.id, required this.text});

  final String id;
  final String text;

  factory SecurityQuestion.fromJson(Map<String, dynamic> json) =>
      SecurityQuestion(
        id: jsonString(json['id']),
        text: jsonString(json['text']),
      );
}

/// A question/answer pair collected during registration. The answer is sent
/// once, hashed by the backend, and never requested back.
class SecurityAnswerInput {
  const SecurityAnswerInput({
    required this.questionId,
    required this.answer,
  });

  final String questionId;
  final String answer;
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.role,
    required this.displayName,
    required this.onboardingComplete,
    this.createdAt,
  });

  final String id;
  final String email;
  final Role role;
  final String displayName;
  final bool onboardingComplete;
  final DateTime? createdAt;

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: jsonString(json['id']),
        email: jsonString(json['email']),
        role: roleFromApi(json['role']),
        displayName: jsonString(json['display_name']),
        onboardingComplete: jsonBool(json['onboarding_complete']),
        createdAt: jsonDate(json['created_at']),
      );
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final UserAccount user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: jsonString(json['access_token']),
        refreshToken: jsonString(json['refresh_token']),
        user: UserAccount.fromJson(jsonObject(json['user'])),
      );
}

class SubjectOption {
  const SubjectOption({required this.id, required this.name});

  final String id;
  final String name;

  factory SubjectOption.fromJson(Map<String, dynamic> json) => SubjectOption(
        id: jsonString(json['id']),
        name: jsonString(json['name']),
      );
}

class AreaCatalogue {
  const AreaCatalogue({
    required this.regions,
    required this.cities,
    required this.places,
  });

  final List<String> regions;
  final List<City> cities;
  final List<Place> places;
}

String clockLabel(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String elapsedClock(Duration duration) {
  final int total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  return '${(total ~/ 60).toString().padLeft(2, '0')}:'
      '${(total % 60).toString().padLeft(2, '0')}';
}

String voiceLabel(int seconds) {
  final int total = seconds < 0 ? 0 : seconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

const List<String> _weekdayShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _monthShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String describeSession(DateTime at) =>
    '${_weekdayShort[at.weekday - 1]} ${at.day} '
    '${_monthShort[at.month - 1]} · ${clockLabel(at)}';
