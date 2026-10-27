# Matching

`GET /matches` is the recommender endpoint behind the existing Flutter match
list. It uses the same five weighted dimensions as the prototype, the same
0-100 score, the same tier thresholds, the same 21-cell availability grid, and
three plain-language reasons per result. The difference is that the ranking is
now computed from stored profiles and returned as JSON.

All matching endpoints require a bearer access token.

## Endpoint

```http
GET /matches
Authorization: Bearer <access token>
```

### Query parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `subjects` | repeated string | none | Keep candidates whose subjects include any selected subject. Canonical names or ids from `GET /subjects` only. |
| `mode` | `online`, `in_person`, `both` | none | Keep candidates whose format is compatible with this request. `both` accepts either format. |
| `max_rate` | integer 0-80 | none | Keep candidates whose stored `budget` is at or below this value. A tutor's budget is their hourly rate; a student's budget is their ceiling. |
| `required_parts` | repeated integer 0, 1, 2 | none | Keep candidates with at least one overlapping slot in that part of the day. `0` = mornings, `1` = afternoons, `2` = evenings. |
| `must_be_free_when_i_am` | boolean | `false` | Keep candidates with at least one shared weekly slot. |
| `max_distance_km` | integer | none | Keep candidates whose public distance is at or below this value. Candidates without a visible location on both sides are excluded. |
| `min_score` | integer 0-100 | none | Keep candidates at or above this score. |
| `limit` | integer 1-100 | `20` | Maximum results returned after ranking. |

Repeated parameters are sent in the usual query-string form:

```http
GET /matches?subjects=Calculus&subjects=Physics&mode=online&limit=10
```

An unknown subject is a `422` with a catalogue message. Other malformed query
values are rejected by FastAPI's normal validation, also with `422`.

### Response

The top-level counts distinguish the pool from the returned page:

- `pool_size`: eligible opposite-role candidates before query filters.
- `ranked_count`: candidates left after filters, before `limit`.
- `returned`: number of results in this response.

A condensed result:

```json
{
  "viewer_id": "student-id",
  "viewer_role": "student",
  "pool_size": 12,
  "ranked_count": 5,
  "returned": 2,
  "cold_start": null,
  "matches": [
    {
      "rank": 1,
      "profile": {
        "id": "tutor-id",
        "role": "tutor",
        "display_name": "Amara Okonkwo",
        "name": "Amara Okonkwo",
        "age": null,
        "photo_url": null,
        "public_location": {
          "label": "London",
          "city": "London",
          "region": "Greater London",
          "latitude": 51.5072,
          "longitude": -0.1276,
          "city_only": true
        },
        "distance_km": 0.0,
        "distance_text": "less than 1 km away",
        "subjects": ["Calculus", "Physics", "Algebra"],
        "style": "I work through examples slowly and let the student steer",
        "mode": "both",
        "budget": 46,
        "availability": [false, false, true, false, false, true, false, false, false, false, false, true, false, false, false, false, false, true, false, false, false],
        "goal": "Fill a few steady evenings a week"
      },
      "score": 95,
      "tier": "strong",
      "tier_label": "Strong match",
      "dimensions": {
        "subjects": {"score": 40, "max": 40},
        "time": {"score": 20, "max": 25},
        "style": {"score": 15, "max": 15},
        "format": {"score": 10, "max": 10},
        "budget": {"score": 10, "max": 10}
      },
      "overlap": [false, false, true, false, false, true, false, false, false, false, false, true, false, false, false, false, false, true, false, false, false],
      "overlap_slots": 4,
      "reasons": [
        {
          "dimension": "subjects",
          "label": "Subjects",
          "signal": "Calculus and Physics",
          "detail": "They cover every subject you asked for."
        },
        {
          "dimension": "time",
          "label": "Available time",
          "signal": "Monday, Tuesday, Thursday and Saturday evenings",
          "detail": "Both of you are free then, 4 hour-blocks that line up in a normal week."
        },
        {
          "dimension": "format",
          "label": "Nearby",
          "signal": "less than 1 km away",
          "detail": "Close enough that an in-person session would not turn into a journey."
        }
      ]
    }
  ]
}
```

`profile` is the same privacy-safe `PublicProfile` returned by
`GET /users/{id}`. The Flutter card's candidate fields therefore come from a
single projection rather than a second, match-specific shape.

