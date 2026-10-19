// ─────────────────────────────────────────────────────────────────────────────
// Match detail.
//
// The screen that has to survive the question "why am I seeing this person?".
// Asymmetric: the person and the argument for them on the left, the score and
// the action in a well on the right, so the decision is never more than a glance
// away from the reasoning that produced it.
//
// Two decisions worth defending:
//
//   * The self-description is set in Spectral italic. It is a quotation — the
//     person talking about themselves — and it is the one place on an Operate
//     screen where the serif earns its keep.
//   * Sending a request confirms INLINE, in the panel that held the form. A
//     modal would interrupt, cover the reasons the person just read, and be
//     dismissed before it was understood. The form is replaced by its own
//     outcome, with a reference and the next step.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/availability_grid.dart';
import 'package:tutormatch/widgets/match_score_scale.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_field.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({required this.result, super.key});

  final MatchResult result;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  final TextEditingController _note = TextEditingController();
  bool _sent = false;
  String? _noteError;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Deterministic, and computed from the characters rather than from
  /// `String.hashCode`, which is seeded per run on the VM. The same person
  /// always produces the same reference here, so a screenshot can be checked
  /// against a second run of the app.
  String get _reference {
    int n = 0;
    for (final int unit in widget.result.candidate.id.codeUnits) {
      n = (n * 31 + unit) % 9000;
    }
    return 'TM-${n + 1000}';
  }

  void _send() {
    final String note = _note.text.trim();
    if (note.length < 12) {
      setState(() => _noteError = 'Add a little more: which day suits you, and '
          'what you want out of the first lesson. Notes like that get answered.');
      return;
    }
    setState(() {
      _noteError = null;
      _sent = true;
    });
    AppStateScope.read(context).lastRequestReference = _reference;
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool wide = TMLayout.isWide(context);

    // Re-scored against the profile as it stands now, so a detail screen opened
    // before an availability change is not showing last week's arithmetic.
    final MatchResult result = rank(state.pool, state.profile).firstWhere(
      (MatchResult r) => r.candidate.id == widget.result.candidate.id,
      orElse: () => widget.result,
    );
    final Candidate c = result.candidate;
    final String? when = describeOverlap(result.score.overlap);
    // The viewer's own side of the conversation: a student checks their outbox,
    // a tutor the requests they have received.
    final List<MatchRequest> inbox = state.role == Role.student
        ? sampleRequests
        : sampleReceivedRequests;
    final bool alreadyAsked = _sent ||
        inbox.any((MatchRequest r) =>
            r.counterpartId == c.id && r.status != RequestStatus.declined);

    final Widget person = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(c.name, style: AppType.pageTitle),
        const SizedBox(height: Space.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(c.headline, style: AppType.bodyLarge.quiet),
        ),
        const SizedBox(height: Space.lg),
        _FactLine(candidate: c),
        const SizedBox(height: Space.xxl),
        const TMRule(label: 'In their own words'),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text('“${c.bio}”', style: AppType.quote),
        ),
        const SizedBox(height: Space.xxl),
        _Credentials(candidate: c),
        const SizedBox(height: Space.xxl),
        const TMRule(label: 'Why you matched'),
        const SizedBox(height: Space.lg),
        for (int i = 0; i < result.reasons.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: Space.lg),
          _Reason(index: i + 1, note: result.reasons[i]),
        ],
        const SizedBox(height: Space.xxl),
        const TMRule(label: 'Where the hundred points come from'),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ScoreBreakdown(score: result.score),
        ),
        const SizedBox(height: Space.xxl),
        const TMRule(label: "When you're both free"),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AvailabilityGrid(
            overlap: result.score.overlap,
            you: state.profile.availability,
            them: c.availability,
            display: AvailabilityDisplay.comparison,
            cellHeight: 22,
          ),
        ),
        const SizedBox(height: Space.lg),
        const AvailabilityLegend(),
        const SizedBox(height: Space.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            when == null
                ? 'Your weeks do not cross at all. Requesting a lesson is still '
                    'possible, but expect to move something on your side first.'
                : '${result.score.overlapSlots} blocks a week line up — $when. '
                    'That is what the 25-point time score is measuring, block by block.',
            style: AppType.body.quiet,
          ),
        ),
      ],
    );

    final Widget aside = _ActionPanel(
      result: result,
      sent: _sent,
      alreadyAsked: alreadyAsked,
      student: state.role == Role.student,
      reference: _reference,
      note: _note,
      noteError: _noteError,
      onChanged: () => setState(() => _noteError = null),
      onSend: _send,
      fromProfile: state.profileAnswered,
      profileSummary: state.profileSummary,
    );

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'Matches',
          onTap: () => Navigator.of(context).pop(),
        ),
        TMNavItem(
          label: 'Requests',
          onTap: () => Navigator.of(context).pushNamed(Routes.requests),
        ),
        TMNavItem(
          label: 'Profile',
          onTap: () => Navigator.of(context).pushNamed(Routes.profile),
        ),
      ],
      navTrailing: TMButton(
        label: 'Back to the list',
        variant: TMButtonVariant.quiet,
        icon: TMIconName.arrowLeft,
        iconLeading: true,
        minHeight: Hit.min,
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: Space.xxl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 7, child: person),
                const SizedBox(width: Space.huge),
                SizedBox(width: TMLayout.asideWidth, child: aside),
              ],
            )
          else ...<Widget>[
            person,
            SizedBox(height: Space.xxxl),
            aside,
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _FactLine extends StatelessWidget {
  const _FactLine({required this.candidate});
  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          candidate.role == Role.tutor ? 'Tutor' : 'Student',
          style: AppType.bodySmall.tone(AppColors.inkMuted),
        ),
        Text('·', style: AppType.bodySmall.quieter),
        for (final String subject in candidate.subjects)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs + 1),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.ruleStrong),
              borderRadius: BorderRadius.circular(Radii.sharp - 1),
            ),
            child: Text(subject, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
          ),
        Text('·', style: AppType.bodySmall.quieter),
        Text(candidate.modeCopy, style: AppType.bodySmall.quieter),
        Text('·', style: AppType.bodySmall.quieter),
        Text(candidate.rateCopy, style: AppType.figure),
        Text('·', style: AppType.bodySmall.quieter),
        Text(candidate.location, style: AppType.bodySmall.quieter),
      ],
    );
  }
}

