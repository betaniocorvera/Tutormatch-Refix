// ═════════════════════════════════════════════════════════════════════════════
// SAMPLE DATA — NOT A BACKEND.
//
// Everything in this file is hard-coded so the interface can be built and
// judged before any service exists. Nothing here is fetched, stored or saved.
//
// HOW TO REPLACE IT WITH THE REAL THING
//   1. `MatchDimension` and `MatchScore` mirror the shape a KNN response should
//      return: a total 0-100 plus the per-dimension contribution that produced
//      it. Keep that shape and the detail screen keeps working.
//   2. `Candidate` is one row of the recommendation pool, for either role.
//      `fitSubjects / fitStyle / fitFormat / fitBudget` are the authored
//      agreement scores per dimension, each already capped at
//      `MatchDimension.max`. A real service sends these computed.
//   3. `MatchDimension.time` is the ONE dimension computed live in this demo,
//      from the actual overlap between the viewer's availability and the
//      candidate's. That is why the mini week grid and the score agree, and why
//      changing your availability in onboarding visibly re-ranks the list.
//      With a real service this arrives precomputed with the rest.
//   4. `applyFilters` and `MatchOutcome` are UI-side narrowing of an
//      already-ranked list. They are not the recommender. The recommender
//      ranks; the filters here only let a person interrogate the ranking.
//   5. `sampleRequests` is a static inbox. Wire it to POST /requests.
//
// The authored fit scores are calibrated against `demoStudentProfile` and
// `demoTutorProfile` at the bottom of this file, which is what you see if you
// skip onboarding. Walk the onboarding flow and the time dimension moves.
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:tutormatch/data/sample_photo.dart';
import 'package:tutormatch/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Weekly availability
// ─────────────────────────────────────────────────────────────────────────────

/// One half of the week's timetable: seven days by three parts of the day.
/// Stored as a flat 21-cell grid in day-major order, which is exactly the
/// shape the mini week grid draws.
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

/// Reads `['Mon-Eve', 'Sat-Morn']` into the 21-cell grid.
///
/// Written as readable strings in the data below rather than 21 booleans,
/// because a wrong boolean is invisible in review and a wrong string is not.
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

/// The hours both people are free. The whole point of the product.
List<bool> overlapOf(List<bool> a, List<bool> b) =>
    List<bool>.generate(Week.cells, (int i) => a[i] && b[i]);

/// Human sentence for the overlap, e.g. `Monday and Thursday evenings`.
/// Returns null when there is no overlap, so callers must handle that case
/// rather than printing "0 slots".
String? describeOverlap(List<bool> grid) {
  if (!grid.contains(true)) return null;
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
// The five dimensions the recommender compares
// ─────────────────────────────────────────────────────────────────────────────

/// Weights and plain-language explanations live together on purpose: the
/// landing page promises the same mechanism the detail screen scores against.
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

  /// What happens if you relax this one. Written per dimension, because
  /// "adjust your filters" is not advice.
  final String widening;

  String get weightCopy => '$max of 100';
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// How the recommender reached a score. Kept as five numbers rather than one,
/// so the detail screen can show its work.
class MatchScore {
  const MatchScore({
    required this.byDimension,
    required this.overlap,
  });

  final Map<MatchDimension, int> byDimension;
  final List<bool> overlap;

  int get total => byDimension.values.fold(0, (int a, int b) => a + b);
  int get overlapSlots => overlap.where((bool c) => c).length;
}

enum MatchTier { strong, good, possible, weak }

/// Thresholds are product copy, not maths: they decide which word a person
/// reads, so they live next to the words.
MatchTier tierFor(int score) => switch (score) {
      >= 80 => MatchTier.strong,
      >= 60 => MatchTier.good,
      >= 40 => MatchTier.possible,
      _ => MatchTier.weak,
    };

extension MatchTierCopy on MatchTier {
  String get label => switch (this) {
        MatchTier.strong => 'Strong match',
        MatchTier.good => 'Good match',
        MatchTier.possible => 'Worth a look',
        MatchTier.weak => 'Long shot',
      };

  /// What the word means, in words a person can act on.
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

/// One plain-language reason, attached to the dimension that produced it.
class FitNote {
  const FitNote(this.dimension, this.signal, this.detail, {this.label});

  /// The concrete fact, set in ink at the start of the line.
  final String signal;

  /// One clause on why it counts. Set quieter than the signal.
  final String detail;

  final MatchDimension dimension;

  /// An override for reasons that are not one of the five scored dimensions.
  /// "Nearby" is a fact about the pair, not a sixth score, so it borrows the
  /// type without pretending to add weight to the ranking.
  final String? label;

  String get dimensionLabel => label ?? dimension.label;
}

/// One row of the recommendation pool — a tutor when the viewer is a student,
/// a student when the viewer is a tutor. Same shape either way.
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
    required this.fitSubjects,
    required this.fitStyle,
    required this.fitFormat,
    required this.fitBudget,
    required this.notes,
    this.livesIn = '',
    this.placeId = '',
    // The least public setting is the default for anyone whose privacy was
    // never chosen. Sample rows set their own value explicitly.
    this.locationPrivacy = LocationPrivacy.cityOnly,
    this.birthdate,
    this.statusText = '',
    this.presence = PresenceStatus.available,
    this.gender = '',
    this.years,
    this.grade = '',
    this.goal = '',
    this.photoTint,
  });

  final String id;
  final Role role;
  final String name;

  /// One line under the name. Specific, never a slogan.
  final String headline;
  final List<String> subjects;
  final String styleLabel;
  final List<String> styleTags;
  final SessionMode mode;

  /// Hourly rate for a tutor; the student's own ceiling when role is student.
  final int rate;
  final String location;
  final double rating;
  final int reviews;
  final String bio;
  final List<String> credentials;
  final List<String> languages;
  final List<bool> availability;

  /// The profile details. [location] says where a lesson can happen ("Online,
  /// from Leeds"); [livesIn] is the place itself, as they would say it.
  ///
  /// [placeId] points into [samplePlaces] and is the only coordinate source.
  /// [locationPrivacy] decides how much of it is public; see [publicPlace].
  final String livesIn;
  final String placeId;
  final LocationPrivacy locationPrivacy;
  final DateTime? birthdate;

  /// The area as other people are allowed to read it, or null when hidden or
  /// unset. Use this rather than [livesIn] on any public or match surface.
  PublicPlace? get publicPlace => publicPlaceFor(placeId, locationPrivacy);

  /// One short line, e.g. "Open for sessions". [presence] is the indicator.
  final String statusText;
  final PresenceStatus presence;
  final String gender;

  /// Tutoring experience in whole years, and the school year for a student.
  final int? years;
  final String grade;

  /// What the viewer is aiming at. Only ever filled on the viewer's own row.
  final String goal;

  /// A flat dye standing in for a picture — the two or three sample people who
  /// "have one". There are no photographs in this product, so the stand-in is
  /// honest: a colour, not a stranger's face. Null means initials.
  final Color? photoTint;

  // Authored agreement scores, each already capped at MatchDimension.max.
  final int fitSubjects;
  final int fitStyle;
  final int fitFormat;
  final int fitBudget;

  final List<FitNote> notes;

  String get rateCopy => role == Role.tutor ? '\$$rate/hr' : 'up to \$$rate/hr';

  String get modeCopy => switch (mode) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Online or in person',
      };
}

enum SessionMode { online, inPerson, both }

extension SessionModeCopy on SessionMode {
  String get label => switch (this) {
        SessionMode.online => 'Online',
        SessionMode.inPerson => 'In person',
        SessionMode.both => 'Either is fine',
      };

  /// What to say when the two sides disagree.
  String get counterLabel => switch (this) {
        SessionMode.online => 'in person',
        SessionMode.inPerson => 'online',
        SessionMode.both => 'either way',
      };

  bool accepts(SessionMode other) =>
      this == other || this == SessionMode.both || other == SessionMode.both;
}

/// Whether somebody is around right now, alongside the line they wrote about
/// themselves. Kept as three states rather than a free colour: "around", "in
/// the middle of something" and "not here" are all a person ever needs to read.
enum PresenceStatus { available, busy, away }

extension PresenceStatusCopy on PresenceStatus {
  String get label => switch (this) {
        PresenceStatus.available => 'Available',
        PresenceStatus.busy => 'Busy',
        PresenceStatus.away => 'Away',
      };

  StatusTone get tone => switch (this) {
        PresenceStatus.available => StatusTone.accepted,
        PresenceStatus.busy => StatusTone.pending,
        PresenceStatus.away => StatusTone.neutral,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Places
//
// A deliberately small gazetteer, not a geocoder. Every place carries an
// approximate neighbourhood centre; no street, building or house number exists
// anywhere in this model, because none is ever needed or shown.
//
// The city centre is what "Show city only" resolves to. It is a separate point
// from the neighbourhood, so choosing that setting genuinely widens the circle
// rather than merely hiding the label.
// ─────────────────────────────────────────────────────────────────────────────

/// What a person allows other people to see about where they live.
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

  /// The sentence used by the privacy control. Written out rather than
  /// abbreviated, because this is the one setting where ambiguity is expensive.
  final String label;
  final String explanation;
}

/// A city or municipality in the demo catalogue, with the centre used when
/// somebody chooses "Show city only".
class City {
  const City({
    required this.region,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String region;
  final String name;
  final double latitude;
  final double longitude;

  String get id => '$region|$name';
}

/// One neighbourhood inside a [City] — the lowest, most precise level the
/// public map ever shows.
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

  /// "Highbury, London" — the reading used when the area is visible.
  String get label => '$name, ${city.name}';
}

/// The public reading of somebody's location, after their privacy setting has
/// been applied. A person whose setting is [LocationPrivacy.hidden] resolves to
/// null rather than to an object with a hidden flag, so every caller has to
/// decide what to do about the absence instead of accidentally printing it.
class PublicPlace {
  const PublicPlace({
    required this.label,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.cityOnly,
  });

  /// What other people may read: the city, or the neighbourhood and city.
  final String label;
  final String city;