## Eligibility: hard filters before KNN

A candidate is placed in the pool only when all of these are true:

1. They are not the signed-in user.
2. Their role is the opposite role: students see tutors, tutors see students.
3. They have completed the five matching answers: at least one subject, a
   style, at least one available slot, a goal, and a positive budget.

The `onboarding_complete` flag is not used as the source of truth. The answers
themselves are checked, so a stale flag cannot create a ghost match and a
complete set of answers is still matchable if a flag was never written.

Query filters are applied to this pool before the KNN query. They narrow the
ranking but never re-sort it: if two candidates were ranked A then B, and both
survive a filter, A remains ahead of B.

## The five weighted groups

| Dimension | Weight | What earns points |
| --- | ---: | --- |
| Subjects | 40 | The student's requested subjects covered by the tutor. |
| Available time | 25 | Shared weekly availability cells, capped at five. |
| Style | 15 | Distance between the two ordered style answers. |
| Format | 10 | Online / in person / either compatibility. |
| Budget | 10 | The tutor's rate against the student's ceiling. |

The total is the sum of the five integer dimension scores, so it is always an
integer from 0 to 100. The response repeats each dimension's score and maximum.

### Subjects: role-aware coverage

The student is always the side with the need. Let `needs` be the student's
subjects and `offers` be the tutor's subjects:

```text
overlap = |needs ∩ offers|
score   = round(40 * overlap / |needs|)
```

Extra tutor subjects do not hurt. A tutor who teaches the one subject a student
needs earns all 40 points even if the tutor also teaches three other subjects. A
student with three requested subjects and a tutor covering two earns
`round(40 * 2 / 3) = 27`.

The same formula is used when the viewer is a tutor: the candidate student is
the need side and the viewer's subjects are the offer side.

### Available time: the Flutter formula

```text
score = min(25, overlap_slots * 25 // 5)
```

So 0, 1, 2, 3, 4, and 5+ shared cells earn 0, 5, 10, 15, 20, and 25 points. The
overlap is the cell-by-cell AND of the two 21-cell grids, in day-major order.

### Style: ordered catalogue distance

The role-specific style catalogues are ordered from structured to exploratory.
Adjacent approaches are closer than opposite ones:

| Index distance | Points |
| ---: | ---: |
| 0 | 15 |
| 1 | 11 |
| 2 | 8 |
| 3 | 4 |
| 4 | 0 |

The formula is `round(15 * (1 - distance / 4))`.

### Format: compatibility, not preference similarity

```text
score = 10 when either side chose "both", or both chose the same mode
score = 0  when online meets in person and neither side is flexible
```

### Budget: the rate against the ceiling

A student's `budget` is their hourly ceiling. A tutor's `budget` is their hourly
rate. The rate is always the tutor's number, regardless of who is viewing.

```text
score = 10 when rate <= ceiling
score = max(0, round(10 * (1 - (rate - ceiling) / 20))) when rate > ceiling
```

A $20 gap loses the whole budget dimension. For example, with a $50 ceiling:

| Rate | Gap | Points |
| ---: | ---: | ---: |
| $46 | under | 10 |
| $52 | $2 | 9 |
| $58 | $8 | 6 |
| $60 | $10 | 5 |
| $70 | $20 | 0 |

## KNN and score conversion

For each candidate, the five group scores are converted into a five-dimensional
disagreement vector:

```text
coordinate[group] = sqrt(weight[group] - score[group])
viewer            = [0, 0, 0, 0, 0]
```

The vector is built after the hard filters, so KNN only sees candidates that
survived them. `NearestNeighbors` is fit with:

- `algorithm="brute"`
- `metric="euclidean"`
- `n_jobs=1`

Because the viewer is the origin, the squared Euclidean distance is exactly the
number of points the candidate did not earn:

```text
distance^2 = sum(weight - score)
           = 100 - total
score      = round(100 - distance^2)
           = total
```

This makes the KNN distance and the displayed score the same fact. Negative
distances are clamped to zero before conversion, and distances at or above 10
lose all points. The service still sorts by the converted score, with a
deterministic name and id tie-break for exact ties.

