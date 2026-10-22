// ─────────────────────────────────────────────────────────────────────────────
// Messages.
//
// An inbox with two different jobs. Requests waiting on this side sit at the top
// as decision cards — accept or decline, with the answer attached — because they
// are the only thing on the screen that cannot wait. Everything else is a
// conversation list: one surface, hairline rows, and the latest line from the
// other side marked with a single green dot.
//
// Reading is local presentation only. The conversation model has no read flag,
// so "unread" means "their last message is still the newest thing here and this
// session has not opened it". Opening, accepting or declining clears the dot.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
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

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// Conversations opened in this session. Presentation only — nothing is
  /// written back to the model, and a reload begins with the same dots.
  final Set<String> _opened = <String>{};

  bool _unread(Conversation c) {
    final ChatMessage? last = c.lastMessage;
    return last != null &&
        !last.fromMe &&
        c.status != RequestStatus.declined &&
        !_opened.contains(c.id);
  }

  void _open(Conversation c) {
    setState(() => _opened.add(c.id));
    Navigator.of(context).pushNamed(Routes.chat, arguments: c.id);
  }

  void _accept(AppState state, Conversation c) {
    setState(() => _opened.add(c.id));
    state.acceptConversation(c.id);
  }

  void _decline(AppState state, Conversation c) {
    setState(() => _opened.add(c.id));
    state.declineConversation(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool student = state.role == Role.student;
    final List<Conversation> chats = state.conversations;

    int count(RequestStatus status) =>
        chats.where((Conversation c) => c.status == status).length;

    // The decision belongs to the side that received the request.
    bool awaitingMe(Conversation c) =>
        c.status == RequestStatus.pending && !c.requestedByMe;
    final List<Conversation> requests =
        chats.where(awaitingMe).toList(growable: false);
    final List<Conversation> threads =
        chats.where((Conversation c) => !awaitingMe(c)).toList(growable: false);
    final int unread = chats.where(_unread).length;
    final int waitingTheirs =
        count(RequestStatus.pending) - requests.length;

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
        TMNavItem(label: 'Messages', selected: true),
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
          _InboxHeading(
            unread: unread,
            total: chats.length,
            student: student,
          ),
          const SizedBox(height: Space.xl),
          _InboxMeter(
            open: count(RequestStatus.accepted),
            yours: requests.length,
            theirs: waitingTheirs,
            closed: count(RequestStatus.declined),
          ),
          const SizedBox(height: Space.xxl),
          if (chats.isEmpty)
            TMEmptyState(
              headline: 'No conversations yet.',
              body: student
                  ? 'A conversation appears here the moment a request is sent — '
                      'yours to a tutor, or a tutor\'s to you — and it stays '
                      'locked until the side that received it answers.'
                  : 'A conversation appears here the moment a request is sent — '
                      'a student\'s to you, or yours to a student — and it stays '
                      'locked until the side that received it answers.',
              primaryLabel: 'Go and read your matches',
              onPrimary: () => Navigator.of(context).pushNamed(Routes.matches),
            )
          else ...<Widget>[
            _SectionHead(
              index: '01',
              title: 'Needs your answer',
              count: requests.length,
              note: requests.isEmpty
                  ? 'Nothing is waiting on you. New requests land here before '
                      'they become conversations.'
                  : 'Accepting opens the thread for both sides. Declining closes '
                      'it with your answer still on it.',
            ),
            const SizedBox(height: Space.lg),
            if (requests.isEmpty)
              const _InlineEmpty(
                icon: TMIconName.check,
                title: 'You are caught up.',
                body: 'Requests you receive will land here with the hours and the '
                    'note attached, so the answer can be made in one place.',
              )
            else
              for (int i = 0; i < requests.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: Space.md),
                TMReveal(
                  key: ValueKey<String>('request-${requests[i].id}'),
                  delay: Motion.stagger * (i < 4 ? i : 4),
                  child: _RequestEntry(
                    conversation: requests[i],
                    unread: _unread(requests[i]),
                    onOpen: () => _open(requests[i]),
                    onAccept: () => _accept(state, requests[i]),
                    onDecline: () => _decline(state, requests[i]),
                  ),
                ),
              ],
            const SizedBox(height: Space.xxl),
            _SectionHead(
              index: '02',
              title: 'Conversations',
              count: threads.length,
              note: threads.isEmpty
                  ? 'No thread is open yet.'
                  : '${count(RequestStatus.accepted)} open · '
                      '${threads.where(_unread).length} with a line you have not '
                      'opened · ${count(RequestStatus.declined)} closed.',
            ),
            const SizedBox(height: Space.lg),
            if (threads.isEmpty)
              const _InlineEmpty(
                icon: TMIconName.chats,
                title: 'No conversations open yet.',
                body: 'Accept a request above and the thread opens here for both '
                    'sides, with the hours and the note already in it.',
              )
            else
              TMReveal(
                duration: const Duration(milliseconds: 460),
                child: _ThreadList(
                  conversations: threads,
                  unread: _unread,
                  onOpen: _open,
                ),
              ),
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Heading and index
// ─────────────────────────────────────────────────────────────────────────────

class _InboxHeading extends StatelessWidget {
  const _InboxHeading({
    required this.unread,
    required this.total,
    required this.student,
  });

  final int unread;
  final int total;
  final bool student;

  @override
  Widget build(BuildContext context) {
    final Widget badge = AnimatedSwitcher(
      duration: Motion.respect(context, Motion.base),
      switchInCurve: Motion.ease,
      switchOutCurve: Motion.ease,
      child: unread == 0
          ? const SizedBox(key: ValueKey<String>('no-unread'))
          : Container(
              key: ValueKey<String>('unread-$unread'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm - 1,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentWash,
                border: Border.all(color: AppColors.accent),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    '$unread unread',
                    style: AppType.micro.tone(AppColors.accent),
                  ),
                ],
              ),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[Text('Messages', style: AppType.pageTitle), badge],
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Every request becomes a conversation here — student to tutor, or '
            'tutor to student. A thread stays locked until the side that '
            'received it answers.',
            style: AppType.bodyLarge.quiet,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          '$total in this prototype',
          style: AppType.micro.tone(AppColors.inkMuted),
        ),
      ],
    );
  }
}