class _Credentials extends StatelessWidget {
  const _Credentials({required this.candidate});
  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xxxl,
      runSpacing: Space.xl,
      children: <Widget>[
        _Column(
          label: candidate.role == Role.tutor ? 'Works this way' : 'Wants this',
          value: '${candidate.styleLabel}\n${candidate.styleTags.join(' · ')}',
        ),
        _Column(
          label: candidate.role == Role.tutor ? 'Background' : 'Where they are',
          value: candidate.credentials.join('\n'),
        ),
        _Column(
          label: 'Speaks',
          value: candidate.languages.join(' · '),
        ),
        _Column(
          label: 'Reviews',
          value: candidate.reviews > 0
              ? '${candidate.rating} from ${candidate.reviews}'
              : 'No reviews yet — newer to the platform',
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 1, child: ColoredBox(color: AppColors.rule)),
          const SizedBox(height: Space.md),
          TMMicroLabelText(label),
          const SizedBox(height: Space.sm),
          Text(value, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.index, required this.note});
  final int index;
  final FitNote note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 26,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$index', style: AppType.micro.tone(AppColors.accent)),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(note.signal, style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(note.detail, style: AppType.bodySmall.quieter),
              ),
              const SizedBox(height: Space.xs),
              Text(note.dimension.label.toUpperCase(), style: AppType.micro.tone(AppColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The action panel
// ─────────────────────────────────────────────────────────────────────────────

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.result,
    required this.sent,
    required this.alreadyAsked,
    required this.student,
    required this.reference,
    required this.note,
    required this.noteError,
    required this.onChanged,
    required this.onSend,
    required this.fromProfile,
    required this.profileSummary,
  });

  final MatchResult result;
  final bool sent;
  final bool alreadyAsked;
  final bool student;
  final String reference;
  final TextEditingController note;
  final String? noteError;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final bool fromProfile;
  final String profileSummary;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      floating: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MatchScorePanel(
            score: result.score.total,
            trailing: TMStatusPill(tone: result.tier.tone, label: result.tier.label, dense: true),
          ),
          const SizedBox(height: Space.sm),
          Text(
            result.tier.meaning,
            style: AppType.bodySmall.quieter,
          ),
          if (fromProfile) ...<Widget>[
            const SizedBox(height: Space.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: Space.sm),
                  child: TMIcon(TMIconName.sliders, size: 13, color: AppColors.accent),
                ),
                Expanded(
                  child: Text(
                    'Based on your profile: $profileSummary',
                    style: AppType.bodySmall.tone(AppColors.inkSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.xl),
          const Divider(height: 1),
          const SizedBox(height: Space.xl),
          if (sent)
            _SentConfirmation(
              name: result.candidate.name,
              reference: reference,
              student: student,
              onOpenRequests: () =>
                  Navigator.of(context).pushNamed(Routes.requests),
            )
          else if (alreadyAsked)
            TMInlineNote(
              tone: StatusTone.pending,
              title: student
                  ? 'You have already asked ${result.candidate.name}.'
                  : '${result.candidate.name} has already asked you.',
              body: student
                  ? 'Their answer appears under Requests as soon as it comes in. '
                      'Sending a second request does not move you up the queue.'
                  : 'Their request is waiting under Requests, with the hours they '
                      'suggested. Read it there before you decide anything.',
              actions: <Widget>[
                TMButton(
                  label: student ? 'Open your requests' : 'Read their request',
                  variant: TMButtonVariant.secondary,
                  minHeight: Hit.min,
                  onPressed: () => Navigator.of(context).pushNamed(Routes.requests),
                ),
              ],
            )
          else
            _RequestForm(
              note: note,
              noteError: noteError,
              onChanged: onChanged,
              onSend: onSend,
              name: result.candidate.name,
              student: student,
            ),
        ],
      ),
    );
  }
}