  /// The centre of the circle to draw. The city centre when [cityOnly], the
  /// neighbourhood centroid otherwise. Never a home address.
  final double latitude;
  final double longitude;
  final bool cityOnly;
}

/// The built-in catalogue. At least twelve areas, spread across the places the
/// sample people actually live in. No network call, no geocoder, no API key.
const City cityLondon = City(
  region: 'Greater London',
  name: 'London',
  latitude: 51.5072,
  longitude: -0.1276,
);
const City cityManchester = City(
  region: 'North West England',
  name: 'Manchester',
  latitude: 53.4808,
  longitude: -2.2426,
);
const City cityCardiff = City(
  region: 'Wales',
  name: 'Cardiff',
  latitude: 51.4816,
  longitude: -3.1791,
);
const City cityLeeds = City(
  region: 'Yorkshire and the Humber',
  name: 'Leeds',
  latitude: 53.8008,
  longitude: -1.5491,
);
const City cityEdinburgh = City(
  region: 'Scotland',
  name: 'Edinburgh',
  latitude: 55.9533,
  longitude: -3.1883,
);
const City cityMelbourne = City(
  region: 'Victoria',
  name: 'Melbourne',
  latitude: -37.8136,
  longitude: 144.9631,
);
const City cityPorto = City(
  region: 'Porto',
  name: 'Porto',
  latitude: 41.1579,
  longitude: -8.6291,
);
const City cityParis = City(
  region: 'Île-de-France',
  name: 'Paris',
  latitude: 48.8566,
  longitude: 2.3522,
);
const City cityBristol = City(
  region: 'South West England',
  name: 'Bristol',
  latitude: 51.4545,
  longitude: -2.5879,
);
const City cityBirmingham = City(
  region: 'West Midlands',
  name: 'Birmingham',
  latitude: 52.4862,
  longitude: -1.8904,
);
const City citySheffield = City(
  region: 'South Yorkshire',
  name: 'Sheffield',
  latitude: 53.3811,
  longitude: -1.4701,
);
const City cityBath = City(
  region: 'Somerset',
  name: 'Bath',
  latitude: 51.3811,
  longitude: -2.3590,
);
const City cityLyon = City(
  region: 'Auvergne-Rhône-Alpes',
  name: 'Lyon',
  latitude: 45.7640,
  longitude: 4.8357,
);
const City cityOxford = City(
  region: 'Oxfordshire',
  name: 'Oxford',
  latitude: 51.7520,
  longitude: -1.2577,
);
const City cityCairo = City(
  region: 'Cairo Governorate',
  name: 'Cairo',
  latitude: 30.0444,
  longitude: 31.2357,
);
const City cityNottingham = City(
  region: 'Nottinghamshire',
  name: 'Nottingham',
  latitude: 52.9548,
  longitude: -1.1581,
);
const City cityRotterdam = City(
  region: 'South Holland',
  name: 'Rotterdam',
  latitude: 51.9244,
  longitude: 4.4777,
);
const City cityBrighton = City(
  region: 'East Sussex',
  name: 'Brighton',
  latitude: 50.8225,
  longitude: -0.1372,
);

const List<City> sampleCities = <City>[
  cityLondon,
  cityManchester,
  cityCardiff,
  cityLeeds,
  cityEdinburgh,
  cityMelbourne,
  cityPorto,
  cityParis,
  cityBristol,
  cityBirmingham,
  citySheffield,
  cityBath,
  cityLyon,
  cityOxford,
  cityCairo,
  cityNottingham,
  cityRotterdam,
  cityBrighton,
];

const List<Place> samplePlaces = <Place>[
  Place(
    id: 'london-highbury',
    city: cityLondon,
    name: 'Highbury',
    latitude: 51.5520,
    longitude: -0.0970,
  ),
  Place(
    id: 'london-camden',
    city: cityLondon,
    name: 'Camden',
    latitude: 51.5390,
    longitude: -0.1426,
  ),
  Place(
    id: 'london-hackney',
    city: cityLondon,
    name: 'Hackney',
    latitude: 51.5450,
    longitude: -0.0553,
  ),
  Place(
    id: 'london-islington',
    city: cityLondon,
    name: 'Islington',
    latitude: 51.5416,
    longitude: -0.1022,
  ),
  Place(
    id: 'manchester-northern-quarter',
    city: cityManchester,
    name: 'Northern Quarter',
    latitude: 53.4837,
    longitude: -2.2346,
  ),
  Place(
    id: 'manchester-didsbury',
    city: cityManchester,
    name: 'Didsbury',
    latitude: 53.4165,
    longitude: -2.2310,
  ),
  Place(
    id: 'cardiff-riverside',
    city: cityCardiff,
    name: 'Riverside',
    latitude: 51.4860,
    longitude: -3.2000,
  ),
  Place(
    id: 'leeds-hyde-park',
    city: cityLeeds,
    name: 'Hyde Park',
    latitude: 53.8080,
    longitude: -1.5660,
  ),
  Place(
    id: 'edinburgh-leith',
    city: cityEdinburgh,
    name: 'Leith',
    latitude: 55.9800,
    longitude: -3.1700,
  ),
  Place(
    id: 'melbourne-fitzroy',
    city: cityMelbourne,
    name: 'Fitzroy',
    latitude: -37.7983,
    longitude: 144.9781,
  ),
  Place(
    id: 'porto-cedofeita',
    city: cityPorto,
    name: 'Cedofeita',
    latitude: 41.1550,
    longitude: -8.6200,
  ),
  Place(
    id: 'paris-montmartre',
    city: cityParis,
    name: 'Montmartre',
    latitude: 48.8867,
    longitude: 2.3431,
  ),
  Place(
    id: 'bristol-clifton',
    city: cityBristol,
    name: 'Clifton',
    latitude: 51.4620,
    longitude: -2.6200,
  ),
  Place(
    id: 'birmingham-moseley',
    city: cityBirmingham,
    name: 'Moseley',
    latitude: 52.4460,
    longitude: -1.8880,
  ),
  Place(
    id: 'sheffield-crookes',
    city: citySheffield,
    name: 'Crookes',
    latitude: 53.3840,
    longitude: -1.5080,
  ),
  Place(
    id: 'bath-widcombe',
    city: cityBath,
    name: 'Widcombe',
    latitude: 51.3750,
    longitude: -2.3560,
  ),
  Place(
    id: 'lyon-croix-rousse',
    city: cityLyon,
    name: 'Croix-Rousse',
    latitude: 45.7740,
    longitude: 4.8320,
  ),
  Place(
    id: 'oxford-jericho',
    city: cityOxford,
    name: 'Jericho',
    latitude: 51.7620,
    longitude: -1.2670,
  ),
  Place(
    id: 'cairo-zamalek',
    city: cityCairo,
    name: 'Zamalek',
    latitude: 30.0600,
    longitude: 31.2190,
  ),
  Place(
    id: 'nottingham-hockley',
    city: cityNottingham,
    name: 'Hockley',
    latitude: 52.9520,
    longitude: -1.1460,
  ),
  Place(
    id: 'rotterdam-kralingen',
    city: cityRotterdam,
    name: 'Kralingen',
    latitude: 51.9240,
    longitude: 4.5100,
  ),
  Place(
    id: 'brighton-kemptown',
    city: cityBrighton,
    name: 'Kemptown',
    latitude: 50.8190,
    longitude: -0.1250,
  ),
];

Place? placeById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final Place place in samplePlaces) {
    if (place.id == id) return place;
  }
  return null;
}

/// The one place where privacy turns a stored area into a public one. Hidden
/// resolves to null; city-only resolves to the city centre; area resolves to the
/// neighbourhood centre. Every map, label and distance reads through here.
PublicPlace? publicPlaceFor(String? placeId, LocationPrivacy privacy) {
  if (privacy == LocationPrivacy.hidden) return null;
  final Place? place = placeById(placeId);
  if (place == null) return null;
  if (privacy == LocationPrivacy.cityOnly) {
    return PublicPlace(
      label: place.city.name,
      city: place.city.name,
      latitude: place.city.latitude,
      longitude: place.city.longitude,
      cityOnly: true,
    );
  }
  return PublicPlace(
    label: place.label,
    city: place.city.name,
    latitude: place.latitude,
    longitude: place.longitude,
    cityOnly: false,
  );
}

/// Great-circle distance in kilometres. The coordinates are approximate area
/// centres, so the result is only ever shown rounded to a whole kilometre.
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

/// The distance to render, or null when either side hides its location or has
/// not chosen one. Null means "do not show a distance", never "zero".
double? distanceBetween(PublicPlace? from, PublicPlace? to) {
  if (from == null || to == null) return null;
  return haversineKm(from.latitude, from.longitude, to.latitude, to.longitude);
}

/// "about 3 km away". The one wording used on cards and maps.
String describeDistance(double km) =>
    km < 1 ? 'less than 1 km away' : 'about ${km.round()} km away';

/// How close counts as nearby for the "why this match" reason.
const int nearbyDistanceKm = 5;

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

/// `14 March 2009`. Written out rather than numbered: a birthdate is read once
/// and freehand, and `14/03/2009` is read twice and still guessed at.
String describeDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

/// Whole years on [on]. A birthday is the fact; an age is only ever a reading
/// of it, so it is computed rather than stored — and it stays right as the
/// sample data ages.
int ageOn(DateTime birthdate, DateTime on) {
  final int years = on.year - birthdate.year;
  final bool hadBirthday = on.month > birthdate.month ||
      (on.month == birthdate.month && on.day >= birthdate.day);
  return hadBirthday ? years : years - 1;
}

/// The viewer's own answers. In memory only, gone on reload. Named `Profile`
/// and not `User` because there are no users here.
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
    this.birthdate,
    this.livesIn = '',
    this.placeId = '',
    this.locationPrivacy = LocationPrivacy.cityOnly,
    this.statusText = '',
    this.presence = PresenceStatus.available,
    this.bio = '',
    this.gender = Profile.noAnswer,
    this.languages = const <String>[],
    this.years,
    this.education = '',
    this.grade = '',
  });

  /// The answer that adds no fact. A question answered "prefer not to say" is
  /// answered, not filled — which is why the completeness count skips it.
  static const String noAnswer = 'Prefer not to say';

  final Role role;
  final String name;
  final List<String> subjects;
  final String style;
  final SessionMode mode;
  final int budget;
  final List<bool> availability;
  final String goal;

  final DateTime? birthdate;

  /// Where they live, in their own words. City, province — whatever they would
  /// write on an envelope. Kept alongside the structured place so the
  /// completeness meter and older copy keep working.
  final String livesIn;

  /// The structured, editable half of the location: a [samplePlaces] id and the
  /// privacy setting that governs what other people see.
  final String placeId;
  final LocationPrivacy locationPrivacy;

  /// The viewer's own area, as they have chosen to show it elsewhere.
  PublicPlace? get publicPlace => publicPlaceFor(placeId, locationPrivacy);

  /// One short line, e.g. "Open for sessions". [presence] says whether now is
  /// a good time; this says what they are up to.
  final String statusText;
  final PresenceStatus presence;
  final String bio;
  final String gender;
  final List<String> languages;

  // Tutor only. `subjects`, `mode` and `budget` above are shared: a tutor's
  // rate is the same number a student's ceiling is, and the ranking reads it
  // the same way.
  final int? years;
  final String education;

  // Student only.
  final String grade;

  /// The facts a finished profile has, in the order the edit form asks for
  /// them, each with whether it is filled. The picture is kept in [AppState]
  /// beside the profile rather than on it, so whether one is set is passed in.
  /// A gap is written as the thing that is missing — "a bio", not "bio".
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
    String? livesIn,
    String? placeId,
    LocationPrivacy? locationPrivacy,
    String? statusText,
    PresenceStatus? presence,
    String? bio,
    String? gender,
    List<String>? languages,
    int? years,
    bool clearYears = false,
    String? education,
    String? grade,
  }) =>
      Profile(
        role: role ?? this.role,
        name: name ?? this.name,
        subjects: subjects ?? this.subjects,
        style: style ?? this.style,
        mode: mode ?? this.mode,
        budget: budget ?? this.budget,
        availability: availability ?? this.availability,
        goal: goal ?? this.goal,
        birthdate: birthdate ?? this.birthdate,
        livesIn: livesIn ?? this.livesIn,
        placeId: placeId ?? this.placeId,
        locationPrivacy: locationPrivacy ?? this.locationPrivacy,
        statusText: statusText ?? this.statusText,
        presence: presence ?? this.presence,
        bio: bio ?? this.bio,
        gender: gender ?? this.gender,
        languages: languages ?? this.languages,
        years: clearYears ? null : (years ?? this.years),
        education: education ?? this.education,
        grade: grade ?? this.grade,
      );
}

enum RequestStatus { pending, accepted, declined }

extension RequestStatusCopy on RequestStatus {
  String get label => switch (this) {
        RequestStatus.pending => 'Pending',
        RequestStatus.accepted => 'Accepted',
        RequestStatus.declined => 'Rejected',
      };

  StatusTone get tone => switch (this) {
        RequestStatus.pending => StatusTone.pending,
        RequestStatus.accepted => StatusTone.accepted,
        RequestStatus.declined => StatusTone.declined,
      };
}

/// A request that has left your outbox or arrived in your inbox.
class MatchRequest {
  const MatchRequest({
    required this.id,
    required this.counterpartId,
    required this.counterpartName,
    required this.counterpartRole,
    required this.subject,
    required this.score,
    required this.status,
    required this.sentOn,
    required this.note,
    this.reply,
    this.outgoing = true,
  });

  final String id;
  final String counterpartId;
  final String counterpartName;
  final Role counterpartRole;
  final String subject;
  final int score;
  final RequestStatus status;
  final String sentOn;
  final String note;

  /// The other side's answer, when there is one. Never "OK".
  final String? reply;
  final bool outgoing;
}

/// What a line in a conversation is. Text is the default, so every sample
/// message written before the rich composer existed still reads as one.
enum MessageKind { text, image, voice, call, session }

/// Where a proposed session stands. Only [proposed] has two answers in it.
enum SessionState { proposed, accepted, declined }

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

/// One line in a conversation. [fromMe] is written from the side the list
/// belongs to, like [MatchRequest.outgoing]: the same exchange reads
/// differently on the two sides, and neither list is the other one flipped.
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
  });

  /// Stable only for messages this run created (and for the one sample session
  /// card that can be answered). Sample lines without ids never need to change.
  final String? id;

  /// The words. Every kind keeps a readable line here, because the inbox needs
  /// a one-line preview for a photo and a call as much as for a sentence.
  final String text;
  final bool fromMe;

  /// Wall-clock label, e.g. `18:42`. A string because the sample data is
  /// authored rather than observed, and so that the clock never drifts between
  /// a screenshot and the run that produced it.
  final String sentAt;

  final MessageKind kind;

  /// The picked picture, in memory only. Never a path, never a URL.
  final Uint8List? image;

  /// Length of a voice note. There is no audio; this is the duration the
  /// waveform pretends to play for.
  final int seconds;

  /// `Thu 22 Oct · 17:30`, already written out because the card is a document.
  final String sessionWhen;
  final SessionState sessionState;

  /// An answer is final, so the only edit a message ever needs.
  ChatMessage copyWith({SessionState? sessionState}) => ChatMessage(
        id: id,
        text: text,
        fromMe: fromMe,
        sentAt: sentAt,
        kind: kind,
        image: image,
        seconds: seconds,
        sessionWhen: sessionWhen,
        sessionState: sessionState ?? this.sessionState,
      );
}

