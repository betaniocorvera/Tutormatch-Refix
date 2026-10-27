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
//   * The self-description is a quotation — the person talking about themselves
//     — set in the body face's italic, indented by a rule rather than wrapped
//     in a decorative card.
//   * Sending a request confirms INLINE, in the panel that held the form. A
//     modal would interrupt, cover the reasons the person just read, and be
//     dismissed before it was understood. The form is replaced by its own
//     outcome, with a reference and the next step.
//
// On a phone the decision is never a scroll away: a pinned bar carries the score
// and the next action, and the full form lives where the reasons end.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
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
  final GlobalKey _actionKey = GlobalKey();
  bool _sent = false;
  String? _noteError;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _scrollToAction() {
    final BuildContext? target = _actionKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: Motion.respect(context, Motion.page),
      curve: Motion.ease,
      alignment: 0.04,
    );
  }

  bool _busy = false;

  String _referenceFor(String id) {
    final String compact = id.replaceAll('-', '').toUpperCase();
    final String tail =
        compact.length > 6 ? compact.substring(compact.length - 6) : compact;
    return 'TM-$tail';
  }

  Future<void> _send() async {
    final String note = _note.text.trim();
    if (note.length < 12) {
      setState(() => _noteError = 'Add a little more: which day suits you, and '
          'what you want out of the first lesson. Notes like that get answered.');
      return;
    }
    final AppState state = AppStateScope.read(context);
    final String? subject = state.sharedSubjectFor(widget.result.candidate);
    if (subject == null) {
      setState(() => _noteError =
          'You do not share a subject with this person yet. Add one of their '
          'subjects to your profile before sending a request.');
      return;
    }
    setState(() {
      _noteError = null;
      _busy = true;
    });
    try {
      final MatchRequest request = await state.createRequest(
        candidate: widget.result.candidate,
        subject: subject,
        note: note,
      );
      if (!mounted) return;
      state.lastRequestReference = _referenceFor(request.id);
      setState(() => _sent = true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _noteError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    final MatchResult result =
        state.matchFor(widget.result.candidate.id) ?? widget.result;
    final Candidate c = result.candidate;
    final String? when = describeOverlap(result.score.overlap);
    final Conversation? chat = _chatWith(state, c.id);
    final MatchRequest? request = state.requestWith(c.id);
    final bool alreadyAsked = _sent ||
        (request != null && request.status != RequestStatus.declined) ||
        chat != null;
    final String reference = state.lastRequestReference ??
        (request == null ? '' : _referenceFor(request.id));

    final Widget person = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The person block is shared with the profile preview, so the page a
        // tutor opens for a student and the page a student previews are the
        // same page — fields and all — rather than two drawings of one idea.
        PersonSummary(
          person: c,
          distanceKm: result.distanceKm,
          heroTag: 'avatar-${c.id}',
          // The shared week below the reasons is the pairing's week. Drawing the
          // person's own week here as well would show two grids of the same
          // seven days and invite the reader to compare the wrong pair.
          showAvailability: false,
        ),
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
      reference: reference,
      note: _note,
      noteError: _noteError,
      busy: _busy,
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
      bottomBar: _DecisionBar(
        score: result.score.total,
        sent: _sent,
        alreadyAsked: alreadyAsked,
        askedByMe: chat?.requestedByMe ?? state.role == Role.student,
        chat: chat,
        student: state.role == Role.student,
        onStartRequest: _scrollToAction,
        onOpenMessages: () => Navigator.of(context).pushNamed(Routes.messages),
        onOpenRequests: () => Navigator.of(context).pushNamed(Routes.requests),
      ),
      // The decision panel becomes the shell's sticky aside: beside the
      // argument from 1120 px, after it below. That keeps the score and the
      // request within reach without pinning a wall over a phone.
      aside: KeyedSubtree(key: _actionKey, child: aside),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          person,
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
// The pinned decision
// ─────────────────────────────────────────────────────────────────────────────

/// A phone-sized bar above the navigation. It carries the one number and the
/// one next action, so the decision never depends on a scroll. The full request
/// form still lives in the panel; this only takes you to it.
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({
    required this.score,
    required this.sent,
    required this.alreadyAsked,
    required this.askedByMe,
    required this.chat,
    required this.student,
    required this.onStartRequest,
    required this.onOpenMessages,
    required this.onOpenRequests,
  });

  final int score;
  final bool sent;
  final bool alreadyAsked;
  final bool askedByMe;
  final Conversation? chat;
  final bool student;
  final VoidCallback onStartRequest;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final Widget action;
    if (sent) {
      action = TMButton(
        label: 'Open your messages',
        icon: TMIconName.arrowRight,
        minHeight: Hit.min,
        expand: true,
        onPressed: onOpenMessages,
      );
    } else if (alreadyAsked) {
      final bool useMessages = chat != null;
      action = TMButton(
        label: askedByMe
            ? (useMessages ? 'Open messages' : 'Open requests')
            : (useMessages ? 'Answer in Messages' : 'Read their request'),
        variant: TMButtonVariant.secondary,
        icon: TMIconName.arrowRight,
        minHeight: Hit.min,
        expand: true,
        onPressed: useMessages ? onOpenMessages : onOpenRequests,
      );
    } else {
      action = TMButton(
        label: student ? 'Ask for a lesson' : 'Offer a lesson',
        icon: TMIconName.arrowRight,
        minHeight: Hit.min,
        expand: true,
        onPressed: onStartRequest,
      );
    }

    return Row(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$score', style: AppType.scoreSmall),
            Text('MATCH', style: AppType.micro.copyWith(fontSize: 8.5).quieter),
          ],
        ),
        const SizedBox(width: Space.lg),
        Expanded(child: action),
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
    required this.busy,
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
  final bool busy;
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
    // With a live conversation the answer lives in Messages; a request that has
    // no conversation yet still points at Requests.
    final String destination = chat == null ? Routes.requests : Routes.messages;
    final String name = result.candidate.name;

    return TMEntry(
      floating: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const TMMicroLabelText('The match'),
          const SizedBox(height: Space.md),
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
              busy: busy,
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
    required this.busy,
    required this.onChanged,
    required this.onSend,
    required this.name,
    required this.student,
  });

  final TextEditingController note;
  final String? noteError;
  final bool busy;
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
          busy: busy,
          busyLabel: 'Sending the request…',
          onPressed: busy ? null : onSend,
        ),
        const SizedBox(height: Space.md),
        Text(
          'The request is saved to your account and appears in Messages. Nothing is emailed.',
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
          body: 'Reference $reference. The request is waiting in Requests — the '
              'chat opens in Messages the moment they accept it. Nothing was '
              'emailed; the request is stored on the TutorMatch server.',
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
