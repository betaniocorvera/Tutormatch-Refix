# TutorMatch A.I.

## What it is

A tutor/student matching interface. Both sides fill in a short profile — subjects,
style, weekly availability, online or in person, budget — and receive a ranked
list of counterparts with a match score, three plain-language reasons, and the
concrete hours they are both free.

## Product truth

- **Mechanism:** K-Nearest Neighbours over a numeric profile vector. Five
  dimensions carry weight: subjects (40), available time (25), teaching/learning
  style (15), online vs in person (10), budget (10). The score is the weighted
  agreement, 0–100.
- **Audience:** a secondary-school or early-university student who needs help in
  specific subjects, and a tutor who wants a handful of well-fitting students
  rather than a marketplace of strangers.
- **The scene:** a student at a kitchen table in the afternoon, laptop open,
  comparing three names before messaging one. A tutor between lessons, phone in
  hand, deciding which two requests to answer. Both are in daylight, in a hurry,
  and sceptical of a score they cannot interrogate.
- **What has to be believed:** the ranking is inspectable. Every score can be
  opened and resolved into reasons a person can argue with. Nothing is a black
  box, and nothing is hidden behind a "learn more".

## Scope

UI only. No auth, no persistence, no network, no KNN. Every value on screen comes
from `lib/data/mock_data.dart`, which is labelled as sample data in the file and
designed so a real ranking service can replace it field for field. Onboarding
answers live in memory and are gone on reload.

## Explicit constraints

- Web-first, responsive to 360 px.
- Keep the code simple and free of heavy packages.
- No purple-to-blue gradient hero, no glassmorphism, no emoji as icons, no
  "Welcome to the future of learning", no identical rounded-card grids, no
  centred-everything, no lorem ipsum, no three-column icon feature row.

## Brand commitments

Set below in DESIGN.md. One line: warm paper, one ink-red accent, a serif that
speaks and a sans that works.