/// The clock label a live message carries. Zero-padded, so a column of
/// timestamps lines up the way the rest of the figures in this product do.
String clockLabel(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// `02:14` — a call length, and the recording timer. Minutes are padded so the
/// running figure does not jump sideways when it crosses ten.
String elapsedClock(Duration duration) {
  final int total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  return '${(total ~/ 60).toString().padLeft(2, '0')}:'
      '${(total % 60).toString().padLeft(2, '0')}';
}

/// `0:14` — the short form printed on a voice note.
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

/// `Thu 22 Oct · 17:30` — a proposed session, the way it is written on the card.
String describeSession(DateTime at) =>
    '${_weekdayShort[at.weekday - 1]} ${at.day} '
    '${_monthShort[at.month - 1]} · ${clockLabel(at)}';

/// A request that has turned into a conversation, or is waiting to. The status
/// is the request's status, and it is the whole gate: only an accepted
/// conversation can be typed into. Pending reads as locked — either waiting for
/// the other side to answer, or holding an answer this side still owes —
/// declined as closed with the answer still on it.
///
/// One conversation per counterpart — the one-to-one case is the only case
/// this product has.
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
  });

  final String id;
  final String counterpartId;
  final String counterpartName;
  final Role counterpartRole;

  /// What the request was about. Shown under the name in the chat header and
  /// in the list, so a conversation says more than who it is with.
  final String subject;
  final RequestStatus status;

  /// Who sent the request, from the point of view of the list that holds this
  /// conversation. Either side can send one, so "pending" alone does not say
  /// whether this side is waiting or owes an answer — this does.
  final bool requestedByMe;
  final List<ChatMessage> messages;

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  /// The last line this side wrote that can carry a delivery state. A call line
  /// is an event the app recorded, not something a person sent, so it is not
  /// the message "Seen" belongs under.
  ChatMessage? get lastMine {
    for (int i = messages.length - 1; i >= 0; i--) {
      final ChatMessage m = messages[i];
      if (m.fromMe && m.kind != MessageKind.call) return m;
    }
    return null;
  }

  /// Read when the other side has written since. There is nobody at the other
  /// end of this prototype, so a reply is the whole of "they saw it".
  bool seen(ChatMessage message) {
    final int i = messages.indexOf(message);
    if (i < 0) return false;
    return messages.skip(i + 1).any((ChatMessage later) => !later.fromMe);
  }

  Conversation copyWith({RequestStatus? status, List<ChatMessage>? messages}) =>
      Conversation(
        id: id,
        counterpartId: counterpartId,
        counterpartName: counterpartName,
        counterpartRole: counterpartRole,
        subject: subject,
        status: status ?? this.status,
        requestedByMe: requestedByMe,
        messages: messages ?? this.messages,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Scoring
// ─────────────────────────────────────────────────────────────────────────────

/// The time dimension, computed from the real overlap. Five shared cells in a
/// week is treated as full marks; below that it scales linearly. One line,
/// deliberately: this is the only arithmetic in the UI and it should be
/// readable by whoever has to defend it.
int _timeFit(int overlapSlots) => (overlapSlots * 25 ~/ 5).clamp(0, MatchDimension.time.max);

MatchScore scoreOf(Candidate candidate, Profile viewer) {
  final List<bool> overlap = overlapOf(viewer.availability, candidate.availability);
  return MatchScore(
    overlap: overlap,
    byDimension: <MatchDimension, int>{
      MatchDimension.subjects: candidate.fitSubjects,
      MatchDimension.time: _timeFit(overlap.where((bool c) => c).length),
      MatchDimension.style: candidate.fitStyle,
      MatchDimension.format: candidate.fitFormat,
      MatchDimension.budget: candidate.fitBudget,
    },
  );
}

/// A ranked row: the person, the score, and the three reasons that earned it.
class MatchResult {
  final Candidate candidate;
  final MatchScore score;

  /// Distance between the two public areas, in kilometres. Null when either
  /// side hides their location, has not chosen one, or when a caller builds a
  /// result without a viewer to measure from.
  final double? distanceKm;

  const MatchResult({
    required this.candidate,
    required this.score,
    this.distanceKm,
  });

  int get rankScore => score.total;
  MatchTier get tier => tierFor(score.total);

  /// The three reasons that best explain this pairing, each rendered as a
  /// sentence. The first two are the highest-proportion scored dimensions;
  /// when the two people are within [nearbyDistanceKm], a third "Nearby" note
  /// takes the last slot. Time always competes on the same footing as the rest,
  /// so a candidate with no shared hours cannot hide behind good subjects.
  List<FitNote> get reasons {
    final List<FitNote> pool = <FitNote>[
      _timeNote(),
      ...candidate.notes,
    ];
    final Map<MatchDimension, int> fit = score.byDimension;
    pool.sort((FitNote a, FitNote b) {
      final double ra = fit[a.dimension]! / a.dimension.max;
      final double rb = fit[b.dimension]! / b.dimension.max;
      return rb.compareTo(ra);
    });
    final List<FitNote> top = pool.take(3).toList();
    final double? km = distanceKm;
    if (km != null && km <= nearbyDistanceKm) {
      // Proximity is not a scored dimension, so it cannot earn a place by
      // weight. It is added as a fact about the pair and takes the third slot,
      // leaving the two strongest scoring reasons untouched above it.
      top.insert(
        math.min(2, top.length),
        FitNote(
          MatchDimension.format,
          describeDistance(km),
          'Close enough that an in-person session would not turn into a journey.',
          label: 'Nearby',
        ),
      );
      if (top.length > 3) top.removeLast();
    }
    return List<FitNote>.unmodifiable(top);
  }

  FitNote _timeNote() {
    final String? when = describeOverlap(score.overlap);
    if (when == null) {
      return const FitNote(
        MatchDimension.time,
        'No shared hours',
        'You are never free at the same time in a normal week — the one hard blocker here.',
      );
    }
    return FitNote(
      MatchDimension.time,
      when,
      'Both of you are free then, ${score.overlapSlots} hour-blocks that line up in a normal week.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Narrowing a ranked list — the filters, and what to say when they exclude
// everyone. This is where the empty state gets its sentence.
// ─────────────────────────────────────────────────────────────────────────────

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

  /// Empty means "any subject".
  final Set<String> subjects;
  final SessionMode? mode;
  final int maxRate;

  /// Which parts of the day you insist on. Empty means "any time".
  final Set<int> requiredParts;

  /// Off by default, and that is a deliberate product decision: an untouched
  /// list shows the whole pool, ranked, including the people whose week never
  /// crosses yours. They score near the bottom, they say why, and the person
  /// reading learns what the pool is like. Hiding them by default would make
  /// the list look smaller than the pool and the ranking look like magic.
  final bool mustBeFreeWhenIAm;

  /// The outermost distance, in kilometres, that a result may be from the
  /// viewer. Null means "any distance". People with no public area (hidden, or
  /// not set) cannot pass a distance filter, because there is nothing to
  /// measure — which is exactly what hiding the area means.
  final int? maxDistanceKm;

  final double minScore;

  MatchFilters copyWith({
    Set<String>? subjects,
    SessionMode? mode,
    bool clearMode = false,
    int? maxRate,
    Set<int>? requiredParts,
    bool? mustBeFreeWhenIAm,
    int? maxDistanceKm,
    bool clearDistance = false,
    double? minScore,
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

/// Says which condition removed everyone, and what to do about it. The copy is
/// generated from the filters that actually fired, so it cannot go stale.
class EmptyExplanation {
  const EmptyExplanation({
    required this.headline,
    required this.body,
    required this.adjustLabel,
    required this.relaxed,
    required this.recovered,
  });

  final String headline;
  final String body;
  final String adjustLabel;
  final MatchFilters relaxed;

  /// How many candidates the suggested adjustment brings back.
  final int recovered;
}

class MatchOutcome {
  const MatchOutcome({required this.results, this.empty});

  final List<MatchResult> results;
  final EmptyExplanation? empty;
}

/// Narrows a ranked list. Rank order is preserved: filtering never re-sorts,
/// because the order is the recommender's opinion and the filters are yours.
MatchOutcome applyFilters(
  List<MatchResult> ranked,
  MatchFilters filters,
  Profile viewer,
) {
  final List<MatchResult> kept = ranked.where((MatchResult r) => _passes(r, filters)).toList();
  if (kept.isNotEmpty) return MatchOutcome(results: kept);
  return MatchOutcome(results: const <MatchResult>[], empty: _explain(ranked, filters, viewer));
}

bool _passes(MatchResult r, MatchFilters f) {
  final Candidate c = r.candidate;
  if (f.subjects.isNotEmpty && !f.subjects.any(c.subjects.contains)) return false;
  if (f.mode != null && !f.mode!.accepts(c.mode)) return false;
  if (f.maxRate < 80 && c.rate > f.maxRate) return false;
  if (f.requiredParts.isNotEmpty) {
    final bool free = f.requiredParts.any((int p) {
      for (int d = 0; d < Week.days.length; d++) {
        if (r.score.overlap[Week.index(d, p)]) return true;
      }
      return false;
    });
    if (!free) return false;
  }
  if (f.mustBeFreeWhenIAm && r.score.overlapSlots == 0) return false;
  if (f.maxDistanceKm != null) {
    final double? km = r.distanceKm;
    if (km == null || km > f.maxDistanceKm!) return false;
  }
  if (r.score.total < f.minScore) return false;
  return true;
}

/// Tries each condition on its own and recommends the one that costs the least
/// and returns the most. A relaxed filter is always something a person can
/// reverse in one click, which is why the suggestion carries a whole
/// [MatchFilters] back rather than a sentence about one.
EmptyExplanation _explain(
  List<MatchResult> ranked,
  MatchFilters f,
  Profile viewer,
) {
  final List<({String headline, String body, String label, MatchFilters next, int n})> options =
      <({String headline, String body, String label, MatchFilters next, int n})>[];

  int count(MatchFilters candidate) =>
      ranked.where((MatchResult r) => _passes(r, candidate)).length;

  // 1. Distance — new, and the one filter that can fail for a privacy reason
  // rather than a shortage of people. Say which of the two it is.
  if (f.maxDistanceKm != null) {
    final MatchFilters next = f.copyWith(clearDistance: true);
    final int n = count(next);
    if (n > 0) {
      final bool canMeasure =
          publicPlaceFor(viewer.placeId, viewer.locationPrivacy) != null;
      options.add((
        headline: canMeasure
            ? 'Nobody within ${f.maxDistanceKm} km.'
            : 'Distance needs a visible area on your profile.',
        body: canMeasure
            ? 'That limit removes everyone left in this list. Someone who has '
                'hidden their area cannot be measured at all, and a city-only '
                'area is measured from the city centre. Showing every distance '
                'brings back $n of the ${ranked.length} candidates.'
            : 'Your own area is hidden or not set, so the prototype has no '
                'point to measure from. Choose an area — or change your privacy '
                'setting — and the distance filter can work. Clearing it brings '
                'back $n of the ${ranked.length} candidates.',
        label: 'Show any distance',
        next: next,
        n: n,
      ));
    }
  }

  // 2. Time — the most common blocker and the one people least expect.
  if (f.mustBeFreeWhenIAm || f.requiredParts.isNotEmpty) {
    final MatchFilters next = f.copyWith(
      mustBeFreeWhenIAm: false,
      requiredParts: const <int>{},
    );
    final int n = count(next);
    if (n > 0) {
      final String? when = _partsPhrase(f.requiredParts);
      options.add((
        headline: when == null
            ? 'Nobody in this list is free when you are.'
            : 'No tutor in your results is free on your $when.',
        body:
            '$n of the ${ranked.length} candidates match you on subjects, style and budget — '
            'their week and yours just never cross${when == null ? '' : ' on a $when'}. '
            'Showing every hour they do have brings them back.',
        label: 'Show all their hours, not just mine',
        next: next,
        n: n,
      ));
    }
  }

  // 3. Budget.
  if (f.maxRate < 80) {
    final int cheapest = ranked.map((MatchResult r) => r.candidate.rate).reduce((int a, int b) => a < b ? a : b);
    if (cheapest > f.maxRate) {
      final MatchFilters next = f.copyWith(maxRate: cheapest);
      options.add((
        headline: 'Nothing at or under \$${f.maxRate} an hour.',
        body: 'The lowest rate in your results is \$$cheapest, a \$${cheapest - f.maxRate} gap. '
            'Raising your ceiling by that much shows ${count(next)} of the ${ranked.length}, '
            'and the top of that list still scores '
            '${ranked.firstWhere((MatchResult r) => r.candidate.rate <= cheapest).score.total}.',
        label: 'Raise my ceiling to \$$cheapest/hr',
        next: next,
        n: count(next),
      ));
    }
  }

  // 4. Mode.
  if (f.mode != null) {
    final MatchFilters next = f.copyWith(clearMode: true, mode: null);
    final int n = count(next);
    if (n > 0) {
      options.add((
        headline: 'Every candidate left is ${f.mode!.counterLabel}-only.',
        body: 'You asked for ${f.mode!.label.toLowerCase()}. $n people fit you on '
            'subjects, hours and budget and are only available ${f.mode!.counterLabel}. '
            'If you can be flexible on that, they are worth reading.',
        label: 'Allow ${f.mode!.counterLabel} as well',
        next: next,
        n: n,
      ));
    }
  }

  // 5. Score floor.
  if (f.minScore > 0 && ranked.isNotEmpty) {
    final int best = ranked.first.rankScore;
    if (best < f.minScore) {
      final MatchFilters next = f.copyWith(minScore: 0);
      options.add((
        headline: 'Nothing reaches ${f.minScore.round()} out of 100.',
        body: 'The best available fit scores $best. That is the honest ceiling of this pool — '
            'lowering the bar does not improve the candidates, it just lets you see them, '
            'with their weak points shown instead of hidden.',
        label: 'Show me the best $best anyway',
        next: next,
        n: count(next),
      ));
    }
  }

  // 6. Subjects.
  if (f.subjects.isNotEmpty) {
    final MatchFilters next = f.copyWith(subjects: const <String>{});
    final int n = count(next);
    if (n > 0) {
      final Set<String> near = <String>{
        for (final MatchResult r in ranked) ...r.candidate.subjects,
      }..removeAll(f.subjects);
      options.add((
        headline: 'None of your ${f.subjects.length} chosen subjects come up in this list.',
        body: 'Dropping the subject filter shows $n of the ${ranked.length} candidates, '
            'and ${near.take(3).join(', ')} are covered by someone in it. '
            'The order does not change — a candidate is still ranked on all five dimensions.',
        label: 'Search across every subject',
        next: next,
        n: n,
      ));
    }
  }

  if (options.isEmpty) {
    // Either the pool is genuinely empty, or every condition is firing at once
    // and no single relaxation is enough. Saying which one it is, is the whole
    // job of this screen.
    if (ranked.isEmpty) {
      return EmptyExplanation(
        headline: 'There is nobody in the pool to rank.',
        body: 'The recommender has nothing to compare you against, so the list '
            'is empty before any filter is applied. That is a data problem on '
            'our side, not something about your profile — there is no filter '
            'here that would fix it.',
        adjustLabel: 'Go back to the form',
        relaxed: const MatchFilters(),
        recovered: 0,
      );
    }
    return EmptyExplanation(
      headline: 'No single change is enough on its own.',
      body: 'Every condition below is excluding everybody, and relaxing any one '
          'of them by itself still leaves nothing. They are listed under this '
          'message with each one removable — clearing them all starts again '
          'from the full ranked pool of ${ranked.length}.',
      adjustLabel: 'Clear every filter',
      relaxed: const MatchFilters(),
      recovered: ranked.length,
    );
  }

  // The cheapest useful change: most results recovered, and when two conditions
  // recover the same number, the earlier one wins because it is the smaller ask.
  options.sort((a, b) => b.n.compareTo(a.n));
  final ({String headline, String body, String label, MatchFilters next, int n}) best = options.first;
  return EmptyExplanation(
    headline: best.headline,
    body: best.body,
    adjustLabel: best.label,
    relaxed: best.next,
    recovered: best.n,
  );
}

String? _partsPhrase(Set<int> parts) {
  if (parts.isEmpty) return null;
  final List<String> names = <String>[
    for (final int p in parts.toList()..sort()) Week.partLong[p],
  ];
  return switch (names.length) {
    1 => names.first,
    2 => '${names[0]} or ${names[1]}',
    _ => '${names.take(names.length - 1).join(', ')} or ${names.last}',
  };
}

/// Ranks a pool for a viewer. Sorted by score, then by rating, then by name so
/// the order is never arbitrary between two equal scores.
List<MatchResult> rank(List<Candidate> pool, Profile viewer) {
  final PublicPlace? from = viewer.publicPlace;
  final List<MatchResult> ranked = pool.map((Candidate c) {
    return MatchResult(
      candidate: c,
      score: scoreOf(c, viewer),
      distanceKm: distanceBetween(from, c.publicPlace),
    );
  }).toList();
  ranked.sort((MatchResult a, MatchResult b) {
    final int byScore = b.rankScore.compareTo(a.rankScore);
    if (byScore != 0) return byScore;
    final int byRating = b.candidate.rating.compareTo(a.candidate.rating);
    if (byRating != 0) return byRating;
    return a.candidate.name.compareTo(b.candidate.name);
  });
  return ranked;
}

// ═════════════════════════════════════════════════════════════════════════════
// THE POOL
// ═════════════════════════════════════════════════════════════════════════════

/// Tutors, as a student would see them.
final List<Candidate> sampleTutors = <Candidate>[
  Candidate(
    id: 't-amara',
    role: Role.tutor,
    name: 'Amara Okonkwo',
    headline: 'Calculus and statistics, nine years, ex-exam marker',
    subjects: <String>['Calculus', 'Statistics', 'Algebra'],
    styleLabel: 'Structured worked examples',
    styleTags: <String>['Worked examples', 'Exam technique', 'Weekly problem sets'],
    mode: SessionMode.online,
    rate: 46,
    location: 'Online, from Manchester',
    livesIn: 'Manchester',
    placeId: 'manchester-northern-quarter',
    locationPrivacy: LocationPrivacy.cityOnly,
    birthdate: DateTime(1991, 6, 2),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 9,
    rating: 4.9,
    reviews: 128,
    bio: 'I mark the papers your students are about to sit. After nine years of '
        'that, I teach the way the marks are actually given: one worked example, '
        'then you do the next one while I watch where it goes wrong. No lecture '
        'recordings, no slides.',
    credentials: <String>['MSc Mathematics, Manchester', 'A-level examiner since 2019'],
    languages: <String>['English', 'Igbo'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 14,
    fitFormat: 10,
    fitBudget: 9,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus, and it is the subject you flagged',
        'Nine years teaching it, plus exam-board marking since 2019 — she knows what the marks are awarded for.',
      ),
      FitNote(
        MatchDimension.style,
        'Worked examples, one at a time',
        'You said you learn by watching a problem solved and then doing the next one yourself.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$46 an hour',
        'One dollar above your ceiling. That is the only place this match costs you anything.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'Screen-shared working, with the recording kept for the week before an exam.',
      ),
    ],
  ),
  Candidate(
    id: 't-liang',
    role: Role.tutor,
    name: 'Liang Chen',
    headline: 'Calculus and physics through competition problems',
    subjects: <String>['Calculus', 'Physics', 'Algebra'],
    styleLabel: 'Hard problems, discussed',
    styleTags: <String>['Olympiad problems', 'Proof', 'Derivation'],
    mode: SessionMode.both,
    rate: 49,
    location: 'Riverside, and online',
    livesIn: 'Riverside, Cardiff',
    placeId: 'cardiff-riverside',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1988, 1, 19),
    statusText: 'Evenings mostly full',
    presence: PresenceStatus.busy,
    years: 8,
    photoTint: AppColors.avatarPlum,
    rating: 4.9,
    reviews: 74,
    bio: 'I coached the regional olympiad squad for four years. My first lesson '
        'is usually a problem you cannot solve, because the useful part of the '
        'hour is finding out exactly where your reasoning stops.',
    credentials: <String>['BSc Physics, Imperial', 'Regional olympiad coach 2020-2024'],
    languages: <String>['English', 'Mandarin'],
    availability: avail(const <String>['Tue-Eve', 'Fri-Eve', 'Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 12,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus and physics together',
        'Both of your focus subjects, and he teaches them as one subject rather than two.',
      ),
      FitNote(
        MatchDimension.style,
        'Starts from a problem you cannot do',
        'Harder than your stated preference, but it is the fastest route through the topics you named.',
      ),
      FitNote(
        MatchDimension.format,
        'Will travel or teach online',
        'You can move a session at a day\'s notice without losing the slot.',
      ),
    ],
  ),
  Candidate(
    id: 't-hana',
    role: Role.tutor,
    name: 'Hana Suzuki',
    headline: 'Physics, derived from first principles',
    subjects: <String>['Physics', 'Calculus'],
    styleLabel: 'Derivation before formula',
    styleTags: <String>['First principles', 'Diagrams', 'Exam technique'],
    mode: SessionMode.online,
    rate: 52,
    location: 'Online, from Leeds',
    livesIn: 'Leeds, West Yorkshire',
    placeId: 'leeds-hyde-park',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1990, 9, 8),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 7,
    photoTint: AppColors.avatarSlate,
    rating: 4.9,
    reviews: 96,
    bio: 'Students arrive with a formula sheet and no idea where the formulas '
        'came from. We rebuild them. It is slower for three weeks and then '
        'noticeably faster for the rest of the year.',
    credentials: <String>['PhD Physics, Leeds', 'PGCE'],
    languages: <String>['English', 'Japanese'],
    availability: avail(const <String>['Tue-Eve', 'Wed-Eve', 'Fri-Eve', 'Sun-Aft']),
    fitSubjects: 40,
    fitStyle: 11,
    fitFormat: 10,
    fitBudget: 6,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Physics, and the calculus underneath it',
        'Exactly the pairing you asked for, taught by someone with a doctorate in it.',
      ),
      FitNote(
        MatchDimension.style,
        'Derives before using',
        'Close to your preference: still worked examples, but she builds each one from the definition up.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$52 an hour',
        'Six dollars above your ceiling, the largest budget gap in your top five.',
      ),
    ],
  ),
  Candidate(
    id: 't-greta',
    role: Role.tutor,
    name: 'Greta Lindqvist',
    headline: 'Statistics you can actually use, via real datasets',
    subjects: <String>['Statistics', 'Computer Science', 'Calculus'],
    styleLabel: 'Project-based',
    styleTags: <String>['Real datasets', 'R and Python', 'Write-ups'],
    mode: SessionMode.online,
    rate: 58,
    location: 'Online, from Edinburgh',
    livesIn: 'Edinburgh, Scotland',
    placeId: 'edinburgh-leith',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1987, 11, 30),
    statusText: 'Evenings and weekends',
    presence: PresenceStatus.available,
    years: 6,
    rating: 5.0,
    reviews: 61,
    bio: 'We pick a dataset in week one — football results, your own sleep '
        'tracker, whatever — and every technique gets used on it. By the end you '
        'have one piece of work you understand completely.',
    credentials: <String>['MSc Data Science, Edinburgh', 'Statistical consultant'],
    languages: <String>['English', 'Swedish'],
    availability: avail(const <String>['Tue-Eve', 'Thu-Eve', 'Sat-Aft']),
    fitSubjects: 34,
    fitStyle: 9,
    fitFormat: 10,
    fitBudget: 4,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, applied rather than abstract',
        'One of your three subjects. She also covers the calculus that statistics leans on.',
      ),
      FitNote(
        MatchDimension.style,
        'Project-based, less exam drill',
        'A different approach from the worked examples you asked for. Better for understanding, weaker for sprinting to a test.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'Sessions are screen-share by default, which suits the coding side.',
      ),
    ],
  ),
  Candidate(
    id: 't-samir',
    role: Role.tutor,
    name: 'Samir Haddad',
    headline: 'SAT prep with an error log that does the work',
    subjects: <String>['SAT Prep', 'Algebra', 'Statistics'],
    styleLabel: 'Drill and review',
    styleTags: <String>['Timed sections', 'Error log', 'Weekly review'],
    mode: SessionMode.both,
    rate: 40,
    location: 'Fitzroy, and online',
    livesIn: 'Fitzroy, Melbourne',
    placeId: 'melbourne-fitzroy',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1986, 4, 12),
    statusText: 'SAT season is open',
    presence: PresenceStatus.available,
    years: 7,
    rating: 4.7,
    reviews: 143,
    bio: 'Every wrong answer gets written into a log with the reason it went '
        'wrong: misread, guessed, or genuinely did not know. Two weeks in, the '
        'log tells us what to study and I stop guessing.',
    credentials: <String>['BA Mathematics, Melbourne', 'Seven years of SAT coaching'],
    languages: <String>['English', 'Arabic'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Fri-Eve', 'Sun-Eve']),
    fitSubjects: 30,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Error logs and timed sections',
        'Very close to how you said you want to work: repetition, then a review of what broke.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Covers your algebra and statistics',
        'Not calculus, but both of the other subjects you listed, plus the SAT paper itself.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$40 an hour, under your ceiling',
        'Four full sessions a month still leaves room in the budget you gave.',
      ),
    ],
  ),
  Candidate(
    id: 't-tomas',
    role: Role.tutor,
    name: 'Tomás Ferreira',
    headline: 'Morning lessons before school, Spanish and history',
    subjects: <String>['Spanish', 'History'],
    styleLabel: 'Conversation first',
    styleTags: <String>['Speaking', 'Primary sources', 'No grammar drills'],
    mode: SessionMode.online,
    rate: 28,
    location: 'Online, from Porto',
    livesIn: 'Porto, Portugal',
    placeId: 'porto-cedofeita',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1998, 2, 27),
    statusText: 'Away until the 20th — exam marking',
    presence: PresenceStatus.away,
    years: 4,
    rating: 4.6,
    reviews: 52,
    bio: 'We talk for fifty minutes and I correct afterwards, in a list. Grammar '
        'comes last because it is the part you can look up.',
    credentials: <String>['BA Modern Languages, Porto'],
    languages: <String>['English', 'Portuguese', 'Spanish'],
    availability: avail(const <String>['Mon-Morn', 'Tue-Morn', 'Wed-Morn', 'Thu-Morn']),
    fitSubjects: 6,
    fitStyle: 4,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$28 an hour',
        'The cheapest option in this pool and comfortably inside your ceiling.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, as you asked',
        'His timezone is an hour ahead, which is what put his lessons in your mornings.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Spanish and history only',
        'Neither appears in your subject list. This is the main reason he ranks where he does.',
      ),
    ],
  ),
  // ── Candidates below the fold, kept in the pool so the list has a floor to
  // ── stand on and the weaker matches stay honest about why they are weaker.
  Candidate(
    id: 't-daniel',
    role: Role.tutor,
    name: 'Daniel Reyes',
    headline: 'Slow, patient algebra for students who got left behind',
    subjects: <String>['Algebra', 'Geometry'],
    styleLabel: 'Step by step, no rushing',
    styleTags: <String>['Foundations', 'Weekly homework', 'Parent updates'],
    mode: SessionMode.both,
    rate: 38,
    location: 'Camden, and online',
    livesIn: 'Camden, London',
    placeId: 'london-camden',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1984, 7, 4),
    statusText: 'Weekday afternoons free',
    presence: PresenceStatus.busy,
    years: 12,
    rating: 4.8,
    reviews: 87,
    bio: 'Most of the students I see were marked down somewhere in year 8 and '
        'never caught up. We go back to that point and walk forward.',
    credentials: <String>['BEd Secondary Mathematics'],
    languages: <String>['English', 'Spanish'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Eve', 'Fri-Aft', 'Sat-Morn']),
    fitSubjects: 24,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Step by step and unhurried',
        'Very close to the worked-example style you picked.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$38 an hour',
        'Well inside your ceiling, with room for an extra session before exams.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Algebra and geometry, no calculus',
        'He does not teach either of your two main subjects, which caps the score.',
      ),
    ],
  ),
  Candidate(
    id: 't-priya',
    role: Role.tutor,
    name: 'Priya Raghavan',
    headline: 'Chemistry and biology, anchored in the lab work',
    subjects: <String>['Chemistry', 'Biology'],
    styleLabel: 'Diagrams and practicals',
    styleTags: <String>['Past papers', 'Required practicals', 'Mark schemes'],
    mode: SessionMode.both,
    rate: 44,
    location: 'Hackney, and online',
    livesIn: 'Hackney, London',
    placeId: 'london-hackney',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1995, 5, 16),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 5,
    rating: 4.8,
    reviews: 102,
    bio: 'The required practicals are where most marks quietly disappear. I '
        'teach them from the diagrams up, then we do past papers until the '
        'marks are boring.',
    credentials: <String>['BSc Biochemistry, UCL', 'PGCE'],
    languages: <String>['English', 'Tamil'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Sat-Aft', 'Sun-Aft']),
    fitSubjects: 10,
    fitStyle: 7,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Will teach online or in person',
        'You can switch to a call during exam week without changing tutor.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$44 an hour',
        'Inside the ceiling you set.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Chemistry and biology',
        'Neither is on your list. Strong tutor, wrong two subjects for you.',
      ),
    ],
  ),
  Candidate(
    id: 't-marcus',
    role: Role.tutor,
    name: 'Marcus Bell',
    headline: 'Essay writing by rewriting your own sentences',
    subjects: <String>['Essay Writing', 'English Literature', 'History'],
    styleLabel: 'Workshop and feedback loops',
    styleTags: <String>['Draft and redraft', 'Argument structure', 'Mark scheme'],
    mode: SessionMode.inPerson,
    rate: 34,
    location: 'Islington, in person only',
    livesIn: 'Islington, London',
    placeId: 'london-islington',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1979, 10, 1),
    statusText: 'Full until the new year',
    presence: PresenceStatus.busy,
    years: 14,
    rating: 4.7,
    reviews: 68,
    bio: 'You send me the draft. I mark it the way the exam board would, then we '
        'spend the hour cutting the two paragraphs that weaken the argument.',
    credentials: <String>['MA English, KCL'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft']),
    fitSubjects: 8,
    fitStyle: 6,
    fitFormat: 3,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$34 an hour',
        'Cheap for the experience. That is genuinely the strongest line here.',
      ),
      FitNote(
        MatchDimension.style,
        'Feedback loops, not worked examples',
        'You learn by iteration rather than by demonstration, which is a real difference.',
      ),
      FitNote(
        MatchDimension.format,
        'In person only, in Islington',
        'You said online. Travel is not optional with Marcus, which is what pushes him down the list.',
      ),
    ],
  ),
  Candidate(
    id: 't-jonah',
    role: Role.tutor,
    name: 'Jonah Pike',
    headline: 'Biology and chemistry for the year-10 jump',
    subjects: <String>['Biology', 'Chemistry'],
    styleLabel: 'Diagram-first',
    styleTags: <String>['Visual notes', 'Flashcard decks', 'Short sessions'],
    mode: SessionMode.online,
    rate: 30,
    location: 'Online, from Bristol',
    livesIn: 'Bristol',
    placeId: 'bristol-clifton',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2000, 8, 21),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 2,
    rating: 4.5,
    reviews: 29,
    bio: 'Three years in, still cheap while I build up reviews. I teach the '
        'diagram before the paragraph, because the paragraph is easier once the '
        'picture is there.',
    credentials: <String>['BSc Biomedical Science'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Thu-Eve', 'Fri-Eve']),
    fitSubjects: 8,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, and free every weeknight',
        'Widest availability in this pool, which is why the grid lights up even though the subjects do not.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$30 an hour',
        'The second cheapest in the list.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Biology and chemistry',
        'No overlap with what you asked for. Read the grid, not the score.',
      ),
    ],
  ),
  Candidate(
    id: 't-rachel',
    role: Role.tutor,
    name: 'Rachel Osei',
    headline: 'History essays: map the argument before writing',
    subjects: <String>['History', 'Essay Writing'],
    styleLabel: 'Argument mapping',
    styleTags: <String>['Source analysis', 'Planning', 'Timed essays'],
    mode: SessionMode.online,
    rate: 36,
    location: 'Online, from Birmingham',
    livesIn: 'Birmingham, West Midlands',
    placeId: 'birmingham-moseley',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1993, 12, 5),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 6,
    rating: 4.8,
    reviews: 54,
    bio: 'Nine times out of ten the problem is not the writing, it is that the '
        'argument has three claims in it. We map it on one page first, then the '
        'essay writes itself in half the time.',
    credentials: <String>['MA History, Warwick'],
    languages: <String>['English', 'Twi'],
    availability: avail(const <String>['Wed-Eve', 'Thu-Eve', 'Sun-Eve']),
    fitSubjects: 6,
    fitStyle: 6,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, in a timezone that matches yours',
        'No travel, and she keeps one evening slot free every week.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$36 an hour',
        'Comfortably inside your ceiling.',
      ),
      FitNote(
        MatchDimension.subjects,
        'History and essay writing',
        'Outside your stated subjects, which is the whole reason she is not higher.',
      ),
    ],
  ),
  Candidate(
    id: 't-nora',
    role: Role.tutor,
    name: 'Nora Bergman',
    headline: 'Geometry by construction, with compass and straight edge',
    subjects: <String>['Geometry', 'Algebra'],
    styleLabel: 'Visual proofs',
    styleTags: <String>['Constructions', 'Proof', 'No calculators'],
    mode: SessionMode.inPerson,
    rate: 42,
    location: 'Sheffield, in person only',
    livesIn: 'Sheffield, South Yorkshire',
    placeId: 'sheffield-crookes',
    locationPrivacy: LocationPrivacy.hidden,
    birthdate: DateTime(1985, 3, 23),
    statusText: 'One slot left on Wednesdays',
    presence: PresenceStatus.busy,
    years: 10,
    rating: 4.8,
    reviews: 45,
    bio: 'We draw everything before we write anything. It is slower for a term, '
        'and then geometry stops being a memory test.',
    credentials: <String>['BSc Mathematics'],
    languages: <String>['English', 'German'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft', 'Sat-Morn']),
    fitSubjects: 24,
    fitStyle: 10,
    fitFormat: 7,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Algebra, and the geometry behind it',
        'One of your subjects, taught in a way that sticks.',
      ),
      FitNote(
        MatchDimension.style,
        'Draw it before you write it',
        'A cousin of worked examples, so it transfers.',
      ),
      FitNote(
        MatchDimension.format,
        'In person only',
        'Only workable if you are near her. That is the decision this match turns on.',
      ),
    ],
  ),
  Candidate(
    id: 't-ibrahim',
    role: Role.tutor,
    name: 'Ibrahim Touré',
    headline: 'Statistics and code, learned by building',
    subjects: <String>['Computer Science', 'Statistics'],
    styleLabel: 'Build first',
    styleTags: <String>['Python', 'Projects', 'Portfolio'],
    mode: SessionMode.online,
    rate: 55,
    location: 'Online, from Paris',
    livesIn: 'Paris, France',
    placeId: 'paris-montmartre',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1996, 6, 11),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 5,
    rating: 4.9,
    reviews: 71,
    bio: 'You will write more code than you expect in the first hour. We only '
        'open the textbook when the code does something you cannot explain.',
    credentials: <String>['MEng Computer Science', 'Backend engineer'],
    languages: <String>['English', 'French'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Sat-Morn']),
    fitSubjects: 16,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 6,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Build first, explain second',
        'You asked for worked examples. This is the opposite order and it suits some people better.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, and generous with evenings',
        'Four evenings a week, including the two you are normally free.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$55 an hour',
        'The second largest gap to your ceiling in this list.',
      ),
    ],
  ),
  Candidate(
    id: 't-evelyn',
    role: Role.tutor,
    name: 'Evelyn Marsh',
    headline: 'Music theory, taught by ear first',
    subjects: <String>['Music Theory'],
    styleLabel: 'Ear first, notation second',
    styleTags: <String>['Listening', 'Harmony', 'Grade exams'],
    mode: SessionMode.inPerson,
    rate: 32,
    location: 'Bath, in person only',
    livesIn: 'Bath, Somerset',
    placeId: 'bath-widcombe',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1972, 1, 29),
    statusText: 'Studio slots on Saturdays',
    presence: PresenceStatus.available,
    years: 20,
    rating: 4.9,
    reviews: 158,
    bio: 'Fifteen years of grade-exam preparation. My students hear the cadence '
        'before they can name it, which is the right order.',
    credentials: <String>['ABRSM Grade 8 distinction', 'DipABRSM'],
    languages: <String>['English'],
    availability: avail(const <String>['Tue-Aft', 'Thu-Aft', 'Sat-Morn']),
    fitSubjects: 4,
    fitStyle: 3,
    fitFormat: 7,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$32 an hour',
        'Reasonable, and she has fifteen years behind it.',
      ),
      FitNote(
        MatchDimension.format,
        'In person only',
        'You asked for online. Ear training genuinely needs the room.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Music theory, nothing else',
        'One subject, and not one of yours. She is in this list so you can see that a five-star tutor can still be the wrong tutor.',
      ),
    ],
  ),
  Candidate(
    id: 't-claire',
    role: Role.tutor,
    name: 'Claire Dubois',
    headline: 'Literature by question, not by summary',
    subjects: <String>['English Literature', 'Essay Writing'],
    styleLabel: 'Socratic',
    styleTags: <String>['Discussion', 'Close reading', 'No notes given'],
    mode: SessionMode.online,
    rate: 33,
    location: 'Online, from Lyon',
    livesIn: 'Lyon, France',
    placeId: 'lyon-croix-rousse',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1990, 4, 3),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    years: 9,
    rating: 4.7,
    reviews: 39,
    bio: 'I will not give you a summary of the book. I will ask you questions '
        'until you produce one, and that one you will remember.',
    credentials: <String>['MA Comparative Literature'],
    languages: <String>['English', 'French'],
    availability: avail(const <String>['Thu-Eve', 'Fri-Eve', 'Sun-Eve']),
    fitSubjects: 6,
    fitStyle: 5,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.format,
        'Online, one evening a week',
        'A single usable slot, which makes scheduling brittle even though the format fits.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$33 an hour',
        'Inside your ceiling with room to spare.',
      ),
      FitNote(
        MatchDimension.subjects,
        'English literature and essay writing',
        'Not your subjects. The score is being honest about that.',
      ),
    ],
  ),
  Candidate(
    id: 't-victor',
    role: Role.tutor,
    name: 'Victor Alvarez',
    headline: 'History from primary sources, afternoons only',
    subjects: <String>['History', 'Spanish'],
    styleLabel: 'Primary sources',
    styleTags: <String>['Archive work', 'Source questions', 'Debate'],
    mode: SessionMode.inPerson,
    rate: 31,
    location: 'Oxford, in person only',
    livesIn: 'Oxford, Oxfordshire',
    placeId: 'oxford-jericho',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(1992, 9, 17),
    statusText: 'Evenings only this term',
    presence: PresenceStatus.busy,
    years: 7,
    rating: 4.6,
    reviews: 33,
    bio: 'We read what was actually written at the time, badly translated and '
        'all, and then argue about it. Source questions stop being a trick.',
    credentials: <String>['BA History, Salamanca'],
    languages: <String>['English', 'Spanish'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Aft', 'Fri-Aft']),
    fitSubjects: 6,
    fitStyle: 4,
    fitFormat: 3,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$31 an hour',
        'Cheap, and it is the only thing that lines up.',
      ),
      FitNote(
        MatchDimension.subjects,
        'History and Spanish',
        'No overlap with your subjects at all.',
      ),
      FitNote(
        MatchDimension.format,
        'Weekday afternoons only, in person',
        'Two independent blockers: the format and the hours. This is what a bottom-of-list match looks like.',
      ),
    ],
  ),
];

