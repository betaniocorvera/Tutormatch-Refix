// ─────────────────────────────────────────────────────────────────────────────
// Requests.
//
// Three states, one list. The tab strip is a ruled index with counts in figures,
// because "Pending 3" is a fact and a bare word is not.
//
// The replanned request is shown as a quotation from the other person, and a
// decline is shown with their reason attached. A declined request that says why
// is more useful than an accepted one that says nothing, and the interface
// should not treat it as a failure state to be hidden.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_empty_state.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  RequestStatus _tab = RequestStatus.pending;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool student = state.role == Role.student;

    // A student reads the requests they sent; a tutor reads the ones students
    // sent them. Two static inboxes, one screen, because the tabs below are
    // states rather than directions.
    final List<MatchRequest> inbox =
        student ? sampleRequests : sampleReceivedRequests;

    int count(RequestStatus status) =>
        inbox.where((MatchRequest r) => r.status == status).length;

    final List<MatchRequest> shown = inbox
        .where((MatchRequest r) => r.status == _tab)
        .toList(growable: false);

    return TMPage(
      navItems: <TMNavItem>[
        TMNavItem(
          label: 'Matches',
          onTap: () => Navigator.of(context).pushNamed(Routes.matches),
        ),
        TMNavItem(label: 'Requests', selected: true),
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
        onPressed: () => Navigator.of(context).pushNamed(Routes.matches),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: Space.xxl),
          Text(
            student ? 'Requests you have sent' : 'Requests you have received',
            style: AppType.pageTitle,
          ),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              student
                  ? '${inbox.length} requests in this prototype: '
                      '${count(RequestStatus.pending)} still waiting, '
                      '${count(RequestStatus.accepted)} accepted, '
                      '${count(RequestStatus.declined)} rejected. Nothing here was '
                      'emailed anywhere.'
                  : 'Requests students have sent you. ${inbox.length} in this '
                      'prototype: ${count(RequestStatus.pending)} waiting on your '
                      'answer, ${count(RequestStatus.accepted)} accepted, '
                      '${count(RequestStatus.declined)} turned down.',
              style: AppType.bodyLarge.quiet,
            ),
          ),
          const SizedBox(height: Space.xxl),
          _Tabs(
            current: _tab,
            counts: <RequestStatus, int>{
              RequestStatus.pending: count(RequestStatus.pending),
              RequestStatus.accepted: count(RequestStatus.accepted),
              RequestStatus.declined: count(RequestStatus.declined),
            },
            onSelect: (RequestStatus s) => setState(() => _tab = s),
          ),
          const SizedBox(height: Space.xxl),
          if (shown.isEmpty)
            _emptyFor(_tab, student)
          else
            for (int i = 0; i < shown.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: Space.lg),
              _RequestEntry(
                request: shown[i],
                student: student,
                onOpenProfile: () => _openProfile(context, state, shown[i]),
              ),
            ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  /// Finds the counterpart in the pool so a request can lead back to the match
  /// that produced it. If they are not in the pool, the entry stays readable and
  /// simply has no link — better than a dead one.
  void _openProfile(BuildContext context, AppState state, MatchRequest request) {
    final List<MatchResult> ranked = rank(state.pool, state.profile);
    final Iterable<MatchResult> hit = ranked.where(
      (MatchResult r) => r.candidate.id == request.counterpartId,
    );
    if (hit.isEmpty) return;
    Navigator.of(context).pushNamed(Routes.matchDetail, arguments: hit.first);
  }

  Widget _emptyFor(RequestStatus tab, bool student) {
    final (String headline, String body) copy = switch (tab) {
      RequestStatus.pending => student
          ? (
              'Nothing is waiting on an answer.',
              'Requests you send from a match appear here and stay here until the '
                  'other side accepts or declines. In this prototype nothing is '
                  'actually sent, so send one from any match and it will show up '
                  'immediately.',
            )
          : (
              'Nothing is waiting on your answer.',
              'When a student asks you for lessons, their request and the hours '
                  'they can do land here. Sending an offer from any student in '
                  'your matches starts the same conversation from your side.',
            ),
      RequestStatus.accepted => student
          ? (
              'No accepted requests yet.',
              'When someone accepts, their answer and the times they suggested land '
                  'here. That is the point at which a lesson gets a date — the score '
                  'and the shared hours you already read are what you take into it.',
            )
          : (
              'No accepted requests yet.',
              'When you accept a request, the agreed time and what happens next '
                  'land here. The score and the shared hours are what you take '
                  'into that first lesson.',
            ),
      RequestStatus.declined => student
          ? (
              'Nothing has been turned down.',
              'Declines appear here with the reason the other person gave. Read them: '
                  'a decline usually names the one constraint that got in the way, '
                  'and that constraint is worth changing before you send the next '
                  'request.',
            )
          : (
              'Nothing has been turned down.',
              'Requests you decline stay here with your reason attached, so a '
                  'student is never left guessing why. That is worth more to them '
                  'than silence.',
            ),
    };

    return TMEmptyState(
      headline: copy.$1,
      body: copy.$2,
      primaryLabel: 'Go and read your matches',
      onPrimary: () => Navigator.of(context).pushNamed(Routes.matches),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.current,
    required this.counts,
    required this.onSelect,
  });

  final RequestStatus current;
  final Map<RequestStatus, int> counts;
  final ValueChanged<RequestStatus> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        children: <Widget>[
          // Equal thirds rather than intrinsic widths. Three labels of unequal
          // length set at their natural size need 332 px on the narrowest phone
          // this product supports, which is 12 px more than exists — and it gets
          // worse the moment somebody turns their text size up. Sharing the
          // width means the strip always fits and only an extreme label ever
          // shortens.
          for (final RequestStatus status in RequestStatus.values)
            Expanded(
              child: _Tab(
                status: status,
                count: counts[status] ?? 0,
                selected: status == current,
                onTap: () => onSelect(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.status,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final RequestStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(status.tone);

    return TMFocusable(
      onTap: onTap,
      semanticButton: false,
      semanticSelected: selected,
      semanticLabel: '${status.label}, $count',
      builder: (BuildContext context, TMState s) {
        return TMFocusRing(
          focused: s.focused,
          radius: 0,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: EdgeInsets.symmetric(
              horizontal: TMLayout.isCompact(context) ? Space.sm : Space.lg,
              vertical: Space.md,
            ),
            decoration: BoxDecoration(
              color: selected ? wash : (s.hovered ? AppColors.paperSunken : null),
              border: Border(
                bottom: BorderSide(
                  color: selected ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                // The word gives way, the figure never does: "3 waiting" with no
                // number is worse than a truncated word.
                Flexible(
                  child: Text(
                    status.label,
                    style: AppType.label
                        .tone(selected ? AppColors.ink : AppColors.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  '$count',
                  style: AppType.figure.tone(selected ? ink : AppColors.inkMuted),
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
// One request
// ─────────────────────────────────────────────────────────────────────────────

class _RequestEntry extends StatelessWidget {
  const _RequestEntry({
    required this.request,
    required this.student,
    required this.onOpenProfile,
  });

  final MatchRequest request;
  final bool student;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Flexible(
                          child: Text(request.counterpartName, style: AppType.name),
                        ),
                        const SizedBox(width: Space.sm),
                        Flexible(
                          child: Text(
                            '· ${request.id}',
                            style: AppType.micro.tone(AppColors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(request.subject, style: AppType.bodySmall.tone(AppColors.inkSecondary)),
                        Text('matched ${request.score}/100', style: AppType.figure.tone(AppColors.inkMuted)),
                        Text(request.sentOn, style: AppType.bodySmall.quieter),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              TMStatusPill(tone: request.status.tone, label: request.status.label),
            ],
          ),
          const SizedBox(height: Space.lg),
          _Said(
            attribution: student ? 'You wrote' : 'They wrote',
            text: request.note,
            tone: StatusTone.neutral,
          ),
          if (request.reply != null) ...<Widget>[
            const SizedBox(height: Space.md),
            _Said(
              attribution: student ? '${request.counterpartName.split(' ').first} replied' : 'You replied',
              text: request.reply!,
              tone: request.status.tone,
            ),
          ],
          const SizedBox(height: Space.lg),
          const Divider(height: 1),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TMButton(
                label: 'Open their profile',
                variant: TMButtonVariant.secondary,
                icon: TMIconName.arrowRight,
                minHeight: Hit.min,
                onPressed: onOpenProfile,
              ),
              if (request.status == RequestStatus.pending)
                student
                    ? TMTextLink(
                        label: 'Withdraw the request',
                        style: AppType.bodySmall,
                        onTap: () => _explainWithdraw(context),
                      )
                    : TMTextLink(
                        label: 'Accept or decline',
                        style: AppType.bodySmall,
                        onTap: () => _explainAnswer(context),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  /// Withdrawing is not implemented, and says so rather than pretending.
  void _explainWithdraw(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Withdrawing is not part of this prototype. In the real product it would '
          'remove the request and free the other person\'s slot.',
          style: AppType.bodySmall.tone(AppColors.onAccent),
        ),
      ),
    );
  }

  /// The tutor's side of the same stub. Answering is the one action a tutor
  /// would take from this screen, so it is named and then honestly declined —
  /// the mirror of withdrawing on the student side.
  void _explainAnswer(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Answering is not part of this prototype. In the real product this would '
          'accept or decline the request and send the shared hours back if it is a yes.',
          style: AppType.bodySmall.tone(AppColors.onAccent),
        ),
      ),
    );
  }
}

/// A quotation block. Used for the note that was sent and for the answer that
/// came back, so the two are visibly the same kind of thing.
class _Said extends StatelessWidget {
  const _Said({
    required this.attribution,
    required this.text,
    required this.tone,
  });

  final String attribution;
  final String text;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: wash,
        border: Border.all(color: tone == StatusTone.neutral ? AppColors.rule : ink),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TMMicroLabelText(attribution, color: tone == StatusTone.neutral ? AppColors.inkMuted : ink),
          const SizedBox(height: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              text,
              style: AppType.body.tone(
                tone == StatusTone.neutral ? AppColors.inkSecondary : ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