The candidate vectors are query-specific: they describe each candidate's
disagreement with this viewer, not a global embedding. That is intentional. The
five dimensions are already pairwise judgments (shared subjects, shared hours,
compatible format), so the disagreement space is the natural common ground for
the KNN query.

## Tiers

| Score | `tier` | `tier_label` |
| ---: | --- | --- |
| 80-100 | `strong` | Strong match |
| 60-79 | `good` | Good match |
| 40-59 | `possible` | Worth a look |
| 0-39 | `weak` | Long shot |

These are the prototype's thresholds and labels.

## Reasons

Each match returns exactly three reasons. They are the three dimensions with the
largest point contribution to this match's score, with ties broken by the
dimension order: subjects, time, style, format, budget. This keeps a 40-point
subject fit ahead of a 10-point format fit, which is how the score is actually
made.

When the two public locations are within 5 km, a third-slot note is inserted
with:

- `dimension: "format"` (the icon family used by the Flutter card)
- `label: "Nearby"`
- `signal: "about 3 km away"` or `"less than 1 km away"`

The nearby note takes the third slot, matching the existing presentation. A
candidate with a hidden location has `distance_km: null` and never receives a
nearby reason.

Reasons never reveal a hidden location, email address, birthdate, raw area id,
or any other private field. They only restate facts already present in the
public profile or the viewer's own answers.

## Cold start

A cold start is a normal `200` response with an empty `matches` array, not an
error.

```json
{
  "viewer_id": "student-id",
  "viewer_role": "student",
  "pool_size": 0,
  "ranked_count": 0,
  "returned": 0,
  "matches": [],
  "cold_start": {
    "reason": "profile_incomplete",
    "message": "Finish your matching answers to see people ranked for you.",
    "missing": ["subjects", "style", "availability", "goal", "budget"]
  }
}
```

There are two reasons:

- `profile_incomplete`: the viewer is missing one or more matching answers. The
  `missing` list uses stable keys in the order above.
- `no_candidates`: the viewer is complete, but no opposite-role person has a
  complete set of matching answers.

If the viewer and candidates are fine but query filters remove everyone,
`cold_start` is `null`; `pool_size` is greater than zero and `ranked_count` is
zero. That distinction lets the client show the filter-empty state rather than
the onboarding state.

## Privacy

The nested profile is the Phase 2 `PublicProfile` projection. It never contains:

- email address
- password hash
- birthdate
- raw `area_id`
- raw `lives_in`
- `onboarding_complete`
- profile completeness

Age is derived on the server. Public location is filtered by
`location_privacy`: `city_only` exposes the city centre, `area` exposes the
neighbourhood centre, and `hidden` exposes nothing. Distance is present only
when both viewer and candidate have a visible public location.

## Evaluation

`tests/test_matching_evaluation.py` runs a small hand-labelled precision@5
evaluation over `tests/data/matching_eval.json`:

- 3 viewer profiles: calculus/physics, humanities, and chemistry/biology/statistics.
- 18 tutor profiles with varied subjects, styles, formats, rates, availability,
  and locations.
- A tutor is labelled relevant for a viewer when it covers every requested
  subject, has a compatible format, is at or under the student's ceiling, and
  shares at least two weekly slots.

Style is deliberately excluded from the label so it can still cost a relevant
person points. The test computes precision@5 per viewer and requires both the
per-viewer score and the average to be at least `0.8`. The current fixture
contains 5 relevant tutors per viewer; the style mismatches and one strong
near-miss make the average less than perfect rather than a tautology.

Run it directly:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest tests/test_matching_evaluation.py -q
```

## Current limits

- Matching uses in-memory repositories. Swapping in PostgreSQL means
  implementing the existing repository interfaces; the engine itself does not
  know where profiles came from.
- There is no rating or review data in the backend yet. The Flutter prototype's
  sample ratings, review counts, style tags, and headlines are not fabricated
  by the matching endpoint; Phase 5 should render the stored public fields or
  add real profile fields before displaying those elements.
- Text search stays client-side. `GET /matches` returns the ranked list; the
  Flutter search field should debounce and filter that list without another
  ranking request.
- Requests, chat, and access control are Phase 4 concerns. A candidate remains
  matchable until that layer adds request-state filtering.
- The response is a single page capped by `limit`; there is no cursor
  pagination. The current pools are small enough for that to be the right
  trade-off.
