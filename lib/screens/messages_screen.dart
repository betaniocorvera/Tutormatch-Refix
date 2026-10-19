// ─────────────────────────────────────────────────────────────────────────────
// Messages.
//
// Every request becomes a conversation here, and the conversation is where the
// status stops being a label and starts being a rule: accepted threads can be
// typed into, pending ones either say who they are waiting for or carry the
// Accept and Decline the answer is made of, and declined ones stay readable and
// closed.
//
// Requests waiting on an answer sit in their own section at the top — the only
// part of this screen with a decision in it — and they belong to whoever
// received the request, whichever role that is.
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
import 'package:tutormatch/widgets/tm_status.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool student = state.role == Role.student;
    final List<Conversation> chats = state.conversations;

    int count(RequestStatus status) =>
        chats.where((Conversation c) => c.status == status).length;

    // The decision belongs to the side that received the request, so the split
    // is by who sent it, not by role: the requests section is whatever is
    // waiting on this side, and everything else is a thread you read.
    bool awaitingMe(Conversation c) =>
        c.status == RequestStatus.pending && !c.requestedByMe;
    final List<Conversation> requests =
        chats.where(awaitingMe).toList(growable: false);
    final List<Conversation> threads =
        chats.where((Conversation c) => !awaitingMe(c)).toList(growable: false);

    Widget entry(Conversation c) => _ConversationEntry(
          conversation: c,
          onOpen: () =>
              Navigator.of(context).pushNamed(Routes.chat, arguments: c.id),
          onAccept: () => state.acceptConversation(c.id),
          onDecline: () => state.declineConversation(c.id),
        );

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
          const SizedBox(height: Space.xxl),
          Text('Messages', style: AppType.pageTitle),
          const SizedBox(height: Space.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              '${chats.length} conversations in this prototype: '
              '${count(RequestStatus.accepted)} open, '
              '${requests.length} waiting on your answer, '
              '${count(RequestStatus.pending) - requests.length} waiting on '
              'theirs, ${count(RequestStatus.declined)} closed. A request '
              'becomes a conversation the moment it is sent — a student to a '
              'tutor, or a tutor to a student — and the chat stays locked '
              'until the other side accepts.',
              style: AppType.bodyLarge.quiet,
            ),
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
            if (requests.isNotEmpty) ...<Widget>[
              const TMRule(label: 'Requests'),
              const SizedBox(height: Space.md),
              for (int i = 0; i < requests.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: Space.lg),
                entry(requests[i]),
              ],
              const SizedBox(height: Space.xxl),
            ],
            if (threads.isNotEmpty) ...<Widget>[
              if (requests.isNotEmpty) ...<Widget>[
                const TMRule(label: 'Conversations'),
                const SizedBox(height: Space.md),
              ],
              for (int i = 0; i < threads.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: Space.lg),
                entry(threads[i]),
              ],
            ],
          ],
          const SizedBox(height: Space.huge),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One conversation
// ─────────────────────────────────────────────────────────────────────────────

class _ConversationEntry extends StatelessWidget {
  const _ConversationEntry({
    required this.conversation,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final Conversation conversation;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final Conversation c = conversation;
    final ChatMessage? last = c.lastMessage;
    // The decision belongs to the side that did not send the request.
    final bool awaitingMe = c.status == RequestStatus.pending && !c.requestedByMe;

    return TMEntry(
      onTap: onOpen,
      semanticLabel: 'Open the conversation with ${c.counterpartName}',
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TMAvatar(
                c.counterpartName,
                size: 44,
                tint: candidateById(c.counterpartId)?.photoTint,
              ),
              const SizedBox(width: Space.lg),
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
                        if (last != null) ...<Widget>[
                          const SizedBox(width: Space.md),
                          Text(
                            last.sentAt,
                            style: AppType.micro.tone(AppColors.inkMuted),
                          ),
                        ],
                        if (last == null) ...<Widget>[
                          const SizedBox(width: Space.md),
                          Text(
                            c.status == RequestStatus.pending
                                ? (c.requestedByMe
                                    ? 'waiting'
                                    : 'needs your answer')
                                : 'no messages',
                            style: AppType.micro.tone(AppColors.inkMuted),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${c.subject} · ${c.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}',
                      style: AppType.bodySmall.quieter,
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      _snippet(c),
                      style: AppType.body.tone(AppColors.inkSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              TMStatusPill(tone: c.status.tone, label: c.status.label, dense: true),
            ],
          ),
          if (awaitingMe) ...<Widget>[
            const SizedBox(height: Space.lg),
            const Divider(height: 1),
            const SizedBox(height: Space.lg),
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
              ],
            ),
          ],
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