/// Students, as a tutor would see them.
final List<Candidate> sampleStudents = <Candidate>[
  Candidate(
    id: 's-maya',
    role: Role.student,
    name: 'Maya Chen',
    headline: 'Year 12, needs calculus from a B+ to an A before mocks',
    subjects: <String>['Calculus', 'Physics'],
    styleLabel: 'Watches one, then does one',
    styleTags: <String>['Worked examples', 'Weekly homework', 'Mock papers'],
    mode: SessionMode.both,
    rate: 45,
    location: 'Highbury, will travel 3 km',
    livesIn: 'Highbury, London',
    placeId: 'london-highbury',
    locationPrivacy: LocationPrivacy.cityOnly,
    birthdate: DateTime(2009, 3, 14),
    statusText: 'Mocks in eleven weeks',
    presence: PresenceStatus.available,
    grade: 'Year 12',
    rating: 4.9,
    reviews: 3,
    bio: 'I am fine in class and then I freeze on the harder questions in the '
        'exam. I have the mock in eleven weeks and a folder of past papers '
        'already printed.',
    credentials: <String>['Year 12', 'Predicted A- in maths', 'A in physics'],
    languages: <String>['English', 'Mandarin'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 34,
    fitStyle: 14,
    fitFormat: 10,
    fitBudget: 9,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Calculus, and physics that leans on it',
        'Your two subjects, and she already has the past papers printed.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants to watch one, then do one',
        'Identical to how you teach. Almost no adaptation needed on your side.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$45 an hour ceiling',
        'One dollar below your rate, and she said so plainly rather than haggling later.',
      ),
    ],
  ),
  Candidate(
    id: 's-aisha',
    role: Role.student,
    name: 'Aisha Rahman',
    headline: 'Year 13, statistics and algebra for a medicine application',
    subjects: <String>['Statistics', 'Algebra', 'SAT Prep'],
    styleLabel: 'Drills under time pressure',
    styleTags: <String>['Timed practice', 'Error log', 'Grade 9 target'],
    mode: SessionMode.online,
    rate: 50,
    location: 'Online only, two hours ahead of you',
    livesIn: 'Cairo, Egypt',
    placeId: 'cairo-zamalek',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2008, 7, 8),
    statusText: 'Revision until exams',
    presence: PresenceStatus.busy,
    grade: 'Year 13',
    photoTint: AppColors.avatarClay,
    rating: 4.9,
    reviews: 4,
    bio: 'Grade 8 predicted, need a 9 for the course I want. I do not need '
        'understanding, I need speed and fewer careless errors.',
    credentials: <String>['Year 13', 'Predicted A in statistics'],
    languages: <String>['English', 'Bengali'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
    fitSubjects: 30,
    fitStyle: 13,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, your main subject',
        'Plus algebra, and a clear reason for wanting both.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants timed practice and an error log',
        'You can reuse the same error-log format you already run for exam students.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$50 an hour ceiling',
        'Above your rate, so no negotiation is needed at any point.',
      ),
    ],
  ),
  Candidate(
    id: 's-ethan',
    role: Role.student,
    name: 'Ethan Brooks',
    headline: 'Year 13, calculus and statistics, but only on Saturday mornings',
    subjects: <String>['Calculus', 'Statistics'],
    styleLabel: 'First principles',
    styleTags: <String>['Derivation', 'Proof', 'Long sessions'],
    mode: SessionMode.online,
    rate: 60,
    location: 'Online only',
    livesIn: 'Nottingham',
    placeId: 'nottingham-hockley',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2008, 2, 14),
    statusText: 'Open for sessions',
    presence: PresenceStatus.available,
    grade: 'Year 13',
    rating: 4.8,
    reviews: 5,
    bio: 'I want to understand where the results come from rather than memorise '
        'them. I have one free morning a week and I would rather use two hours '
        'of it than one.',
    credentials: <String>['Year 13', 'Further maths', 'Physics olympiad bronze'],
    languages: <String>['English'],
    availability: avail(const <String>['Sat-Morn']),
    fitSubjects: 40,
    fitStyle: 11,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Exactly your two subjects, at a serious level',
        'Further maths and olympiad work — you would not be simplifying anything.',
      ),
      FitNote(
        MatchDimension.style,
        'Wants derivations, not shortcuts',
        'Close to your worked-example approach; he will want the proof as well.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$60 an hour ceiling',
        'The highest budget in your inbox, and it is not the reason to take him.',
      ),
    ],
  ),
  Candidate(
    id: 's-kai',
    role: Role.student,
    name: 'Kai Nakamura',
    headline: 'Year 12, statistics through a project he already started',
    subjects: <String>['Statistics', 'Computer Science'],
    styleLabel: 'Learn by building',
    styleTags: <String>['Python', 'Own dataset', 'Portfolio'],
    mode: SessionMode.online,
    rate: 60,
    location: 'Online only, one hour ahead of you',
    livesIn: 'Rotterdam, Netherlands',
    placeId: 'rotterdam-kralingen',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2009, 10, 6),
    statusText: 'Project work through the winter',
    presence: PresenceStatus.available,
    grade: 'Year 12',
    rating: 4.7,
    reviews: 6,
    bio: 'I have three years of cycling data and a half-finished analysis. I '
        'want a tutor who will help me finish it properly rather than start a '
        'textbook from chapter one.',
    credentials: <String>['Year 12', 'Python since year 8'],
    languages: <String>['English', 'Japanese'],
    availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve']),
    fitSubjects: 26,
    fitStyle: 9,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.subjects,
        'Statistics, applied to his own data',
        'Your main subject, used immediately on something he cares about.',
      ),
      FitNote(
        MatchDimension.style,
        'Project-led rather than exercise-led',
        'The opposite of your usual format. It works, but it is a different lesson to plan.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in a timezone that mostly lines up',
        'Three evening slots a week, one hour ahead of you.',
      ),
    ],
  ),
  Candidate(
    id: 's-leo',
    role: Role.student,
    name: 'Leo Novak',
    headline: 'Year 11, chemistry and biology, revision in the evenings',
    subjects: <String>['Chemistry', 'Biology'],
    styleLabel: 'Flashcards and past papers',
    styleTags: <String>['Revision', 'Grade 6 target', 'Short sessions'],
    mode: SessionMode.online,
    rate: 35,
    location: 'Online only',
    livesIn: 'Manchester',
    placeId: 'manchester-didsbury',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2010, 5, 19),
    statusText: 'Weeknights after six',
    presence: PresenceStatus.available,
    grade: 'Year 11',
    rating: 4.6,
    reviews: 2,
    bio: 'I am on a grade 5 in both and I need a 6 to take either at A-level. '
        'I do not need to love it, I need to pass it.',
    credentials: <String>['Year 11'],
    languages: <String>['English', 'Polish'],
    availability: avail(const <String>['Tue-Eve', 'Wed-Eve', 'Thu-Eve']),
    fitSubjects: 8,
    fitStyle: 10,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$35 an hour ceiling',
        'Inside your rate with room for an extra session a month.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in the evenings',
        'Fits the three evenings you keep free.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Chemistry and biology',
        'Neither is a subject you teach. The budget line is the only strong one.',
      ),
    ],
  ),
  Candidate(
    id: 's-sofia',
    role: Role.student,
    name: 'Sofia Marino',
    headline: 'Year 12, essay writing for coursework deadlines',
    subjects: <String>['Essay Writing', 'English Literature'],
    styleLabel: 'Feedback on drafts',
    styleTags: <String>['Redrafting', 'Structure', 'Coursework'],
    mode: SessionMode.online,
    rate: 40,
    location: 'Online only',
    livesIn: 'Brighton',
    placeId: 'brighton-kemptown',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2009, 8, 2),
    statusText: 'Coursework deadlines this half term',
    presence: PresenceStatus.busy,
    grade: 'Year 12',
    rating: 4.6,
    reviews: 3,
    bio: 'My ideas are fine and my structure is not. I need someone to read a '
        'draft and tell me which paragraph to cut, not to tell me to plan better.',
    credentials: <String>['Year 12', 'A in English literature'],
    languages: <String>['English', 'Italian'],
    availability: avail(const <String>['Mon-Eve', 'Wed-Eve', 'Thu-Eve']),
    fitSubjects: 6,
    fitStyle: 8,
    fitFormat: 10,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.budget,
        '\$40 an hour ceiling',
        'Below your rate, so she can afford weekly rather than fortnightly.',
      ),
      FitNote(
        MatchDimension.format,
        'Online, in the evenings',
        'Overlaps two of your free evenings.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Essay writing and literature',
        'Not subjects you teach. She would be a poor fit for you despite being an easy student.',
      ),
    ],
  ),
  Candidate(
    id: 's-owen',
    role: Role.student,
    name: 'Owen Pratt',
    headline: 'Year 10, algebra in the afternoons, needs the basics rebuilt',
    subjects: <String>['Algebra', 'Geometry'],
    styleLabel: 'Slow and patient',
    styleTags: <String>['Foundations', 'Homework help', 'Weekly'],
    mode: SessionMode.inPerson,
    rate: 40,
    location: 'Camden, in person only',
    livesIn: 'Camden, London',
    placeId: 'london-camden',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2010, 11, 25),
    statusText: 'Afternoons only, with support',
    presence: PresenceStatus.available,
    grade: 'Year 10',
    rating: 4.5,
    reviews: 2,
    bio: 'I lost the plot somewhere in year 8 and nobody noticed. I would rather '
        'go back and fix it than keep pretending.',
    credentials: <String>['Year 10'],
    languages: <String>['English'],
    availability: avail(const <String>['Mon-Aft', 'Wed-Aft', 'Fri-Aft']),
    fitSubjects: 18,
    fitStyle: 12,
    fitFormat: 4,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Wants slow and patient',
        'A genuine match on temperament, with someone who has admitted the gap.',
      ),
      FitNote(
        MatchDimension.budget,
        '\$40 an hour ceiling',
        'Inside your rate.',
      ),
      FitNote(
        MatchDimension.format,
        'In person, in the afternoons',
        'Not online, and not in the evening — two mismatches at once.',
      ),
    ],
  ),
  Candidate(
    id: 's-nadia',
    role: Role.student,
    name: 'Nadia Haddad',
    headline: 'Year 10, Spanish and history, after school',
    subjects: <String>['Spanish', 'History'],
    styleLabel: 'Conversation and reading',
    styleTags: <String>['Speaking', 'Source work', 'No exams yet'],
    mode: SessionMode.inPerson,
    rate: 30,
    location: 'Bath, in person only',
    livesIn: 'Bath, Somerset',
    placeId: 'bath-widcombe',
    locationPrivacy: LocationPrivacy.area,
    birthdate: DateTime(2010, 6, 30),
    statusText: 'Back in two weeks',
    presence: PresenceStatus.away,
    grade: 'Year 10',
    rating: 4.4,
    reviews: 1,
    bio: 'Languages are the only lessons I look forward to. I want to actually '
        'speak it, not just pass the paper.',
    credentials: <String>['Year 10'],
    languages: <String>['English', 'Arabic'],
    availability: avail(const <String>['Mon-Aft', 'Tue-Aft', 'Thu-Aft']),
    fitSubjects: 5,
    fitStyle: 9,
    fitFormat: 4,
    fitBudget: 10,
    notes: <FitNote>[
      FitNote(
        MatchDimension.style,
        'Conversation-led, which matches how she is taught at school',
        'The clearest line in this match, and it is not the one that decides it.',
      ),
      FitNote(
        MatchDimension.subjects,
        'Spanish and history',
        'Outside your subjects.',
      ),
      FitNote(
        MatchDimension.format,
        'In person, in Bath, on weekday afternoons',
        'Three mismatches on one line. This is the bottom of the list and it should be.',
      ),
    ],
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// Onboarding options — the answer sets the recommender can actually use
// ═════════════════════════════════════════════════════════════════════════════

abstract final class OnboardingOptions {
  static const List<String> subjects = <String>[
    'Algebra',
    'Geometry',
    'Calculus',
    'Statistics',
    'Physics',
    'Chemistry',
    'Biology',
    'English Literature',
    'Essay Writing',
    'History',
    'Spanish',
    'Computer Science',
    'Music Theory',
    'SAT Prep',
  ];

  static const List<String> studentStyles = <String>[
    'Watch one worked example, then do the next one myself',
    'Start from the theory and derive everything',
    'Talk it through until it makes sense',
    'Drill past papers under time pressure',
    'Learn it by building or making something',
  ];

  static const List<String> tutorStyles = <String>[
    'I work through examples slowly and let the student steer',
    'I go back to first principles and build up',
    'I teach by discussion and questioning',
    'I run timed practice and review the errors',
    'I teach by getting the student to build something',
  ];

  static const List<String> studentGoals = <String>[
    'Pass a specific exam that is coming up',
    'Move up a grade or two this year',
    'Understand the subject properly, not just pass it',
    'Catch up on foundations I missed earlier',
    'Decide whether to take this subject further',
  ];

  static const List<String> tutorGoals = <String>[
    'Fill a few steady evenings a week',
    'Take on one or two exam-year students before mocks',
    'Work with beginners who need foundations rebuilt',
    'Teach the hardest material to students who want it',
    'Build up reviews and a regular timetable',
  ];

  /// The languages the sample people actually speak, plus the usual suspects —
  /// so a picked set in the edit form always has somewhere to come back from.
  static const List<String> languages = <String>[
    'English',
    'Arabic',
    'Bengali',
    'French',
    'German',
    'Igbo',
    'Italian',
    'Japanese',
    'Mandarin',
    'Polish',
    'Portuguese',
    'Spanish',
    'Swedish',
    'Tamil',
    'Twi',
  ];

  static const List<String> genders = <String>[
    'Female',
    'Male',
    'Non-binary',
    Profile.noAnswer,
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Requests — a static inbox per side, so the three tabs have something honest
// in them. A student reads [sampleRequests] (their outbox); a tutor reads
// [sampleReceivedRequests] (their inbox). Same six shapes either way, written
// from the side that actually wrote them.
// ═════════════════════════════════════════════════════════════════════════════

const List<MatchRequest> sampleRequests = <MatchRequest>[
  MatchRequest(
    id: 'r-1041',
    counterpartId: 't-amara',
    counterpartName: 'Amara Okonkwo',
    counterpartRole: Role.tutor,
    subject: 'Calculus',
    score: 93,
    status: RequestStatus.accepted,
    sentOn: 'Sent Mon 6 Oct',
    note: 'Mock in eleven weeks. Weekday evenings after 6, and I can do Saturday morning if that is easier for you.',
    reply: 'Yes — I have Tuesday and Thursday free from next week. Send me your last mock paper and I will look at it before we start.',
  ),
  MatchRequest(
    id: 'r-1038',
    counterpartId: 't-liang',
    counterpartName: 'Liang Chen',
    counterpartRole: Role.tutor,
    subject: 'Calculus and Physics',
    score: 82,
    status: RequestStatus.pending,
    sentOn: 'Sent Sun 5 Oct',
    note: 'Interested in both subjects together if that works. I am free Tuesday and Friday evenings.',
  ),
  MatchRequest(
    id: 'r-1036',
    counterpartId: 't-hana',
    counterpartName: 'Hana Suzuki',
    counterpartRole: Role.tutor,
    subject: 'Physics',
    score: 77,
    status: RequestStatus.pending,
    sentOn: 'Sent Fri 3 Oct',
    note: 'Would you start with mechanics or electricity? I am weaker on mechanics.',
  ),
  MatchRequest(
    id: 'r-1030',
    counterpartId: 't-marcus',
    counterpartName: 'Marcus Bell',
    counterpartRole: Role.tutor,
    subject: 'Essay Writing',
    score: 61,
    status: RequestStatus.declined,
    sentOn: 'Sent Tue 30 Sep',
    note: 'I know you are in person only — I could travel on Thursdays if that is possible.',
    reply: 'Afraid not — my Thursdays filled up for the term. Rachel Osei does the same work online and she is good. Worth trying her.',
  ),
  MatchRequest(
    id: 'r-1029',
    counterpartId: 't-evelyn',
    counterpartName: 'Evelyn Marsh',
    counterpartRole: Role.tutor,
    subject: 'Music Theory',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Mon 29 Sep',
    note: 'Long shot — you are in Bath and I am not, but I wanted to ask about online grade 5 theory.',
    reply: 'I only teach in person, I am afraid. For grade 5 theory online, try the ABRSM practice papers first — most people need less teaching than they think there.',
  ),
  MatchRequest(
    id: 'r-1044',
    counterpartId: 't-greta',
    counterpartName: 'Greta Lindqvist',
    counterpartRole: Role.tutor,
    subject: 'Statistics',
    score: 71,
    status: RequestStatus.pending,
    sentOn: 'Sent Wed 8 Oct',
    note: 'Are you taking on new students in January? I would rather wait for a slot than start with someone else.',
  ),
];

/// Students' requests, as the tutor sees them: the mirror of [sampleRequests].
/// Written from the side that actually wrote them, and scored against
/// [demoTutorProfile], so a tutor's inbox is never another tutor's outbox
/// wearing their name.
const List<MatchRequest> sampleReceivedRequests = <MatchRequest>[
  MatchRequest(
    id: 'r-2011',
    counterpartId: 's-maya',
    counterpartName: 'Maya Chen',
    counterpartRole: Role.student,
    subject: 'Calculus and Physics',
    score: 87,
    status: RequestStatus.accepted,
    sentOn: 'Sent Mon 6 Oct',
    outgoing: false,
    note: 'Mock in eleven weeks, so I am working backwards from it. I have all '
        'the past papers printed already — could we start Monday or Tuesday '
        'evening after six?',
    reply: 'Yes — Tuesday and Thursday evenings are free from next week. Send '
        'me your last mock paper and we will spend the first hour on the '
        'questions that cost you marks.',
  ),
  MatchRequest(
    id: 'r-2009',
    counterpartId: 's-aisha',
    counterpartName: 'Aisha Rahman',
    counterpartRole: Role.student,
    subject: 'Statistics',
    score: 83,
    status: RequestStatus.pending,
    sentOn: 'Sent Wed 8 Oct',
    outgoing: false,
    note: 'Grade 8 predicted and I need a 9 for the course I want. I do not '
        'need the ideas explained again — I need speed under time pressure '
        'and fewer careless errors.',
  ),
  MatchRequest(
    id: 'r-2006',
    counterpartId: 's-ethan',
    counterpartName: 'Ethan Brooks',
    counterpartRole: Role.student,
    subject: 'Calculus',
    score: 76,
    status: RequestStatus.pending,
    sentOn: 'Sent Sun 5 Oct',
    outgoing: false,
    note: 'I have exactly one free morning a week. I would rather use Saturday '
        'mornings properly, two hours at a time, than squeeze an evening in. '
        'I want the derivations, not shortcuts.',
  ),
  MatchRequest(
    id: 'r-2004',
    counterpartId: 's-kai',
    counterpartName: 'Kai Nakamura',
    counterpartRole: Role.student,
    subject: 'Statistics',
    score: 70,
    status: RequestStatus.pending,
    sentOn: 'Sent Fri 3 Oct',
    outgoing: false,
    note: 'Three years of cycling data and a half-finished analysis. Could the '
        'lessons be about finishing that properly rather than starting a '
        'textbook from chapter one?',
  ),
  MatchRequest(
    id: 'r-2001',
    counterpartId: 's-sofia',
    counterpartName: 'Sofia Marino',
    counterpartRole: Role.student,
    subject: 'Essay Writing',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Tue 30 Sep',
    outgoing: false,
    note: 'My ideas are fine and my structure falls apart. Could you read a '
        'draft and tell me which paragraph to cut?',
    reply: 'I only teach maths and the sciences, I am afraid. Claire Dubois '
        'and Rachel Osei both do this work online, and they are good.',
  ),
  MatchRequest(
    id: 'r-1998',
    counterpartId: 's-owen',
    counterpartName: 'Owen Pratt',
    counterpartRole: Role.student,
    subject: 'Algebra',
    score: 44,
    status: RequestStatus.declined,
    sentOn: 'Sent Mon 29 Sep',
    outgoing: false,
    note: 'I lost the thread somewhere in year 8 and nobody noticed. I would '
        'rather rebuild it than keep pretending. I can do weekday afternoons, '
        'in person if that is easier.',
    reply: 'I teach online, and my week is mostly evenings — Daniel Reyes '
        'teaches in Camden in the afternoons and would be the better fit.',
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// Conversations — what a request turns into
//
// Two lists, one per side, the same way the request inboxes above work. Either
// side can send a request, so each list carries both directions: a pending one
// this side must answer, a pending one it is waiting on, accepted threads with
// real talking in them — the student's includes every kind of message the
// composer can make — and one declined with the refusal readable. A student
// reads [sampleConversations]; a tutor reads [sampleReceivedConversations].
// ═════════════════════════════════════════════════════════════════════════════

/// A student's side. The counterpart is a tutor, `fromMe` is the student
/// talking, and `requestedByMe` says which way the asking went — the tutor's
/// offer at the top is the one this side has to answer.
///
/// Not const: the first thread carries [sampleWorksheetPhoto], bytes decoded at
/// load. Everything else in the list still would be.
final List<Conversation> sampleConversations = <Conversation>[
  // The rich thread, already accepted: a photo, a voice note, a call line and
  // a proposed session, so every bubble the composer can make is visible on
  // the first run. It is also the one thread whose session card can be
  // answered in the sample data.
  Conversation(
    id: 'c-1045',
    counterpartId: 't-greta',
    counterpartName: 'Greta Lindqvist',
    counterpartRole: Role.tutor,
    subject: 'Calculus',
    status: RequestStatus.accepted,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Question 7 is the one that keeps going wrong. The working is '
            'fine until the last two lines and then I lose the thread.',
        fromMe: true,
        sentAt: '13:58',
      ),
      ChatMessage(
        text: 'Photo · the marked page',
        fromMe: false,
        sentAt: '14:02',
        kind: MessageKind.image,
        image: sampleWorksheetPhoto,
      ),
      ChatMessage(
        text: 'That is the line. You are dropping the constant two steps '
            'before the mark scheme asks you to. Same mistake in parts b and c.',
        fromMe: false,
        sentAt: '14:03',
      ),
      ChatMessage(
        text: 'That makes more sense than the mark scheme does. Thursday '
            'evening to go through the rest of the paper?',
        fromMe: true,
        sentAt: '14:06',
      ),
      ChatMessage(
        text: 'Voice note · 0:18',
        fromMe: false,
        sentAt: '14:09',
        kind: MessageKind.voice,
        seconds: 18,
      ),
      ChatMessage(
        text: 'Voice call · 04:12',
        fromMe: true,
        sentAt: '14:20',
        kind: MessageKind.call,
      ),
      ChatMessage(
        id: 'm-session-c-1045',
        text: 'Session proposed · Thu 22 Oct · 17:30',
        fromMe: false,
        sentAt: '14:24',
        kind: MessageKind.session,
        sessionWhen: 'Thu 22 Oct · 17:30',
      ),
    ],
  ),
  Conversation(
    id: 'c-1042',
    counterpartId: 't-hana',
    counterpartName: 'Hana Suzuki',
    counterpartRole: Role.tutor,
    subject: 'Physics',
    status: RequestStatus.pending,
    requestedByMe: false,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'I saw your mock is in eleven weeks. I have Tuesday and Friday '
            'evenings free, and we would start with the mechanics questions — '
            'the ones that cost marks under time. Shall I put you down for '
            'Tuesday?',
        fromMe: false,
        sentAt: '11:26',
      ),
    ],
  ),
  Conversation(
    id: 'c-1041',
    counterpartId: 't-amara',
    counterpartName: 'Amara Okonkwo',
    counterpartRole: Role.tutor,
    subject: 'Calculus',
    status: RequestStatus.accepted,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Mock in eleven weeks. I can do weekday evenings after six, or '
            'Saturday morning if that is easier for you.',
        fromMe: true,
        sentAt: '18:04',
      ),
      ChatMessage(
        text: 'Yes — Tuesday and Thursday are free from next week. Send me '
            'your last mock paper and I will look at it before we start.',
        fromMe: false,
        sentAt: '20:12',
      ),
      ChatMessage(
        text: 'Sent it this morning. Question 7 is the one that keeps going '
            'wrong — I run out of time before the last part.',
        fromMe: true,
        sentAt: '07:41',
      ),
      ChatMessage(
        text: 'Read it. Your opening move is fine, the marks go in the last '
            'two lines. We will fix exactly that on Tuesday.',
        fromMe: false,
        sentAt: '08:15',
      ),
    ],
  ),
  Conversation(
    id: 'c-1040',
    counterpartId: 't-samir',
    counterpartName: 'Samir Haddad',
    counterpartRole: Role.tutor,
    subject: 'SAT Prep',
    status: RequestStatus.accepted,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'I need speed more than theory — the timing is what kills me, '
            'I never finish the last section.',
        fromMe: true,
        sentAt: '16:20',
      ),
      ChatMessage(
        text: 'Then we start with timed sections and an error log. Bring the '
            'last two papers you sat, wrong answers included.',
        fromMe: false,
        sentAt: '17:05',
      ),
      ChatMessage(
        text: 'Deal. Thursday after school, or Saturday morning if you '
            'prefer it quieter.',
        fromMe: true,
        sentAt: '17:22',
      ),
    ],
  ),
  Conversation(
    id: 'c-1038',
    counterpartId: 't-liang',
    counterpartName: 'Liang Chen',
    counterpartRole: Role.tutor,
    subject: 'Calculus and Physics',
    status: RequestStatus.pending,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Interested in both subjects together if that works. I am free '
            'Tuesday and Friday evenings.',
        fromMe: true,
        sentAt: '19:10',
      ),
    ],
  ),
  Conversation(
    id: 'c-1030',
    counterpartId: 't-marcus',
    counterpartName: 'Marcus Bell',
    counterpartRole: Role.tutor,
    subject: 'Essay Writing',
    status: RequestStatus.declined,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'I know you are in person only — I could travel on Thursdays if '
            'that is possible.',
        fromMe: true,
        sentAt: '12:30',
      ),
      ChatMessage(
        text: 'Afraid not — my Thursdays filled up for the term. Rachel Osei '
            'does the same work online and she is good. Worth trying her.',
        fromMe: false,
        sentAt: '15:12',
      ),
    ],
  ),
];