class _InboxMeter extends StatelessWidget {
  const _InboxMeter({
    required this.open,
    required this.yours,
    required this.theirs,
    required this.closed,
  });

  final int open;
  final int yours;
  final int theirs;
  final int closed;

  String _figure(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final List<Widget> metrics = <Widget>[
      _Metric(
        figure: _figure(open),
        label: 'Open',
        tone: StatusTone.accepted,
      ),
      _Metric(
        figure: _figure(yours),
        label: 'Needs you',
        tone: StatusTone.pending,
        lead: true,
      ),
      _Metric(
        figure: _figure(theirs),
        label: 'Waiting',
        tone: StatusTone.neutral,
      ),
      _Metric(
        figure: _figure(closed),
        label: 'Closed',
        tone: StatusTone.declined,
      ),
    ];

    return TMEntry(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool tight = constraints.maxWidth < 560;
          if (!tight) {
            return Row(
              children: <Widget>[
                for (int i = 0; i < metrics.length; i++) ...<Widget>[
                  if (i > 0) const _MeterRule(),
                  Expanded(child: metrics[i]),
                ],
              ],
            );
          }
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: metrics[0]),
                  const _MeterRule(),
                  Expanded(child: metrics[1]),
                ],
              ),
              const Divider(height: 1),
              Row(
                children: <Widget>[
                  Expanded(child: metrics[2]),
                  const _MeterRule(),
                  Expanded(child: metrics[3]),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MeterRule extends StatelessWidget {
  const _MeterRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: AppColors.rule,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.figure,
    required this.label,
    required this.tone,
    this.lead = false,
  });

  final String figure;
  final String label;
  final StatusTone tone;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = AppColors.statusTint(tone);
    final Color value = lead ? AppColors.ink : AppColors.inkSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (lead)
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(right: Space.md),
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(figure, style: AppType.figureLarge.tone(value)),
                const SizedBox(height: Space.xxs),
                Row(
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: Space.xs + 1),
                      decoration: BoxDecoration(
                        color: ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        label.toUpperCase(),
                        style: AppType.micro.copyWith(fontSize: 9.5).tone(
                              lead ? ink : AppColors.inkMuted,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section heads
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.index,
    required this.title,
    required this.count,
    required this.note,
  });

  final String index;
  final String title;
  final int count;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                index,
                style: AppType.figure.tone(AppColors.inkMuted),
              ),
            ),
            Expanded(
              child: Text(title, style: AppType.titleLarge),
            ),
            Text(
              count.toString().padLeft(2, '0'),
              style: AppType.figureLarge.tone(AppColors.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(note, style: AppType.bodySmall.quieter),
          ),
        ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final TMIconName icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return TMEntry(
      backgroundColor: AppColors.paperRaised,
      padding: const EdgeInsets.all(Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.paperSunken,
              borderRadius: Radii.sharpAll,
            ),
            child: TMIcon(icon, size: 16, color: AppColors.inkMuted),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppType.label),
                const SizedBox(height: Space.xxs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Text(body, style: AppType.bodySmall.quieter),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A request that needs a decision
// ─────────────────────────────────────────────────────────────────────────────

class _RequestEntry extends StatelessWidget {
  const _RequestEntry({
    required this.conversation,
    required this.unread,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final Conversation conversation;
  final bool unread;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final Conversation c = conversation;
    final ChatMessage? last = c.lastMessage;

    return TMEntry(
      onTap: onOpen,
      semanticLabel:
          'Request from ${c.counterpartName}${unread ? ', unread' : ''}. Open the conversation.',
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PersonMark(
                name: c.counterpartName,
                id: c.counterpartId,
                unread: unread,
                size: 44,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.counterpartName,
                      style: AppType.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.subject} · '
                      '${c.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}',
                      style: AppType.bodySmall.quieter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              TMStatusPill(
                tone: c.status.tone,
                label: c.status.label,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm + 1,
              Space.md,
              Space.sm + 1,
            ),
            decoration: BoxDecoration(
              color: AppColors.pendingWash,
              borderRadius: Radii.sharpAll,
              border: Border.all(color: AppColors.rule),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: Space.sm),
                  child: TMIcon(
                    TMIconName.dash,
                    size: 13,
                    color: AppColors.pending,
                    strokeWidth: 2,
                  ),
                ),
                Expanded(
                  child: Text(
                    _snippet(c),
                    style: AppType.body.tone(AppColors.inkSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (last != null) ...<Widget>[
                  const SizedBox(width: Space.md),
                  Text(
                    last.sentAt,
                    style: AppType.micro.tone(AppColors.pending),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          const Divider(height: 1),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TMButton(
                label: 'Accept the request',
                icon: TMIconName.check,
                minHeight: Hit.min,
                onPressed: onAccept,
              ),
              TMButton(
                label: 'Decline',
                variant: TMButtonVariant.secondary,
                minHeight: Hit.min,
                onPressed: onDecline,
              ),
              TMTextLink(
                label: 'Read the thread first',
                style: AppType.bodySmall,
                onTap: onOpen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _snippet(Conversation c) {
    final ChatMessage? last = c.lastMessage;
    if (last == null) {
      return c.requestedByMe
          ? 'Request sent — this is where the answer will arrive.'
          : 'Request received — open it and answer it.';
    }
    return '${last.fromMe ? 'You: ' : ''}${last.text}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The conversation list
// ─────────────────────────────────────────────────────────────────────────────

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.conversations,
    required this.unread,
    required this.onOpen,
  });

  final List<Conversation> conversations;
  final bool Function(Conversation c) unread;
  final ValueChanged<Conversation> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.rule),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < conversations.length; i++)
            _ThreadRow(
              conversation: conversations[i],
              unread: unread(conversations[i]),
              first: i == 0,
              last: i == conversations.length - 1,
              onOpen: () => onOpen(conversations[i]),
            ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.conversation,
    required this.unread,
    required this.first,
    required this.last,
    required this.onOpen,
  });

  final Conversation conversation;
  final bool unread;
  final bool first;
  final bool last;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final Conversation c = conversation;
    final ChatMessage? message = c.lastMessage;
    final bool permission = c.status == RequestStatus.accepted;

    return TMFocusable(
      onTap: onOpen,
      semanticLabel:
          'Open the conversation with ${c.counterpartName}'
          '${unread ? ', unread' : ''}',
      builder: (BuildContext context, TMState s) {
        return TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: AnimatedContainer(
            duration: Motion.respect(context, Motion.fast),
            curve: Motion.ease,
            decoration: BoxDecoration(
              color: s.hovered ? AppColors.paperSunken.withValues(alpha: 0.7) : null,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(first ? Radii.sharp : 0),
                bottom: Radius.circular(last ? Radii.sharp : 0),
              ),
              border: Border(
                bottom: BorderSide(
                  color: last ? Colors.transparent : AppColors.rule,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PersonMark(
                  name: c.counterpartName,
                  id: c.counterpartId,
                  unread: unread,
                  size: 42,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              c.counterpartName,
                              style: AppType.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          if (unread)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: _UnreadDot(size: 7),
                            ),
                          const Spacer(),
                          if (message != null)
                            Text(
                              message.sentAt,
                              style: AppType.micro.tone(AppColors.inkMuted),
                            )
                          else
                            Text(
                              c.status == RequestStatus.pending
                                  ? (c.requestedByMe ? 'waiting' : 'needs you')
                                  : 'no messages',
                              style: AppType.micro.tone(AppColors.inkMuted),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${c.subject} · '
                              '${c.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}',
                              style: AppType.bodySmall.quieter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          TMStatusPill(
                            tone: c.status.tone,
                            label: permission ? 'Open' : c.status.label,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _snippet(c),
                              style: AppType.body.tone(
                                unread ? AppColors.ink : AppColors.inkSecondary,
                              ).copyWith(
                                fontWeight:
                                    unread ? FontWeight.w500 : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          TMIcon(
                            TMIconName.arrowRight,
                            size: 14,
                            color: unread ? AppColors.accent : AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _snippet(Conversation c) {
    final ChatMessage? last = c.lastMessage;
    if (last == null) {
      return c.requestedByMe
          ? 'Request sent — this is where the answer will arrive.'
          : 'Request received — open it and answer it.';
    }
    return '${last.fromMe ? 'You: ' : ''}${last.text}';
  }
}

class _PersonMark extends StatelessWidget {
  const _PersonMark({
    required this.name,
    required this.id,
    required this.unread,
    required this.size,
  });

  final String name;
  final String id;
  final bool unread;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        TMAvatar(
          name,
          size: size,
          tint: candidateById(id)?.photoTint,
        ),
        if (unread)
          Positioned(
            right: -2,
            top: -2,
            child: _UnreadDot(size: 11),
          ),
      ],
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Unread',
      child: Container(
        width: size + 4,
        height: size + 4,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.paperRaised,
          shape: BoxShape.circle,
        ),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
