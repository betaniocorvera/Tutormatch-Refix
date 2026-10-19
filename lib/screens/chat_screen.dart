// ─────────────────────────────────────────────────────────────────────────────
// One conversation.
//
// A messenger inside the ruled world: the header is the page's top bar with a
// way back, the thread is the page itself, and the composer is pinned to the
// bottom where a person's hands are. Your messages sit right, on the accent;
// theirs sit left on paper, each with a small avatar and the time underneath.
//
// The composer only exists while the request is accepted. A pending thread
// either says who it is waiting for or carries the decision itself, depending
// on which side sent the request; a declined one stays readable and closed.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';
import 'package:tutormatch/widgets/tm_status.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.conversationId, super.key});

  /// The id, not the object: the thread has to read the conversation as it is
  /// now, not as it was when the screen was pushed.
  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// How many messages the thread had at the last build. Any change — this
  /// side's, or the scripted answer's — puts the thread back at its foot.
  int _seen = -1;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    AppStateScope.read(context).sendMessage(widget.conversationId, text);
    // The field is now empty, so the send button has to go back to disabled.
    setState(() {});
  }

  void _toBottom({required bool jump}) {
    if (!mounted || !_scroll.hasClients) return;
    final double end = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(end);
    } else {
      _scroll.animateTo(end, duration: Motion.base, curve: Motion.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Conversation? found = state.conversation(widget.conversationId);
    if (found == null) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Center(
            child: Text(
              'This conversation is no longer here.',
              style: AppType.bodyLarge.quiet,
            ),
          ),
        ),
      );
    }
    final Conversation c = found;

    if (c.messages.length != _seen) {
      final bool first = _seen == -1;
      _seen = c.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(jump: first));
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ChatHeader(
              conversation: c,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: _thread(context, c)),
            _footer(context, state, c),
          ],
        ),
      ),
    );
  }

  Widget _thread(BuildContext context, Conversation c) {
    if (c.messages.isEmpty) {
      final String first = c.counterpartName.split(' ').first;
      final String empty = switch (c.status) {
        RequestStatus.accepted =>
          'No messages yet. Say which of the shared hours suits you.',
        RequestStatus.pending => c.requestedByMe
            ? 'Waiting for $first to accept — the chat opens here the moment '
                'they do.'
            : 'No messages yet — this request is waiting for your answer.',
        RequestStatus.declined =>
          'Nothing was written here before the request closed.',
      };
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: AppType.bodySmall.quieter,
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(
            horizontal: TMLayout.gutter(context),
            vertical: Space.xl,
          ),
          itemCount: c.messages.length,
          itemBuilder: (BuildContext context, int i) => Padding(
            padding: EdgeInsets.only(
              bottom: i == c.messages.length - 1 ? 0 : Space.lg,
            ),
            child: _Bubble(
              message: c.messages[i],
              name: c.counterpartName,
              // Whoever the conversation is with, their avatar is drawn from
              // the one pool row that knows what they look like.
              tint: candidateById(c.counterpartId)?.photoTint,
            ),
          ),
        ),
      ),
    );
  }

  /// Where the composer would be. One of the three states of the request takes
  /// that place, which is the whole design: what you can do next is the bottom
  /// line of the screen, always.
  Widget _footer(BuildContext context, AppState state, Conversation c) {
    // Who owes what is a fact about the request, not about the role: either
    // side can have sent it.
    final bool askedByMe = c.requestedByMe;
    final String first = c.counterpartName.split(' ').first;

    final Widget body = switch (c.status) {
      RequestStatus.accepted => _Composer(
          controller: _text,
          onChanged: () => setState(() {}),
          onSend: _send,
        ),
      RequestStatus.pending => askedByMe
          ? TMInlineNote(
              tone: StatusTone.pending,
              title: 'Waiting for $first to accept',
              body: 'They see the request in their Messages. The chat opens the '
                  'moment they accept it, for both sides — until then it is '
                  'read-only. Nothing is emailed in this prototype.',
            )
          : TMInlineNote(
              tone: StatusTone.pending,
              title: 'This request is waiting on your answer',
              body: 'Accept and the chat opens for both sides. Decline and it '
                  'closes here, with your answer on it.',
              actions: <Widget>[
                TMButton(
                  label: 'Accept the request',
                  icon: TMIconName.check,
                  minHeight: Hit.min,
                  onPressed: () => state.acceptConversation(c.id),
                ),
                TMButton(
                  label: 'Decline',
                  variant: TMButtonVariant.secondary,
                  minHeight: Hit.min,
                  onPressed: () => state.declineConversation(c.id),
                ),
              ],
            ),
      RequestStatus.declined => TMInlineNote(
          tone: StatusTone.declined,
          title: askedByMe
              ? '$first turned this request down'
              : 'You turned this request down',
          body: askedByMe
              ? 'The answer is the last message above. Asking again from their '
                  'profile reopens the conversation.'
              : 'The thread stays closed. If their situation changes, they can '
                  'send a new request from your profile.',
        ),
    };

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TMLayout.gutter(context),
          vertical: Space.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
            child: body,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.conversation, required this.onBack});

  final Conversation conversation;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final Conversation c = conversation;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: TMLayout.gutter(context),
              vertical: Space.md,
            ),
            child: Row(
              children: <Widget>[
                _BackButton(onTap: onBack),
                const SizedBox(width: Space.sm),
                TMAvatar(
                  c.counterpartName,
                  size: 40,
                  tint: candidateById(c.counterpartId)?.photoTint,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        c.counterpartName,
                        style: AppType.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.subject} · ${c.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}',
                        style: AppType.bodySmall.quieter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                TMStatusPill(tone: c.status.tone, label: c.status.label, dense: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TMFocusable(
      onTap: onTap,
      semanticLabel: 'Back',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.sharp,
        child: SizedBox(
          width: Hit.min,
          height: Hit.min,
          child: AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              color: s.hovered || s.focused
                  ? AppColors.paperSunken
                  : Colors.transparent,
              borderRadius: Radii.sharpAll,
            ),
            child: const Center(
              child: TMIcon(TMIconName.arrowLeft, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message and its time. Mine on the accent at the right; theirs on
/// sunken paper at the left, with the avatar that says who is talking.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.name, this.tint});

  final ChatMessage message;
  final String name;

  /// The counterpart's stand-in for a picture, when they have one.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final bool mine = message.fromMe;
    final Widget bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: mine ? AppColors.accent : AppColors.paperSunken,
        border: mine ? null : Border.all(color: AppColors.rule),
        borderRadius: Radii.sharpAll,
      ),
      child: Text(
        message.text,
        style: AppType.body.tone(mine ? AppColors.onAccent : AppColors.ink),
      ),
    );
    final Widget stamp = Text(
      message.sentAt,
      style: AppType.micro.tone(AppColors.inkMuted),
    );

    if (mine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  bubble,
                  const SizedBox(height: Space.xs),
                  stamp,
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: TMAvatar(name, size: 28, tint: tint),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bubble,
                const SizedBox(height: Space.xs),
                stamp,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The field and the send button. Enter sends as well, because the keyboard is
/// where the sentence just came from.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bool ready = controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSend(),
            textInputAction: TextInputAction.send,
            style: AppType.body,
            cursorWidth: 1.5,
            cursorRadius: const Radius.circular(1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.paperRaised,
              hintText: 'Write a message',
              hintStyle: AppType.body.tone(AppColors.inkMuted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              constraints: const BoxConstraints(minHeight: Hit.min),
              border: OutlineInputBorder(
                borderRadius: Radii.sharpAll,
                borderSide: const BorderSide(color: AppColors.ruleStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: Radii.sharpAll,
                borderSide: const BorderSide(color: AppColors.ruleStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.sharpAll,
                borderSide: const BorderSide(color: AppColors.ink, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.md),
        TMButton(
          label: 'Send',
          icon: TMIconName.arrowRight,
          minHeight: Hit.min,
          onPressed: ready ? onSend : null,
        ),
      ],
    );
  }
}
