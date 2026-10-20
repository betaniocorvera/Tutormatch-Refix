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
import 'package:tutormatch/widgets/person_profile.dart';
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
    final AppState state = AppStateScope.read(context);
    state.lastRequestReference = _reference;
    // The request is also a conversation from this moment on: pending, so the
    // chat is locked until the other side accepts it.
    state.startConversation(widget.result.candidate, note: note);
  }

  /// The live conversation with this person, once a request has turned into
  /// one. Declined conversations do not count — asking again is allowed.
  Conversation? _chatWith(AppState state, String id) {
    for (final Conversation chat in state.conversations) {
      if (chat.counterpartId == id && chat.status != RequestStatus.declined) {
        return chat;
      }
    }
    return null;
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
    // The viewer's own side of the conversation: either a student's list of
    // tutors or a tutor's list of students — whichever it is, it holds both
    // requests sent and requests received.
    final List<MatchRequest> inbox = state.role == Role.student
        ? sampleRequests
        : sampleReceivedRequests;
    // A request sent from here becomes a conversation in the same breath, so
    // the conversation list is the honest check for "already asked": the static
    // inbox cannot see what was sent a minute ago.
    final Conversation? chat = _chatWith(state, c.id);
    final bool alreadyAsked = _sent ||
        chat != null ||
        inbox.any((MatchRequest r) =>
            r.counterpartId == c.id && r.status != RequestStatus.declined);

    final Widget person = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The person block is shared with the profile preview, so the page a
        // tutor opens for a student and the page a student previews are the
        // same page — fields and all — rather than two drawings of one idea.
        PersonSummary(person: c, distanceKm: result.distanceKm),
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
      chat: chat,
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
          label: 'Messages',
          onTap: () => Navigator.of(context).pushNamed(Routes.messages),
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
              Text(note.dimensionLabel.toUpperCase(), style: AppType.micro.tone(AppColors.inkMuted)),
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
    required this.chat,
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

  /// The student's live conversation with this person, when there is one.
  final Conversation? chat;
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
    // Who asked is a fact about the conversation when there is one; without a
    // live conversation the static inbox says it — a student's list is their
    // outbox, a tutor's is what arrived.
    final bool askedByMe = chat?.requestedByMe ?? student;
    // With a live conversation the answer lives in Messages; a static sample
    // request has no conversation behind it and still points at Requests.
    final String destination = chat == null ? Routes.requests : Routes.messages;
    final String name = result.candidate.name;

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
              name: name,
              reference: reference,
              onOpenMessages: () =>
                  Navigator.of(context).pushNamed(Routes.messages),
            )
          else if (alreadyAsked)
            TMInlineNote(
              tone: StatusTone.pending,
              title: askedByMe
                  ? 'You have already asked $name.'
                  : '$name has already asked you.',
              body: askedByMe
                  ? chat == null
                      ? 'Their answer appears under Requests as soon as it comes '
                          'in. Sending a second request does not move you up the '
                          'queue.'
                      : chat!.status == RequestStatus.accepted
                          ? 'You are already talking in Messages — open the '
                              'conversation there to carry on where you left off.'
                          : 'The request is waiting in Messages. Open the '
                              'conversation there — the chat opens the moment they '
                              'accept it.'
                  : chat == null
                      ? 'Their request is waiting under Requests, with the hours '
                          'they suggested. Read it there before you decide '
                          'anything.'
                      : 'Their request is waiting in your Messages, with the '
                          'hours they suggested. Answer it there — accepting '
                          'opens the chat for both sides.',
              actions: <Widget>[
                TMButton(
                  label: askedByMe
                      ? (chat == null ? 'Open your requests' : 'Open your messages')
                      : (chat == null ? 'Read their request' : 'Answer it in Messages'),
                  variant: TMButtonVariant.secondary,
                  minHeight: Hit.min,
                  onPressed: () => Navigator.of(context).pushNamed(destination),
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
          label: 'Send request',
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
    required this.onOpenMessages,
  });

  final String name;
  final String reference;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TMInlineNote(
          tone: StatusTone.accepted,
          title: 'Sent to $name.',
          body: 'Reference $reference. The request is waiting in Messages — the '
              'chat opens there the moment they accept it. Nothing was emailed: '
              'this is a prototype, and the request only exists inside it.',
        ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          children: <Widget>[
            TMButton(
              label: 'Open your messages',
              variant: TMButtonVariant.secondary,
              icon: TMIconName.arrowRight,
              minHeight: Hit.min,
              onPressed: onOpenMessages,
            ),
            TMButton(
              label: 'Keep reading the list',
              variant: TMButtonVariant.quiet,
              minHeight: Hit.min,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
