// ─────────────────────────────────────────────────────────────────────────────
// The profile.
//
// Two registers on one page, and the split is deliberate.
//
// The five answers that decide the ranking are live controls, each editable
// where it is stated: a person who wonders "why am I seeing this tutor?" can
// change an answer and watch the list move. The sixth block, the goal, is
// deliberately outside the numbered list and labelled as not compared, because
// lying about what the algorithm uses is the one thing a matching product
// cannot afford to do.
//
// The details above them — picture, name, birthdate, where you live, status,
// bio, languages, and the answers only your side has — are a profile other
// people read. They are edited behind Edit/Save/Cancel because they are a
// form, not a dial: nothing in the ranking reads them, and the preview below
// shows exactly what a match page would draw.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/flip_card.dart';
import 'package:tutormatch/widgets/location_map.dart';
import 'package:tutormatch/widgets/person_profile.dart';
import 'package:tutormatch/widgets/tilt_card.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// True while the detail form is open. The five answers stay live below it —
  /// they are the ranking's input and were built that way — but the details
  /// are copied into the draft when editing begins and only reach app state on
  /// Save.
  bool _editing = false;

  /// The small in-page preview turns on its own axis; the full preview route
  /// stays exactly where it was, this is only a second reading beside the form.
  bool _previewFlipped = false;

  late final TextEditingController _name;
  late final TextEditingController _statusText;
  late final TextEditingController _bio;
  late final TextEditingController _years;
  late final TextEditingController _education;
  late final TextEditingController _grade;
  DateTime? _birthdate;
  PresenceStatus _presence = PresenceStatus.available;
  String _gender = Profile.noAnswer;
  final Set<String> _languages = <String>{};
  String? _nameError;

  /// The structured location while editing. The saved profile is untouched
  /// until Save, exactly like every other detail on this form.
  String _placeId = '';
  LocationPrivacy _locationPrivacy = LocationPrivacy.cityOnly;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _statusText = TextEditingController();
    _bio = TextEditingController();
    _years = TextEditingController();
    _education = TextEditingController();
    _grade = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _statusText.dispose();
    _bio.dispose();
    _years.dispose();
    _education.dispose();
    _grade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Profile p = state.profile;
    final bool wide = TMLayout.isWide(context);

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'Matches',
          onTap: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        TMNavItem(
          label: 'Requests',
          onTap: () => Navigator.of(context).pushNamed(Routes.requests),
        ),
        TMNavItem(
          label: 'Messages',
          onTap: () => Navigator.of(context).pushNamed(Routes.messages),
        ),
        TMNavItem(label: 'Profile', selected: true),
      ],
      navTrailing: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // The rail footer is 216 px wide after its padding: enough for the
          // action, not for a name and a role as well. Only show the account
          // line in the top bar, where there is room to read it.
          final bool showName =
              !constraints.hasBoundedWidth || constraints.maxWidth >= 320;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showName) ...<Widget>[
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      '${p.name} · ${p.role == Role.student ? 'Student' : 'Tutor'}',
                      style: AppType.bodySmall.quieter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
              ],
              TMButton(
                label: 'Sign out',
                variant: TMButtonVariant.quiet,
                minHeight: Hit.min,
                onPressed: () =>
                    Navigator.of(context)
                        .popUntil((Route<void> r) => r.isFirst),
              ),
            ],
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Your profile', style: AppType.pageTitle),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'Two halves of one page. Your picture and details are what other '
              'people read; the five answers below them are what the ranking '
              'reads, in the order they count. Change an answer and the list '
              'changes with it — nothing is sent anywhere until you ask for a '
              'lesson.',
              style: AppType.bodyLarge.quiet,
            ),
          ),
          const SizedBox(height: Space.xxl),
          TiltCard(
            maxTilt: 3,
            lift: 3,
            child: _identity(context, state),
          ),
          SizedBox(height: Space.band(TMLayout.widthOf(context))),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _details(context, state),
                      const SizedBox(height: Space.xxl),
                      _answers(context, state),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xxl),
                SizedBox(
                  width: TMLayout.asideWidth,
                  child: _aside(context, state),
                ),
              ],
            )
          else ...<Widget>[
            _details(context, state),
            const SizedBox(height: Space.xxl),
            _answers(context, state),
            SizedBox(height: Space.band(TMLayout.widthOf(context))),
            _aside(context, state),
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  // ── Who you are: the picture, the status, and what is missing ──────────────

  /// The profile the meter and the header read while editing: the saved one
  /// plus whatever the draft has changed so far. Nothing here reaches app
  /// state — Save does that.
  Profile _draft(Profile p) => p.copyWith(
    name: _editing ? _name.text : null,
    birthdate: _editing ? _birthdate : null,
    livesIn: _editing ? (placeById(_placeId)?.label ?? '') : null,
    placeId: _editing ? _placeId : null,
    locationPrivacy: _editing ? _locationPrivacy : null,
    statusText: _editing ? _statusText.text : null,
    presence: _editing ? _presence : null,
    bio: _editing ? _bio.text : null,
    gender: _editing ? _gender : null,
    languages: _editing ? _languages.toList() : null,
    years: _editing ? int.tryParse(_years.text.trim()) : null,
    clearYears: _editing && _years.text.trim().isEmpty,
    education: _editing ? _education.text : null,
    grade: _editing ? _grade.text : null,
  );

  Widget _identity(BuildContext context, AppState state) {
    final Profile p = _draft(state.profile);
    final List<(String, bool)> gaps = p.profileGaps(
      hasPicture: state.photo != null,
    );
    final int filled = gaps.where(((String, bool) gap) => gap.$2).length;
    final List<String> missing = <String>[
      for (final (String, bool) gap in gaps)
        if (!gap.$2) gap.$1,
    ];
    final String name = p.name.trim().isEmpty ? 'Your name' : p.name.trim();
    final List<String> meta = <String>[
      if (p.birthdate != null)
        '${ageOn(p.birthdate!, DateTime.now())} years old',
      if (p.publicPlace != null) p.publicPlace!.label,
    ];

    final bool compact = TMLayout.isCompact(context);

    return TMEntry(
      padding: EdgeInsets.all(compact ? Space.lg : Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AvatarControl(
                name: name,
                photo: state.photo,
                caption: state.photo == null ? 'Add a picture' : 'Change picture',
                onTap: _openPictureSheet,
              ),
              const SizedBox(width: Space.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(name, style: AppType.titleLarge),
                        Text(
                          p.role == Role.student ? 'Student' : 'Tutor',
                          style: AppType.micro.tone(AppColors.inkMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    PersonStatusLine(
                      presence: p.presence,
                      statusText: p.statusText,
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      meta.isEmpty
                          ? 'Add where you live and when you were born — people look for both before they write.'
                          : meta.join(' · '),
                      style: AppType.bodySmall.quieter,
                    ),
                    const SizedBox(height: Space.lg),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        const TMMicroLabelText('Profile completeness'),
                        Text(
                          '$filled of ${gaps.length}',
                          style: AppType.figure.tone(AppColors.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: _Track(
                        fraction: gaps.isEmpty ? 0 : filled / gaps.length,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        missing.isEmpty
                            ? 'Every field a profile can answer is answered.'
                            : 'Still missing: ${missing.join(', ')}.',
                        style: AppType.bodySmall.quieter,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            children: _actions(context, state),
          ),
        ],
      ),
    );
  }

  /// The one pair of buttons the edit mode swaps in place. Rendered here and
  /// again at the end of the form, because on a phone the form is taller than
  /// the screen and "Save" must not be a scroll away from the last field.
  List<Widget> _actions(BuildContext context, AppState state) => <Widget>[
    if (_editing) ...<Widget>[
      TMButton(
        label: 'Save changes',
        icon: TMIconName.check,
        onPressed: () => _save(state),
      ),
      TMButton(
        label: 'Cancel',
        variant: TMButtonVariant.quiet,
        onPressed: () => setState(() => _editing = false),
      ),
    ] else ...<Widget>[
      TMButton(
        label: 'Edit profile',
        variant: TMButtonVariant.secondary,
        onPressed: () => _beginEdit(state),
      ),
      TMButton(
        label: 'Preview how others see you',
        variant: TMButtonVariant.quiet,
        onPressed: () => Navigator.of(context).pushNamed(Routes.profilePreview),
      ),
    ],
  ];

  void _beginEdit(AppState state) {
    final Profile p = state.profile;
    _name.text = p.name;
    _placeId = p.placeId;
    _locationPrivacy = p.locationPrivacy;
    _statusText.text = p.statusText;
    _bio.text = p.bio;
    _years.text = p.years?.toString() ?? '';
    _education.text = p.education;
    _grade.text = p.grade;
    _birthdate = p.birthdate;
    _presence = p.presence;
    _gender = p.gender;
    _languages
      ..clear()
      ..addAll(p.languages);
    setState(() {
      _nameError = null;
      _editing = true;
    });
  }

  void _save(AppState state) {
    final String name = _name.text.trim();
    setState(() {
      _nameError = name.isEmpty
          ? 'A display name is required — it is the one thing every list and '
                'every message shows first.'
          : null;
    });
    if (_nameError != null) return;

    final Place? place = placeById(_placeId);
    state.profile = state.profile.copyWith(
      name: name,
      birthdate: _birthdate,
      livesIn: place?.label ?? '',
      placeId: place?.id ?? '',
      locationPrivacy: _locationPrivacy,
      statusText: _statusText.text.trim(),
      presence: _presence,
      bio: _bio.text.trim(),
      gender: _gender,
      languages: _languages.toList(),
      years: int.tryParse(_years.text.trim()),
      clearYears: _years.text.trim().isEmpty,
      education: _education.text.trim(),
      grade: _grade.text.trim(),
    );
    setState(() => _editing = false);
    _say('Profile updated');
  }

  /// The one snackbar on this screen. It reports what happened and says the
  /// thing worth knowing about it — that it happened in memory.
  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(text, style: AppType.bodySmall.tone(AppColors.onAccent)),
      ),
    );
  }

  Future<void> _openPictureSheet() async {
    final AppState state = AppStateScope.read(context);
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperRaised,
      builder: (BuildContext context) =>
          _PictureSheet(hasPicture: state.photo != null),
    );
    if (!mounted || choice == null) return;

    if (choice == 'remove') {
      state.photo = null;
      _say('Picture removed — the initials are back.');
      return;
    }

    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null || !mounted) return;
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      state.photo = bytes;
      _say('Picture set. It lives in memory only — nothing was uploaded.');
    } on Exception {
      // A browser with no file picker, or a cancelled permission: say so
      // rather than dying on a tap.
      if (!mounted) return;
      _say('This device would not open a picture picker.');
    }
  }

  Future<void> _pickBirthdate() async {
    final DateTime now = DateTime.now();
    final DateTime initial =
        _birthdate ?? DateTime(now.year - 18, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      // Nothing before this was ever a plausible answer, and nothing after
      // today is possible — the two bounds are the whole validation.
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'When were you born?',
    );
    if (picked == null || !mounted) return;
    setState(() => _birthdate = picked);
  }

  // ── The details other people read ──────────────────────────────────────────

  Widget _details(BuildContext context, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Profile details'),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.xl),
        if (_editing) ...<Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _form(context, state),
          ),
          const SizedBox(height: Space.xl),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            children: _actions(context, state),
          ),
        ] else
          _readOnly(context, state.profile),
      ],
    );
  }

  /// The details as they stand, grouped by the question they answer rather
  /// than printed as one long ledger. A field that has not been answered says so
  /// in the muted ink rather than showing nothing — the gap is information, and
  /// it is the same gap the meter above is counting.
  Widget _readOnly(BuildContext context, Profile p) {
    final bool tutor = p.role == Role.tutor;
    final PublicPlace? place = p.publicPlace;
    final List<(String, String?)> about = <(String, String?)>[
      (
        'Birthdate',
        p.birthdate == null
            ? null
            : '${describeDate(p.birthdate!)} · '
                  '${ageOn(p.birthdate!, DateTime.now())} years old',
      ),
      ('Gender', p.gender),
      ('Languages', p.languages.isEmpty ? null : p.languages.join(', ')),
    ];
    final List<(String, String?)> now = <(String, String?)>[
      (
        'Status',
        p.statusText.trim().isEmpty
            ? p.presence.label
            : '${p.presence.label} · ${p.statusText}',
      ),
    ];
    final List<(String, String?)> work = tutor
        ? <(String, String?)>[
            (
              'Years of experience',
              p.years == null ? null : '${p.years} years',
            ),
            ('Education', p.education),
          ]
        : <(String, String?)>[('Year level', p.grade)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailGroup(label: 'About you', rows: about),
        const SizedBox(height: Space.xl),
        _DetailGroup(label: 'Right now', rows: now),
        const SizedBox(height: Space.xl),
        _DetailGroup(label: tutor ? 'Teaching' : 'School', rows: work),
        if (place != null) ...<Widget>[
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              const TMMicroLabelText('Approximate area'),
              const SizedBox(width: Space.sm),
              TMIcon(
                TMIconName.pin,
                size: 13,
                color: AppColors.accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: Space.xs + 1),
              Flexible(
                child: Text(
                  place.label,
                  style: AppType.bodySmall.tone(AppColors.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LocationCard(
              place: place,
              height: 230,
              // The one map in the product that takes gestures. Everywhere
              // else a scroll or a tap must not become a pan.
              interactive: true,
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        _DetailGroup(
          label: 'Bio',
          rows: const <(String, String?)>[],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              p.bio.trim().isEmpty
                  ? 'No bio yet — a couple of lines about how you like to work '
                        'is the thing people read before they write to you.'
                  : '“${p.bio}”',
              style: p.bio.trim().isEmpty
                  ? AppType.bodyLarge.quieter
                  : AppType.quote,
            ),
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, AppState state) {
    final bool tutor = state.profile.role == Role.tutor;
    // Every text field rebuilds the block as it is typed in, because the
    // completeness meter above counts the draft, not the saved profile.
    void touched(String _) => setState(() {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMTextField(
          label: 'Display name',
          controller: _name,
          error: _nameError,
          reason:
              'Shown on every list and message you appear in. Not compared '
              'against anybody.',
          onChanged: (String _) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            } else {
              setState(() {});
            }
          },
        ),
        const SizedBox(height: Space.xl),
        _DateField(
          label: 'Birthdate',
          value: _birthdate,
          reason:
              'Shown as your age, and nothing else — it is never part of '
              'the ranking.',
          onTap: _pickBirthdate,
        ),
        const SizedBox(height: Space.xl),
        // Shared by both roles. Where you live is a fact about the person, not
        // a student fact or a tutor fact, so this deliberately sits outside the
        // role-specific fields below.
        _LocationFields(
          placeId: _placeId,
          privacy: _locationPrivacy,
          onPlaceChanged: (String id) => setState(() => _placeId = id),
          onPrivacyChanged: (LocationPrivacy privacy) =>
              setState(() => _locationPrivacy = privacy),
        ),
        const SizedBox(height: Space.xl),
        const TMFieldLabel(
          label: 'Availability',
          reason:
              'Whether now is a good time. Shown beside your status line, '
              'and read by nothing else.',
        ),
        const SizedBox(height: Space.sm),
        TMSegmented<PresenceStatus>(
          options: PresenceStatus.values,
          selected: _presence,
          onSelect: (PresenceStatus v) => setState(() => _presence = v),
          labelOf: (PresenceStatus v) => v.label,
        ),
        const SizedBox(height: Space.xl),
        TMTextField(
          label: 'Status',
          controller: _statusText,
          hint: 'Open for sessions',
          reason:
              'One short line about what you are up to — "Mocks in eleven '
              'weeks", "Evenings and weekends".',
          onChanged: touched,
        ),
        const SizedBox(height: Space.xl),
        TMTextField(
          label: 'Bio',
          controller: _bio,
          maxLines: 5,
          hint: 'What you are like to work with, and what you are working on.',
          reason:
              'Set in italics on your profile, as a quotation — so write it '
              'in your own voice.',
          onChanged: touched,
        ),
        const SizedBox(height: Space.xl),
        const TMFieldLabel(
          label: 'Gender',
          reason:
              'Optional. "Prefer not to say" is a complete answer; it is '
              'simply not printed on your profile.',
        ),
        const SizedBox(height: Space.sm),
        TMChoiceList<String>(
          options: OnboardingOptions.genders,
          selected: _gender,
          onSelect: (String g) => setState(() => _gender = g),
          labelOf: (String g) => g,
        ),
        const SizedBox(height: Space.xl),
        const TMFieldLabel(
          label: 'Languages',
          reason: 'Everything you can hold a lesson in.',
        ),
        const SizedBox(height: Space.sm),
        TMTagPicker(
          options: OnboardingOptions.languages,
          selected: _languages,
          onToggle: (String language) => setState(() {
            if (!_languages.remove(language)) _languages.add(language);
          }),
        ),
        const SizedBox(height: Space.xl),
        if (tutor) ...<Widget>[
          TMTextField(
            label: 'Years of experience',
            controller: _years,
            hint: '9',
            keyboardType: TextInputType.number,
            reason: 'Counting from your first paid lesson. Digits only.',
            onChanged: touched,
          ),
          const SizedBox(height: Space.xl),
          TMTextField(
            label: 'Education',
            controller: _education,
            hint: 'MSc Mathematics, Manchester',
            reason:
                'The one line a student checks first. Degrees, teaching '
                'qualifications, or neither.',
            onChanged: touched,
          ),
        ] else
          TMTextField(
            label: 'Year level',
            controller: _grade,
            hint: 'Year 12',
            reason: 'Your school year right now, as your school states it.',
            onChanged: touched,
          ),
      ],
    );
  }

  // ── The five answers, in weight order ──────────────────────────────────────

  Widget _answers(BuildContext context, AppState state) {
    final Profile p = state.profile;
    final bool student = p.role == Role.student;
    final List<String> styles = student
        ? OnboardingOptions.studentStyles
        : OnboardingOptions.tutorStyles;
    final List<String> goals = student
        ? OnboardingOptions.studentGoals
        : OnboardingOptions.tutorGoals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('What the ranking uses'),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),

        const SizedBox(height: Space.xl),
        _Answer(
          number: 1,
          title: MatchDimension.subjects.label,
          note:
              '${MatchDimension.subjects.max} of 100 points. '
              '${MatchDimension.subjects.explainer}',
          child: TMTagPicker(
            options: OnboardingOptions.subjects,
            selected: p.subjects.toSet(),
            max: 4,
            maxReachedNote:
                'Four is the limit here. A shorter list ranks you '
                'better than a long one: the recommender reads every subject you '
                'add as something you actually want to be taught.',
            onToggle: (String s) {
              final Set<String> next = <String>{...p.subjects};
              if (!next.remove(s)) next.add(s);
              state.profile = p.copyWith(subjects: next.toList());
            },
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 2,
          title: MatchDimension.time.label,
          note:
              '${MatchDimension.time.max} of 100 points, worked out cell by '
              'cell against the other person\'s week — so this is the answer '
              'that moves the list most when you change it.',
          child: AvailabilityEditor(
            value: p.availability,
            onChanged: (List<bool> next) =>
                state.profile = p.copyWith(availability: next),
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 3,
          title: MatchDimension.style.label,
          note:
              '${MatchDimension.style.max} of 100 points. '
              '${MatchDimension.style.explainer}',
          child: _Disclosure(
            summary: p.style,
            openLabel: 'Pick a different answer',
            closeLabel: 'Keep it as it is',
            child: TMChoiceList<String>(
              options: styles,
              selected: p.style,
              onSelect: (String s) => state.profile = p.copyWith(style: s),
              labelOf: (String s) => s,
            ),
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 4,
          title: MatchDimension.format.label,
          note:
              '${MatchDimension.format.max} of 100 points. '
              '${MatchDimension.format.explainer}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMSegmented<SessionMode>(
                options: const <SessionMode>[
                  SessionMode.online,
                  SessionMode.inPerson,
                  SessionMode.both,
                ],
                selected: p.mode,
                onSelect: (SessionMode m) =>
                    state.profile = p.copyWith(mode: m),
                labelOf: (SessionMode m) => m.label,
              ),
              const SizedBox(height: Space.sm),
              Text(
                p.mode == SessionMode.both
                    ? 'Both sides of the list are open to you. Every tutor who '
                          'teaches online counts, and so does the one who only '
                          'teaches in a room.'
                    : 'People who teach ${p.mode.counterLabel} still rank, they '
                          'just lose the ${MatchDimension.format.max} points this '
                          'dimension is worth — which is why they sort lower '
                          'instead of disappearing.',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: 5,
          title: MatchDimension.budget.label,
          note:
              '${MatchDimension.budget.max} of 100 points. '
              '${MatchDimension.budget.explainer}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMBudgetScale(
                value: p.budget,
                onChanged: (int v) => state.profile = p.copyWith(budget: v),
              ),
              const SizedBox(height: Space.sm),
              Text(
                student
                    ? 'A ceiling, not a target. ${p.budget >= 80 ? 'Set to any price, so cost stops counting.' : 'Anyone above \$${p.budget} an hour still appears — the reason line says by how much.'}'
                    : 'Your going rate. Students whose ceiling is below it still '
                          'appear, with the gap stated as one of their reasons.',
                style: AppType.bodySmall.quieter,
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.xxl),
        _Answer(
          number: null,
          title: 'What you want out of it',
          note:
              'Not one of the five. Nothing above changes because of this — it '
              'is here so that whoever reads your request knows what you are '
              'aiming at before they answer it.',
          child: _Disclosure(
            summary: p.goal,
            openLabel: 'Pick a different answer',
            closeLabel: 'Keep it as it is',
            child: TMChoiceList<String>(
              options: goals,
              selected: p.goal,
              onSelect: (String g) => state.profile = p.copyWith(goal: g),
              labelOf: (String g) => g,
            ),
          ),
        ),
      ],
    );
  }

  // ── Account and the way back to the list ───────────────────────────────────

  Widget _aside(BuildContext context, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Your account'),
        const SizedBox(height: Space.md),
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        Text(
          'Your name, picture and details are edited above, behind Edit '
          'profile — they are what other people read.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xl),

        // A second reading of the same profile, in the column where the
        // account facts live. The button above still opens the full preview.
        const TMMicroLabelText('Two readings'),
        const SizedBox(height: Space.md),
        _ProfileFlipPreview(
          profile: _draft(state.profile),
          photo: state.photo,
          flipped: _previewFlipped,
          onFlip: () => setState(() => _previewFlipped = !_previewFlipped),
        ),
        const SizedBox(height: Space.xxl),

        // The role is an account fact rather than a preference: it is chosen
        // when you register and decides whose list you see from then on. A line
        // rather than a control, because there is nothing here to change.
        const TMMicroLabelText('Account type'),
        const SizedBox(height: Space.sm),
        Text(
          state.role == Role.student ? 'Student' : 'Tutor',
          style: AppType.body.tone(AppColors.inkSecondary),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Fixed at registration. It decides whose list you see and the '
          'questions your profile asks.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xxl),

        TMButton(
          label: 'Rank again with these answers',
          icon: TMIconName.arrowRight,
          expand: true,
          onPressed: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'The ranking uses your answers the moment you change them. This takes '
          'you to the result — ${state.pool.length} '
          '${state.role == Role.student ? 'tutors' : 'students'} in the pool.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.xxl),

        const TMInlineNote(
          tone: StatusTone.neutral,
          title: 'None of this is saved',
          body:
              'TutorMatch is an interface prototype with no accounts behind '
              'it. The answers above live in memory for as long as this tab is '
              'open, and reloading puts you back to the sample profile. Nothing '
              'is sent to a server, because there is no server.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One numbered answer
// ─────────────────────────────────────────────────────────────────────────────

/// The place picker and its public preview.
///
/// Three dependent fields over the built-in gazetteer, then the map those
/// choices produce. The preview always centres on the chosen neighbourhood so
/// the person can see what they picked; the privacy setting decides what other
/// people get to see, and the sentence underneath says exactly that.
class _LocationFields extends StatelessWidget {
  const _LocationFields({
    required this.placeId,
    required this.privacy,
    required this.onPlaceChanged,
    required this.onPrivacyChanged,
  });

  final String placeId;
  final LocationPrivacy privacy;
  final ValueChanged<String> onPlaceChanged;
  final ValueChanged<LocationPrivacy> onPrivacyChanged;

  @override
  Widget build(BuildContext context) {
    final Place? place = placeById(placeId);
    final City? city = place?.city;
    final List<String> regions =
        sampleCities.map((City c) => c.region).toSet().toList()..sort();
    final List<City> cities = city == null
        ? const <City>[]
        : sampleCities
              .where((City c) => c.region == city.region)
              .toList(growable: false);
    final List<Place> places = city == null
        ? const <Place>[]
        : samplePlaces
              .where((Place p) => p.city.name == city.name)
              .toList(growable: false);

    final Widget cityField = TMDropdown<City>(
      key: const Key('place-city'),
      label: 'City / municipality',
      value: city,
      options: cities,
      enabled: cities.isNotEmpty,
      hint: 'Choose a city',
      labelOf: (City c) => c.name,
      onChanged: (City next) {
        final Place first = samplePlaces.firstWhere(
          (Place p) => p.city.name == next.name,
        );
        onPlaceChanged(first.id);
      },
    );

    final Widget areaField = TMDropdown<Place>(
      key: const Key('place-area'),
      label: 'Barangay / area',
      value: place,
      options: places,
      enabled: places.isNotEmpty,
      hint: 'Choose an area',
      labelOf: (Place p) => p.name,
      onChanged: (Place next) => onPlaceChanged(next.id),
    );

    // This is the owner's preview, so it is centred on the chosen area and
    // does not depend on the privacy setting. When no area has been chosen yet
    // the map still appears, centred on the catalogue's default place, with a
    // caption that asks for one. Privacy governs what other people see; it
    // never removes this map.
    final Place mapPlace = place ?? samplePlaces.first;
    final bool hasPlace = place != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const TMMicroLabelText('Lives in'),
        const SizedBox(height: Space.md),
        TMDropdown<String>(
          key: const Key('place-region'),
          label: 'Province / region',
          value: city?.region,
          options: regions,
          hint: 'Choose a province or region',
          reason:
              'The built-in list is small and offline on purpose: this is a '
              'prototype, not an address lookup.',
          labelOf: (String region) => region,
          onChanged: (String region) {
            final City firstCity = sampleCities.firstWhere(
              (City c) => c.region == region,
            );
            final Place firstPlace = samplePlaces.firstWhere(
              (Place p) => p.city.name == firstCity.name,
            );
            onPlaceChanged(firstPlace.id);
          },
        ),
        const SizedBox(height: Space.lg),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth >= 420) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: cityField),
                  const SizedBox(width: Space.md),
                  Expanded(child: areaField),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                cityField,
                const SizedBox(height: Space.lg),
                areaField,
              ],
            );
          },
        ),
        const SizedBox(height: Space.lg),
        LocationMap(
          centerLatitude: mapPlace.latitude,
          centerLongitude: mapPlace.longitude,
          height: 190,
          caption: hasPlace ? mapPlace.label : 'Choose your area',
          captionNote: hasPlace
              ? switch (privacy) {
                  LocationPrivacy.area => 'visible to others',
                  LocationPrivacy.cityOnly => 'others see the city',
                  LocationPrivacy.hidden => 'preview only',
                }
              : null,
          fallbackTitle: hasPlace ? mapPlace.label : 'Choose your area',
          semanticLabel: hasPlace
              ? 'Map preview of ${mapPlace.label}. ${privacy.explanation}'
              : 'Map preview centred on a default place. Choose your area.',
        ),
        const SizedBox(height: Space.sm),
        Text(
          !hasPlace
              ? 'Choose a region, city and area to set the centre of this '
                    'preview.'
              : switch (privacy) {
                  LocationPrivacy.area =>
                    'Others will see ${mapPlace.label} and a circle of about '
                        '1–2 km.',
                  LocationPrivacy.cityOnly =>
                    'Others will see ${mapPlace.city.name} and a circle around '
                        'its centre — not ${mapPlace.name}.',
                  LocationPrivacy.hidden =>
                    'This preview is only for you. Others will see no map, no '
                        'area and no distance.',
                },
          style: AppType.bodySmall.tone(AppColors.inkSecondary),
        ),
        const SizedBox(height: Space.xl),
        const TMFieldLabel(
          label: 'Location privacy',
          reason:
              'This is the only control that decides what other people see. '
              'It never changes your saved area.',
        ),
        const SizedBox(height: Space.sm),
        TMChoiceList<LocationPrivacy>(
          options: LocationPrivacy.values,
          selected: privacy,
          onSelect: onPrivacyChanged,
          labelOf: (LocationPrivacy value) => value.label,
        ),
        const SizedBox(height: Space.sm),
        Text(privacy.explanation, style: AppType.bodySmall.quieter),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.only(left: Space.md),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: TMIcon(
                  TMIconName.pin,
                  size: 14,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Only your approximate area is shown to others. Your exact '
                  'address is never shared.',
                  style: AppType.bodySmall.tone(AppColors.inkSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    required this.number,
    required this.title,
    required this.note,
    required this.child,
  });

  /// The position in the ranking's order of weight. Null for the answer that is
  /// not compared, which is marked with a rule instead of a figure.
  final int? number;
  final String title;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On a phone the number moves into the label rather than eating a gutter
    // out of the week grid, where every pixel is a 44 px tap target.
    final bool compact = TMLayout.isCompact(context);
    final String label = number == null
        ? title
        : compact
        ? '$number. $title'
        : title;

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
        const SizedBox(height: Space.lg),
        TMMicroLabelText(
          label,
          color: number == null ? AppColors.inkMuted : AppColors.inkSecondary,
        ),
        const SizedBox(height: Space.lg),
        child,
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(note, style: AppType.bodySmall.quieter),
        ),
      ],
    );

    if (compact || number == null) return body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: Space.lg - 2),
            child: Text(
              '$number',
              style: AppType.figure.tone(AppColors.inkMuted),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The disclosure
// ─────────────────────────────────────────────────────────────────────────────

/// The current answer, quoted, with the full choice list behind one link.
///
/// Style and goal are answered in whole sentences, and five sentences take a
/// screenful. Keeping them closed means the recap of the five answers stays the
/// dominant thing on this page — but the sentences are still the real control,
/// one tap away, not a summary that hides what was actually chosen.
class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.summary,
    required this.openLabel,
    required this.closeLabel,
    required this.child,
  });

  final String summary;
  final String openLabel;
  final String closeLabel;
  final Widget child;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text('“${widget.summary}”', style: AppType.quote),
        ),
        const SizedBox(height: Space.sm),
        _DisclosureLink(
          label: _open ? widget.closeLabel : widget.openLabel,
          open: _open,
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.lg),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Local rather than shared: this is the only link in the product whose mark
/// turns, because it is the only one where the mark's angle *is* the state.
class _DisclosureLink extends StatelessWidget {
  const _DisclosureLink({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticLabel: label,
      builder: (BuildContext context, TMState s) {
        final Color ink = s.hovered || s.focused
            ? AppColors.accent
            : AppColors.ink;
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodySmall
                        .tone(ink)
                        .copyWith(
                          decoration: s.hovered || s.focused
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: ink,
                          decorationThickness: 1.2,
                        ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                TMRotatingIcon(
                  TMIconName.chevronDown,
                  turns: open ? 0.5 : 0,
                  size: 15,
                  color: ink,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The picture, the meter and the details
// ─────────────────────────────────────────────────────────────────────────────

/// The profile picture and the one way to change it. The square itself is the
/// ordinary shared avatar — it draws the in-memory picture, or the initials
/// when there is none — and the caption under it is what makes the tap
/// discoverable, because a square of initials does not advertise itself as a
/// button.
class _AvatarControl extends StatelessWidget {
  const _AvatarControl({
    required this.name,
    required this.photo,
    required this.caption,
    required this.onTap,
  });

  final String name;
  final Uint8List? photo;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticLabel: 'Profile picture — $caption',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TMAvatar(name, size: 88, photo: photo),
            const SizedBox(height: Space.sm),
            Text(
              caption,
              style: AppType.bodySmall.tone(
                s.hovered || s.focused ? AppColors.accent : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The profile seen two ways, small enough to sit in the account column.
///
/// It is the same two readings the full preview screen offers: the page as it
/// was written, and the first glance a ranked list gives it. It turns on the
/// same vertical axis, in the same 500 ms, and never mirrors its own back face.
class _ProfileFlipPreview extends StatelessWidget {
  const _ProfileFlipPreview({
    required this.profile,
    required this.photo,
    required this.flipped,
    required this.onFlip,
  });

  final Profile profile;
  final Uint8List? photo;
  final bool flipped;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final String name = profile.name.trim().isEmpty
        ? 'Your name'
        : profile.name.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 248,
          child: FlipCard(
            flipped: flipped,
            onTap: onFlip,
            front: _MiniFace(
              label: 'As written',
              icon: TMIconName.eye,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TMAvatar(name, size: 44, photo: photo),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              name,
                              style: AppType.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            PersonStatusLine(
                              presence: profile.presence,
                              statusText: profile.statusText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Expanded(
                    child: Text(
                      profile.bio.trim().isEmpty
                          ? 'No bio yet. A couple of lines about how you work '
                                'is the thing people read before they write.'
                          : '“${profile.bio}”',
                      style: profile.bio.trim().isEmpty
                          ? AppType.bodySmall.quieter
                          : AppType.quote.copyWith(fontSize: 14),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  const SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppColors.rule),
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.md,
                    runSpacing: Space.xs,
                    children: <Widget>[
                      if (profile.publicPlace != null)
                        _MiniFact(
                          icon: TMIconName.pin,
                          text: profile.publicPlace!.city,
                        ),
                      _MiniFact(
                        icon: TMIconName.graduation,
                        text: profile.role == Role.student
                            ? 'Student'
                            : 'Tutor',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            back: _MiniFace(
              label: 'First glance',
              icon: TMIconName.sparkle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: AppType.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(
                    profile.role == Role.tutor
                        ? (profile.education.trim().isEmpty
                              ? profile.style
                              : profile.education)
                        : (profile.grade.trim().isEmpty
                              ? profile.style
                              : '${profile.grade} · ${profile.style}'),
                    style: AppType.bodySmall.quieter,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: <Widget>[
                      for (final String subject in profile.subjects.take(3))
                        _MiniChip(subject),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppColors.rule),
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.md,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _MiniFact(
                        icon: TMIconName.wallet,
                        text: profile.role == Role.student
                            ? 'up to \$${profile.budget}'
                            : '\$${profile.budget}/hr',
                      ),
                      _MiniFact(
                        icon: TMIconName.compass,
                        text: profile.mode.label,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        TMFocusable(
          onTap: onFlip,
          semanticLabel: flipped
              ? 'Show the profile as written'
              : 'Show the first-glance card',
          semanticButton: false,
          builder: (BuildContext context, TMState s) => TMFocusRing(
            focused: s.focused,
            radius: Radii.sharp,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: <Widget>[
                  TMIcon(
                    TMIconName.refresh,
                    size: 13,
                    color: s.hovered || s.focused
                        ? AppColors.accent
                        : AppColors.inkMuted,
                  ),
                  const SizedBox(width: Space.xs + 2),
                  Expanded(
                    child: Text(
                      flipped
                          ? 'Showing the first glance. Turn it back.'
                          : 'Showing the page. Turn it to a card.',
                      style: AppType.bodySmall.tone(
                        s.hovered || s.focused
                            ? AppColors.accent
                            : AppColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniFace extends StatelessWidget {
  const _MiniFace({
    required this.label,
    required this.icon,
    required this.child,
  });

  final String label;
  final TMIconName icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TMMicroLabelText(label),
              const Spacer(),
              TMIcon(icon, size: 12, color: AppColors.inkMuted),
            ],
          ),
          const SizedBox(height: Space.md),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.icon, required this.text});

  final TMIconName icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TMIcon(icon, size: 12, color: AppColors.inkMuted),
        const SizedBox(width: Space.xs + 1),
        Text(
          text,
          style: AppType.bodySmall.tone(AppColors.inkSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ruleStrong),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: AppType.micro.copyWith(fontSize: 9.5).tone(AppColors.inkSecondary),
      ),
    );
  }
}

/// A measured fraction of a rule: the completeness meter. It fills once, on
/// arrival, over the hairline the rest of the page is drawn with — the same
/// kind of measured arrival as the match ring.
class _Track extends StatelessWidget {
  const _Track({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final double target = fraction.clamp(0.0, 1.0);
    return Semantics(
      label: 'Profile completeness ${(target * 100).round()} percent',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: Motion.respect(context, const Duration(milliseconds: 620)),
        curve: Motion.emphasized,
        builder: (BuildContext context, double value, Widget? child) {
          return SizedBox(
            height: 3,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.rule,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Container(
                      height: 2,
                      width: constraints.maxWidth * value,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    if (value > 0)
                      Positioned(
                        left: (constraints.maxWidth * value - 3).clamp(
                          0.0,
                          constraints.maxWidth - 6,
                        ),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// A labelled group of detail rows. The label is the question the rows answer,
/// so the read-only profile scans as three short sections rather than one
/// undifferentiated table.
class _DetailGroup extends StatelessWidget {
  const _DetailGroup({required this.label, required this.rows, this.child});

  final String label;
  final List<(String, String?)> rows;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMMicroLabelText(label),
        const SizedBox(height: Space.sm),
        if (rows.isNotEmpty) _Details(rows: rows),
        ?child,
      ],
    );
  }
}

/// Label-and-value rows, ruled between. A field that has not been answered
/// reads "Not set" in the muted ink: the gap is information, and it is the
/// same gap the meter is counting.
class _Details extends StatelessWidget {
  const _Details({required this.rows});

  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0)
            const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 150, child: TMMicroLabelText(rows[i].$1)),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    rows[i].$2 == null || rows[i].$2!.trim().isEmpty
                        ? 'Not set'
                        : rows[i].$2!.trim(),
                    style: AppType.body.tone(
                      rows[i].$2 == null || rows[i].$2!.trim().isEmpty
                          ? AppColors.inkMuted
                          : AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A date, chosen from the calendar rather than typed into a box. Built from
/// the same label and the same ruled surface as [TMTextField], so a date field
/// between two text fields reads as one of them — but it opens the one control
/// that makes an impossible date impossible to enter.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.reason,
  });

  final String label;
  final DateTime? value;
  final String? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMFieldLabel(label: label, reason: reason),
        const SizedBox(height: Space.sm),
        TMFocusable(
          onTap: onTap,
          semanticLabel: value == null
              ? '$label, not set. Choose a date.'
              : '$label, ${describeDate(value!)}. Change it.',
          builder: (BuildContext context, TMState s) => TMFocusRing(
            focused: s.focused,
            radius: Radii.sharp,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              constraints: const BoxConstraints(minHeight: Hit.min),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.paperRaised,
                borderRadius: Radii.sharpAll,
                border: Border.all(
                  color: s.focused ? AppColors.ink : AppColors.ruleStrong,
                  width: s.focused ? 2 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      value == null ? 'Choose a date' : describeDate(value!),
                      style: AppType.body.tone(
                        value == null ? AppColors.inkMuted : AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (value != null) ...<Widget>[
                    Text(
                      '${ageOn(value!, now)} years old',
                      style: AppType.bodySmall.quieter,
                    ),
                    const SizedBox(width: Space.md),
                  ],
                  const TMIcon(
                    TMIconName.chevronDown,
                    size: 18,
                    color: AppColors.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The picture sheet: choose, remove, or leave it. A line says where the
/// picture actually lives, because "no server" is the sort of thing this
/// product says out loud rather than leaving a person to guess.
class _PictureSheet extends StatelessWidget {
  const _PictureSheet({required this.hasPicture});

  final bool hasPicture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const TMMicroLabelText('Profile picture'),
              const SizedBox(height: Space.md),
              const SizedBox(
                height: 1,
                child: ColoredBox(color: AppColors.rule),
              ),
              const SizedBox(height: Space.lg),
              Text(
                'Pick a picture from this device. It is held in memory for as '
                'long as this tab is open and sent nowhere — there is no server '
                'to send it to.',
                style: AppType.bodySmall.quieter,
              ),
              const SizedBox(height: Space.lg),
              TMButton(
                label: hasPicture ? 'Change picture' : 'Choose a picture',
                expand: true,
                onPressed: () => Navigator.pop<String>(context, 'choose'),
              ),
              if (hasPicture) ...<Widget>[
                const SizedBox(height: Space.sm),
                TMButton(
                  label: 'Remove picture',
                  variant: TMButtonVariant.secondary,
                  expand: true,
                  onPressed: () => Navigator.pop<String>(context, 'remove'),
                ),
              ],
              const SizedBox(height: Space.sm),
              TMButton(
                label: 'Cancel',
                variant: TMButtonVariant.quiet,
                expand: true,
                onPressed: () => Navigator.pop<String>(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