class _RequestForm extends StatelessWidget {
  const _RequestForm({
    required this.note,
    required this.noteError,
    required this.onChanged,
    required this.onSend,
    required this.name,
    required this.student,
  });

  final TextEditingController note;
  final String? noteError;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final String name;
  final bool student;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMMicroLabelText(student ? 'Ask for a lesson' : 'Offer a lesson'),
        const SizedBox(height: Space.md),
        Text(
          student
              ? 'Say which of the shared hours you want and what the first lesson '
                  'should cover. Requests with a day and a goal in them get '
                  'answered; requests that say "hi" do not.'
              : 'Say which of the shared hours you can give and what the first '
                  'lesson would cover. Offers with a day and a plan in them get '
                  'answered; offers that say "hi" do not.',
          style: AppType.bodySmall.quieter,
        ),
        const SizedBox(height: Space.lg),
        _NoteField(
          controller: note,
          error: noteError,
          onChanged: onChanged,
          name: name,
          student: student,
        ),
        const SizedBox(height: Space.lg),
        TMButton(
          label: student ? 'Send the request' : 'Send the offer',
          expand: true,
          icon: TMIconName.arrowRight,
          onPressed: onSend,
        ),
        const SizedBox(height: Space.md),
        Text(
          'Nothing is emailed in this prototype — sending only changes this panel.',
          style: AppType.bodySmall.quieter,
        ),
      ],
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.name,
    required this.student,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;
  final String name;
  final bool student;

  @override
  Widget build(BuildContext context) {
    final String first = name.split(' ').first;
    return TMTextField(
      label: 'Your note',
      controller: controller,
      hint: student
          ? 'Hi $first — could we start Thursday evening? I have a mock in '
              'eleven weeks and the mechanics questions are where I lose marks.'
          : 'Hi $first — I can do Tuesday or Thursday after six. Bring the paper '
              'you mentioned and we will start with the questions that went wrong.',
      maxLines: 4,
      error: error,
      helper: error == null
          ? 'Between 12 and about 400 characters is the range that gets replies.'
          : null,
      // Typing retires the error: the message goes back to being a hint about
      // length, and the field's rule goes back to ink.
      onChanged: (_) => onChanged(),
    );
  }
}

class _SentConfirmation extends StatelessWidget {
  const _SentConfirmation({
    required this.name,
    required this.reference,
    required this.student,
    required this.onOpenRequests,
  });

  final String name;
  final String reference;
  final bool student;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMInlineNote(
          tone: StatusTone.accepted,
          title: 'Sent to $name.',
          body: student
              ? 'Reference $reference. They will accept or decline, and either '
                  'answer appears under Requests — you do not have to check back '
                  'here. Nothing was emailed: this is a prototype and the request '
                  'only exists in this tab.'
              : 'Reference $reference. They will accept or suggest another time. '
                  'Nothing was emailed: this is a prototype, and the offer only '
                  'exists in this panel.',
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          children: <Widget>[
            if (student)
              TMButton(
                label: 'Open your requests',
                variant: TMButtonVariant.secondary,
                icon: TMIconName.arrowRight,
                minHeight: Hit.min,
                onPressed: onOpenRequests,
              ),
            TMButton(
              label: 'Keep reading the list',
              variant: student ? TMButtonVariant.quiet : TMButtonVariant.secondary,
              minHeight: Hit.min,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