/// A tutor's side. The counterpart is a student, `fromMe` is the tutor talking.
/// The two pending threads sit first: one waits on this side's answer, the
/// other on the student's.
const List<Conversation> sampleReceivedConversations = <Conversation>[
  Conversation(
    id: 'c-2009',
    counterpartId: 's-aisha',
    counterpartName: 'Aisha Rahman',
    counterpartRole: Role.student,
    subject: 'Statistics',
    status: RequestStatus.pending,
    requestedByMe: false,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Grade 8 predicted and I need a 9 for the course I want. I do '
            'not need the ideas explained again — I need speed under time '
            'pressure and fewer careless errors.',
        fromMe: false,
        sentAt: '18:47',
      ),
    ],
  ),
  Conversation(
    id: 'c-2012',
    counterpartId: 's-kai',
    counterpartName: 'Kai Nakamura',
    counterpartRole: Role.student,
    subject: 'Statistics',
    status: RequestStatus.pending,
    requestedByMe: true,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Your cycling data is the kind of project I like teaching '
            'against. Two evenings a week and we finish the analysis properly — '
            'starting with the parts that are already half-done. Interested?',
        fromMe: true,
        sentAt: '09:14',
      ),
    ],
  ),
  Conversation(
    id: 'c-2011',
    counterpartId: 's-maya',
    counterpartName: 'Maya Chen',
    counterpartRole: Role.student,
    subject: 'Calculus and Physics',
    status: RequestStatus.accepted,
    requestedByMe: false,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'Mock in eleven weeks. I can do weekday evenings after six, or '
            'Saturday morning if that is easier for you.',
        fromMe: false,
        sentAt: '18:04',
      ),
      ChatMessage(
        text: 'Yes — Tuesday and Thursday are free from next week. Send me '
            'your last mock paper and I will look at it before we start.',
        fromMe: true,
        sentAt: '20:12',
      ),
      ChatMessage(
        text: 'Sent it this morning. Question 7 is the one that keeps going '
            'wrong — I run out of time before the last part.',
        fromMe: false,
        sentAt: '07:41',
      ),
      ChatMessage(
        text: 'Read it. Your opening move is fine, the marks go in the last '
            'two lines. We will fix exactly that on Tuesday.',
        fromMe: true,
        sentAt: '08:15',
      ),
    ],
  ),
  Conversation(
    id: 'c-2003',
    counterpartId: 's-ethan',
    counterpartName: 'Ethan Brooks',
    counterpartRole: Role.student,
    subject: 'Calculus',
    status: RequestStatus.accepted,
    requestedByMe: false,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'I have one free morning a week and I would rather use two hours '
            'of it. I want the derivations, not shortcuts.',
        fromMe: false,
        sentAt: '10:02',
      ),
      ChatMessage(
        text: 'Then we take Saturdays. Bring the further maths book — we '
            'build each result from the definition up, nothing accepted on '
            'trust.',
        fromMe: true,
        sentAt: '10:31',
      ),
      ChatMessage(
        text: 'Perfect. Same time next week?',
        fromMe: false,
        sentAt: '10:40',
      ),
    ],
  ),
  Conversation(
    id: 'c-1998',
    counterpartId: 's-owen',
    counterpartName: 'Owen Pratt',
    counterpartRole: Role.student,
    subject: 'Algebra',
    status: RequestStatus.declined,
    requestedByMe: false,
    messages: <ChatMessage>[
      ChatMessage(
        text: 'I lost the thread somewhere in year 8 and nobody noticed. I '
            'would rather rebuild it than keep pretending. Weekday '
            'afternoons, in person if that works.',
        fromMe: false,
        sentAt: '17:15',
      ),
      ChatMessage(
        text: 'I teach online and my week is mostly evenings — Daniel Reyes '
            'teaches in Camden in the afternoons and would be the better fit.',
        fromMe: true,
        sentAt: '19:02',
      ),
    ],
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// The two profiles you land on if you skip onboarding
// ═════════════════════════════════════════════════════════════════════════════

/// The student you are if you open the app and skip the form. Chosen so the
/// default list has a clear top, a muddle in the middle and some honest bad
/// matches at the bottom — a real ranking, not a wall of 99s.
///
/// The details below are the ones an edit form can change: birthdate, where
/// they live, a status line, their year. The bio is deliberately empty, so the
/// completeness meter has something to count and the preview has something to
/// gain from being filled in.
final Profile demoStudentProfile = Profile(
  role: Role.student,
  name: 'Maya Chen',
  subjects: const <String>['Calculus', 'Physics', 'Algebra'],
  style: OnboardingOptions.studentStyles[0],
  mode: SessionMode.both,
  budget: 50,
  availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Wed-Eve', 'Thu-Eve', 'Sat-Morn']),
  goal: OnboardingOptions.studentGoals[1],
  birthdate: DateTime(2009, 3, 14),
  livesIn: 'Highbury, London',
  placeId: 'london-highbury',
  locationPrivacy: LocationPrivacy.cityOnly,
  statusText: 'Mocks in eleven weeks',
  presence: PresenceStatus.available,
  gender: 'Female',
  languages: const <String>['English', 'Mandarin'],
  grade: 'Year 12',
);

/// The tutor you are if you open the app and skip the form. Calibrated against
/// Amara Okonkwo's real availability, since her card is the landing specimen.
final Profile demoTutorProfile = Profile(
  role: Role.tutor,
  name: 'Amara Okonkwo',
  subjects: const <String>['Calculus', 'Statistics', 'Algebra'],
  style: OnboardingOptions.tutorStyles[0],
  mode: SessionMode.both,
  budget: 46,
  availability: avail(const <String>['Mon-Eve', 'Tue-Eve', 'Thu-Eve', 'Sat-Morn']),
  goal: OnboardingOptions.tutorGoals[0],
  birthdate: DateTime(1991, 6, 2),
  livesIn: 'Manchester',
  placeId: 'manchester-northern-quarter',
  locationPrivacy: LocationPrivacy.cityOnly,
  statusText: 'Open for sessions',
  presence: PresenceStatus.available,
  gender: 'Female',
  languages: const <String>['English', 'Igbo'],
  years: 9,
  education: 'MSc Mathematics, Manchester',
);

/// The pool row for [id], on either side. Screens that hold only an id — a
/// conversation, a request — look the person up here, so an avatar is drawn
/// from one place whatever the screen knows.
Candidate? candidateById(String id) {
  for (final List<Candidate> pool in <List<Candidate>>[sampleTutors, sampleStudents]) {
    for (final Candidate c in pool) {
      if (c.id == id) return c;
    }
  }
  return null;
}

/// The viewer's own profile, shaped as a pool row, so the person page can draw
/// it with the very same widgets it draws everybody else with — which is what
/// makes "preview how others see you" exact rather than a paraphrase. Nothing
/// here is a match: the fit numbers are zero and the notes are empty, because
/// no comparison produced them.
Candidate profileAsCandidate(Profile p) => Candidate(
      id: 'me',
      role: p.role,
      name: p.name,
      headline: '',
      subjects: p.subjects,
      styleLabel: p.style,
      styleTags: const <String>[],
      mode: p.mode,
      rate: p.budget,
      location: p.livesIn,
      livesIn: p.livesIn,
      placeId: p.placeId,
      locationPrivacy: p.locationPrivacy,
      birthdate: p.birthdate,
      statusText: p.statusText,
      presence: p.presence,
      gender: p.gender,
      years: p.years,
      grade: p.grade,
      goal: p.goal,
      rating: 0,
      reviews: 0,
      bio: p.bio,
      credentials: p.role == Role.tutor && p.education.trim().isNotEmpty
          ? <String>[p.education]
          : const <String>[],
      languages: p.languages,
      availability: p.availability,
      fitSubjects: 0,
      fitStyle: 0,
      fitFormat: 0,
      fitBudget: 0,
      notes: const <FitNote>[],
    );


/// The specimen shown on the landing page: the top-ranked tutor for the demo
/// student, scored live so the landing page cannot drift from the product.
MatchResult landingSpecimen() => rank(sampleTutors, demoStudentProfile).first;

int get poolSize => sampleTutors.length + sampleStudents.length + 2;
