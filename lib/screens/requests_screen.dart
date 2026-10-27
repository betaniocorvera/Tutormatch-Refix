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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/main.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_empty_state.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_motion.dart';
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
    final List<MatchRequest> inbox = state.requests;

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
        onPressed: () => Navigator.of(context).pushNamed(Routes.matches),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Your requests', style: AppType.pageTitle),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              '${inbox.length} requests: ${count(RequestStatus.pending)} waiting, '
              '${count(RequestStatus.accepted)} accepted, '
              '${count(RequestStatus.declined)} declined. Requests you sent and '
              'requests you received share this list; the quoted note says who '
              'wrote it.',
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
          AnimatedSize(
            duration: Motion.respect(context, Motion.page),
            curve: Motion.ease,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: Motion.respect(context, Motion.page),
              switchInCurve: Motion.ease,
              switchOutCurve: Motion.ease,
              layoutBuilder:
                  (Widget? currentChild, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (Widget child, Animation<double> animation) {
                if (Motion.reduced(context)) return child;
                final Animation<Offset> slide = Tween<Offset>(
                  begin: const Offset(0.018, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Motion.ease),
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<RequestStatus>(_tab),
                child: state.requestsLoading && inbox.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: Space.huge),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : state.requestsError != null && inbox.isEmpty
                        ? TMEmptyState(
                            headline: 'Requests could not load.',
                            body: state.requestsError!,
                            primaryLabel: 'Try again',
                            onPrimary: state.loadRequests,
                          )
                        : shown.isEmpty
                            ? _emptyFor(_tab, state.role == Role.student)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  for (int i = 0; i < shown.length; i++)
                                    ...<Widget>[
                                      if (i > 0)
                                        const SizedBox(height: Space.lg),
                                      TMReveal(
                                        key: ValueKey<String>(
                                          'request-${shown[i].id}',
                                        ),
                                        delay: Motion.stagger *
                                            (i < 5 ? i : 5),
                                        child: _RequestEntry(
                                          request: shown[i],
                                          photo: state
                                              .photoFor(shown[i].counterpartId),
                                          onOpenProfile: () => _openProfile(
                                            context,
                                            state,
                                            shown[i],
                                          ),
                                          onOpenConversation: () =>
                                              Navigator.of(context).pushNamed(
                                            Routes.chat,
                                            arguments:
                                                shown[i].conversationId,
                                          ),
                                        ),
                                      ),
                                    ],
                                ],
                              ),
              ),
            ),
          ),
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }

  /// Finds the counterpart in the pool so a request can lead back to the match
  /// that produced it. If they are not in the pool, the entry stays readable and
  /// simply has no link — better than a dead one.
  void _openProfile(BuildContext context, AppState state, MatchRequest request) {
    final MatchResult? hit = state.matchFor(request.counterpartId);
    if (hit == null) return;
    Navigator.of(context).pushNamed(Routes.matchDetail, arguments: hit);
  }

  Widget _emptyFor(RequestStatus tab, bool student) {
    final (String headline, String body) copy = switch (tab) {
      RequestStatus.pending => student
          ? (
              'Nothing is waiting on an answer.',
              'Requests you send from a match appear here and stay here until the '
                  'other side accepts or declines. Sending one creates the '
                  'conversation immediately; it stays read-only until they answer.',
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
          child: AnimatedContainer(
            duration: Motion.respect(context, Motion.fast),
            curve: Motion.ease,
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
    required this.photo,
    required this.onOpenProfile,
    required this.onOpenConversation,
  });

  final MatchRequest request;
  final Uint8List? photo;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenConversation;

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
              TMAvatar(
                request.counterpartName,
                size: 44,
                photo: photo,
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(request.counterpartName, style: AppType.name),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        // The reference belongs with the other facts about the
                        // request, not with the name: on a phone it was the
                        // thing that pushed a two-word name onto two lines.
                        Text(
                          request.reference,
                          style: AppType.micro.tone(AppColors.inkMuted),
                        ),
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
            attribution: request.outgoing
                ? 'You wrote'
                : '${request.counterpartName.split(' ').first} wrote',
            text: request.note,
            tone: StatusTone.neutral,
          ),
          if (request.reply != null) ...<Widget>[
            const SizedBox(height: Space.md),
            _Said(
              attribution: request.outgoing
                  ? '${request.counterpartName.split(' ').first} replied'
                  : 'You replied',
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
              TMButton(
                label: request.status == RequestStatus.accepted
                    ? 'Open conversation'
                    : request.outgoing
                        ? 'Open conversation'
                        : 'Answer in Messages',
                variant: TMButtonVariant.quiet,
                minHeight: Hit.min,
                onPressed: onOpenConversation,
              ),
              if (request.status == RequestStatus.pending && request.outgoing)
                TMTextLink(
                  label: 'Withdraw is not available yet',
                  style: AppType.bodySmall,
                  onTap: () => _explainWithdraw(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Withdrawing has no endpoint yet, and says so rather than pretending.
  void _explainWithdraw(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Withdrawing is not available yet. The request stays in Messages '
          'until the other person answers it.',
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
