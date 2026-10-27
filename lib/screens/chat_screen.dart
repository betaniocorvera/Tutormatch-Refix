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
//
// Once it opens, the conversation can hold more than sentences: a picked photo,
// a simulated voice note, a call the app records, and a session proposal with
// two answers in it. All of it is local state, and the photo bytes never leave
// this tab.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tutormatch/data/api_client.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/screens/call_screen.dart';
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
  final ImagePicker _picker = ImagePicker();

  /// How many messages the thread had at the last build. Any change — this
  /// side's, or the scripted answer's — puts the thread back at its foot.
  int _seen = -1;

  /// Messages already on screen once. A bubble slides in only the first time it
  /// appears in this session; scrolling back up does not replay the entrance.
  final Set<int> _appeared = <int>{};

  /// The composer draws its own focus edge around the field and its tools.
  final FocusNode _composerFocus = FocusNode();

  bool _emojiOpen = false;
  bool _attachOpen = false;
  bool _sending = false;
  Timer? _poll;

  /// Recording is a local simulation: a timer, a red dot, and a duration. The
  /// server records the resulting voice note, but no microphone is opened.
  bool _recording = false;
  Duration _recorded = Duration.zero;
  Timer? _recordTimer;

  /// The picked picture, waiting for Send. Bytes in memory, as everywhere else.
  Uint8List? _pendingPhoto;

  /// The panel of twenty-four. Small enough to scan, large enough to be useful.
  static const List<String> _emojis = <String>[
    '😀', '😄', '😊', '😂', '🙂', '😉',
    '😍', '🤔', '😅', '😮', '😢', '😭',
    '😡', '👍', '👎', '👏', '🙏', '🎉',
    '❤️', '🔥', '✅', '📚', '📝', '⏰',
  ];

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(_onComposerFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AppState state = AppStateScope.read(context);
      final Conversation? current = state.conversation(widget.conversationId);
      if (current == null || current.messages.isEmpty) {
        unawaited(state.loadConversation(widget.conversationId));
      }
      _poll = Timer.periodic(const Duration(seconds: 5), (Timer _) {
        if (!mounted) return;
        unawaited(state.refreshConversation(widget.conversationId));
      });
    });
  }

  void _onComposerFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _poll?.cancel();
    _composerFocus.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    if (_sending) return;
    final String text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await AppStateScope.read(context)
          .sendMessage(widget.conversationId, text);
      if (!mounted) return;
      _text.clear();
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _attachOpen = false;
      _emojiOpen = false;
    });
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file == null || !mounted) return;
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingPhoto = bytes);
    } on Exception {
      // A browser with no file picker, or a cancelled permission: say so rather
      // than dying on a tap.
      if (!mounted) return;
      _say('This device would not open a picture picker.');
    }
  }

  Future<void> _sendPhoto() async {
    final Uint8List? photo = _pendingPhoto;
    if (photo == null || _sending) return;
    setState(() => _sending = true);
    try {
      await AppStateScope.read(context)
          .sendImage(widget.conversationId, photo);
      if (mounted) setState(() => _pendingPhoto = null);
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startRecording() {
    _recordTimer?.cancel();
    setState(() {
      _recording = true;
      _recorded = Duration.zero;
      _emojiOpen = false;
      _attachOpen = false;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted) return;
      setState(() => _recorded += const Duration(seconds: 1));
    });
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    setState(() {
      _recording = false;
      _recorded = Duration.zero;
    });
  }

  Future<void> _sendVoice() async {
    final int seconds = _recorded.inSeconds < 1 ? 1 : _recorded.inSeconds;
    setState(() => _sending = true);
    try {
      await AppStateScope.read(context)
          .sendVoice(widget.conversationId, seconds);
      _recordTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recorded = Duration.zero;
      });
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── The small extras ──────────────────────────────────────────────────────

  void _toggleEmoji() {
    setState(() {
      _emojiOpen = !_emojiOpen;
      _attachOpen = false;
    });
  }

  void _toggleAttach() {
    setState(() {
      _attachOpen = !_attachOpen;
      _emojiOpen = false;
    });
  }

  /// Inserts at the caret, not at the end: an emoji is part of a sentence being
  /// written, not an addition to a finished one.
  void _insertEmoji(String emoji) {
    final TextEditingValue value = _text.value;
    final bool hasSelection = value.selection.isValid;
    final int start = hasSelection ? value.selection.start : value.text.length;
    final int end = hasSelection ? value.selection.end : value.text.length;
    final String next = value.text.replaceRange(start, end, emoji);
    _text.value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
      composing: TextRange.empty,
    );
    setState(() {});
  }

  Future<void> _proposeSession() async {
    setState(() {
      _attachOpen = false;
      _emojiOpen = false;
    });
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 2)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Which day?',
    );
    if (day == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      helpText: 'What time?',
    );
    if (time == null || !mounted) return;
    try {
      await AppStateScope.read(context).proposeSession(
        widget.conversationId,
        DateTime(day.year, day.month, day.day, time.hour, time.minute),
      );
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    }
  }

  Future<void> _accept(String id) async {
    try {
      await AppStateScope.read(context).acceptConversation(id);
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    }
  }

  Future<void> _decline(String id) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _DeclineChatDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await AppStateScope.read(context).declineConversation(id, reason: reason);
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    }
  }

  Future<void> _answerSession(
    String conversationId,
    String messageId,
    SessionState answer,
  ) async {
    try {
      await AppStateScope.read(context)
          .answerSession(conversationId, messageId, answer);
    } on ApiException catch (error) {
      if (mounted) _say(error.message);
    }
  }

  void _openPhoto(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.ink.withValues(alpha: 0.94),
      builder: (BuildContext context) => _PhotoViewer(bytes: bytes),
    );
  }

  void _startCall(CallKind kind) {
    Navigator.of(context).push(
      TMTransitions.page<void>(
        CallScreen(conversationId: widget.conversationId, kind: kind),
        name: '/call',
      ),
    );
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(text, style: AppType.bodySmall.tone(AppColors.onAccent)),
      ),
    );
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

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
              onCall: _startCall,
            ),
            Expanded(
              child: _thread(
                context,
                c,
                state.photoFor(c.counterpartId),
              ),
            ),
            _footer(context, state, c),
          ],
        ),
      ),
    );
  }

  Widget _thread(BuildContext context, Conversation c, Uint8List? photo) {
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
      return _EmptyThread(
        name: c.counterpartName,
        photo: photo,
        subject: c.subject,
        role: c.counterpartRole,
        message: empty,
      );
    }

    // Delivery belongs under the last thing this side actually sent. The server
    // sets read_by_recipient when the other participant marks the thread read.
    final ChatMessage? lastMine = c.lastMine;
    final bool seen = lastMine != null && c.seen(lastMine);
    final int count = c.messages.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(
            horizontal: TMLayout.gutter(context),
            vertical: Space.xl,
          ),
          itemCount: count,
          itemBuilder: (BuildContext context, int i) {
            final ChatMessage message = c.messages[i];
            final String? delivery = c.status == RequestStatus.accepted &&
                    message == lastMine
                ? (seen ? 'Seen' : 'Sent')
                : null;
            final bool fresh = _appeared.add(identityHashCode(message));
            return Padding(
              padding: EdgeInsets.only(
                bottom: i == count - 1 ? 0 : Space.lg,
              ),
              child: _MessageArrival(
                animate: fresh,
                fromMe: message.fromMe,
                child: _Bubble(
                  message: message,
                  name: c.counterpartName,
                  photo: photo,
                  delivery: delivery,
                  onOpenPhoto: _openPhoto,
                  onAnswerSession: message.id == null
                      ? null
                      : (SessionState answer) =>
                          _answerSession(c.id, message.id!, answer),
                ),
              ),
            );
          },
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
      RequestStatus.accepted => _composerArea(context),
      RequestStatus.pending => askedByMe
          ? TMInlineNote(
              tone: StatusTone.pending,
              title: 'Waiting for $first to accept',
              body: 'They see the request in their Messages. The chat opens the '
                  'moment they accept it, for both sides — until then it is '
                  'read-only. Nothing is emailed.',
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
                  onPressed: () => _accept(c.id),
                ),
                TMButton(
                  label: 'Decline',
                  variant: TMButtonVariant.secondary,
                  minHeight: Hit.min,
                  onPressed: () => _decline(c.id),
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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: TMLayout.gutter(context),
            vertical: Space.lg,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
              child: AnimatedSize(
                duration: Motion.respect(context, Motion.base),
                curve: Motion.ease,
                alignment: Alignment.bottomCenter,
                child: AnimatedSwitcher(
                  duration: Motion.respect(context, Motion.slow),
                  switchInCurve: Motion.ease,
                  switchOutCurve: Motion.ease,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    if (Motion.reduced(context)) return child;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<RequestStatus>(c.status),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The bar and everything that unfolds above it. On a phone the four
  /// affordances collapse into one + menu; the field and Send never move.
  Widget _composerArea(BuildContext context) {
    final bool compact = TMLayout.isCompact(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_pendingPhoto != null) ...<Widget>[
              _photoDraft(context),
              const SizedBox(height: Space.md),
            ],
            if (_emojiOpen) ...<Widget>[
              _emojiPanel(context),
              const SizedBox(height: Space.md),
            ],
            if (_attachOpen && compact) ...<Widget>[
              _attachPanel(context),
              const SizedBox(height: Space.md),
            ],
          ],
        ),
        AnimatedSwitcher(
          duration: Motion.respect(context, Motion.fast),
          switchInCurve: Motion.ease,
          switchOutCurve: Motion.ease,
          child: _recording
              ? KeyedSubtree(
                  key: const ValueKey<String>('recording'),
                  child: _recordingBar(context),
                )
              : KeyedSubtree(
                  key: const ValueKey<String>('composer'),
                  child: _composerRow(context, compact),
                ),
        ),
      ],
    );
  }

  /// One surface for the field and its tools, with a single focus edge that
  /// lights when either the field or a tool holds the keyboard.
  Widget _composerRow(BuildContext context, bool compact) {
    final bool focused = _composerFocus.hasFocus;

    return AnimatedContainer(
      duration: Motion.respect(context, Motion.fast),
      curve: Motion.ease,
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: Radii.sharpAll,
        border: Border.all(
          color: focused ? AppColors.ink : AppColors.ruleStrong,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (compact)
            _ChatIconButton(
              icon: TMIconName.plus,
              tooltip: 'More ways to send',
              active: _attachOpen || _emojiOpen,
              onTap: _toggleAttach,
            )
          else ...<Widget>[
            _ChatIconButton(
              icon: TMIconName.image,
              tooltip: 'Send a photo',
              onTap: _pickPhoto,
            ),
            _ChatIconButton(
              icon: TMIconName.mic,
              tooltip: 'Record a voice note',
              onTap: _startRecording,
            ),
            _ChatIconButton(
              icon: TMIconName.calendar,
              tooltip: 'Propose a session',
              onTap: _proposeSession,
            ),
          ],
          const SizedBox(width: Space.xs),
          Expanded(child: _messageField()),
          if (!compact)
            _ChatIconButton(
              icon: TMIconName.emoji,
              tooltip: 'Insert an emoji',
              active: _emojiOpen,
              onTap: _toggleEmoji,
            ),
          const SizedBox(width: Space.sm),
          TMButton(
            label: 'Send',
            icon: TMIconName.arrowRight,
            minHeight: Hit.min,
            busy: _sending,
            busyLabel: 'Sending…',
            onPressed:
                _sending || _text.text.trim().isEmpty ? null : _sendText,
          ),
        ],
      ),
    );
  }

  Widget _messageField() {
    return TextField(
      controller: _text,
      focusNode: _composerFocus,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _sendText(),
      textInputAction: TextInputAction.send,
      style: AppType.body,
      cursorColor: AppColors.accent,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(1),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        hintText: 'Write a message',
        hintStyle: TextStyle(color: AppColors.inkMuted),
        contentPadding: EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: 11,
        ),
        constraints: BoxConstraints(minHeight: Hit.min),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  /// The selected picture, held back until it is wanted: sending it is a
  /// separate decision from choosing it.
  Widget _photoDraft(BuildContext context) {
    final Uint8List bytes = _pendingPhoto!;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.ruleStrong),
        borderRadius: Radii.sharpAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: Radii.sharpAll,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                        const ColoredBox(color: AppColors.paperSunken),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Photo ready to send', style: AppType.label),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'It is uploaded when you send it. The server strips '
                      'metadata before storing the image.',
                      style: AppType.bodySmall.quieter,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            alignment: WrapAlignment.end,
            children: <Widget>[
              TMButton(
                label: 'Send photo',
                icon: TMIconName.arrowRight,
                minHeight: Hit.min,
                busy: _sending,
                busyLabel: 'Uploading…',
                onPressed: _sending ? null : _sendPhoto,
              ),
              TMButton(
                label: 'Cancel',
                variant: TMButtonVariant.secondary,
                minHeight: Hit.min,
                onPressed: () => setState(() => _pendingPhoto = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Recording takes the place of the field, as the task asks: there is
  /// nothing to type while a take is running, and two decisions to make.
  Widget _recordingBar(BuildContext context) {
    final bool compact = TMLayout.isCompact(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.accent),
        borderRadius: Radii.sharpAll,
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 10,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            elapsedClock(_recorded),
            style: AppType.figure.tone(AppColors.ink),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                'Recording a voice note',
                style: AppType.bodySmall.quieter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          TMButton(
            label: 'Cancel',
            variant: TMButtonVariant.quiet,
            minHeight: Hit.min,
            onPressed: _cancelRecording,
          ),
          const SizedBox(width: Space.sm),
          TMButton(
            label: 'Send',
            icon: TMIconName.arrowRight,
            minHeight: Hit.min,
            busy: _sending,
            busyLabel: 'Sending…',
            onPressed: _sending ? null : _sendVoice,
          ),
        ],
      ),
    );
  }

  /// Twenty-four common emoji, each on a full tap target. Scrolls inside a
  /// fixed height so the thread above never disappears entirely.
  Widget _emojiPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.rule),
        borderRadius: Radii.softAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.xs,
                ),
                child: Text(
                  'EMOJI',
                  style: AppType.micro.tone(AppColors.inkMuted),
                ),
              ),
              const Spacer(),
              _ChatIconButton(
                icon: TMIconName.close,
                tooltip: 'Close the emoji panel',
                onTap: () => setState(() => _emojiOpen = false),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 188),
            child: SingleChildScrollView(
              child: Wrap(
                children: <Widget>[
                  for (final String emoji in _emojis)
                    TMFocusable(
                      onTap: () => _insertEmoji(emoji),
                      semanticLabel: 'Insert $emoji',
                      semanticButton: false,
                      builder: (BuildContext context, TMState s) => TMFocusRing(
                        focused: s.focused,
                        radius: Radii.sharp,
                        child: Container(
                          width: Hit.min,
                          height: Hit.min,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: s.hovered || s.focused
                                ? AppColors.paperSunken
                                : Colors.transparent,
                            borderRadius: Radii.sharpAll,
                          ),
                          child: Text(emoji, style: AppType.emoji),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The narrow-width alternative to four icons: one +, four labelled actions.
  Widget _attachPanel(BuildContext context) {
    void close() => setState(() => _attachOpen = false);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.rule),
        borderRadius: Radii.softAll,
      ),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: <Widget>[
          TMButton(
            label: 'Photo',
            icon: TMIconName.image,
            variant: TMButtonVariant.secondary,
            minHeight: Hit.min,
            onPressed: () {
              close();
              _pickPhoto();
            },
          ),
          TMButton(
            label: 'Voice note',
            icon: TMIconName.mic,
            variant: TMButtonVariant.secondary,
            minHeight: Hit.min,
            onPressed: () {
              close();
              _startRecording();
            },
          ),
          TMButton(
            label: 'Emoji',
            icon: TMIconName.emoji,
            variant: TMButtonVariant.secondary,
            minHeight: Hit.min,
            onPressed: () {
              setState(() {
                _attachOpen = false;
                _emojiOpen = true;
              });
            },
          ),
          TMButton(
            label: 'Propose a session',
            icon: TMIconName.calendar,
            variant: TMButtonVariant.secondary,
            minHeight: Hit.min,
            onPressed: () {
              close();
              _proposeSession();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.onBack,
    required this.onCall,
  });

  final Conversation conversation;
  final VoidCallback onBack;
  final ValueChanged<CallKind> onCall;

  @override
  Widget build(BuildContext context) {
    final Conversation c = conversation;
    final AppState state = AppStateScope.of(context);
    final bool accepted = c.status == RequestStatus.accepted;
    final bool compact = TMLayout.isCompact(context);
    final PublicPlace? counterpartPlace =
        state.matchFor(c.counterpartId)?.candidate.publicPlace;
    // On a phone the header earns its height by keeping the call actions and
    // dropping the accepted label; the footer states the status anyway.

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.paperRaised,
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContent),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: TMLayout.gutter(context),
              vertical: Space.sm + 2,
            ),
            child: Row(
              children: <Widget>[
                _ChatIconButton(
                  icon: TMIconName.arrowLeft,
                  tooltip: 'Back to messages',
                  onTap: onBack,
                ),
                const SizedBox(width: Space.sm),
                TMAvatar(
                  c.counterpartName,
                  size: 40,
                  photo: state.photoFor(c.counterpartId),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          c.counterpartName,
                          style: AppType.sectionTitle.copyWith(fontSize: 19.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              '${c.subject} · '
                              '${c.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}',
                              style: AppType.bodySmall.quieter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (counterpartPlace != null && !compact) ...<Widget>[
                            const SizedBox(width: Space.sm),
                            const TMIcon(
                              TMIconName.pin,
                              size: 11,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                counterpartPlace.label,
                                style: AppType.micro.tone(AppColors.inkMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // On a phone the area moves to its own line rather than
                      // disappearing: the allowed public area is part of what
                      // both sides agreed to share, and a narrower window is
                      // not a reason to hide it.
                      if (counterpartPlace != null && compact) ...<Widget>[
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            const TMIcon(
                              TMIconName.pin,
                              size: 10,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                counterpartPlace.label,
                                style: AppType.micro
                                    .copyWith(fontSize: 9.5)
                                    .tone(AppColors.inkMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (accepted) ...<Widget>[
                  const SizedBox(width: Space.xs),
                  _ChatIconButton(
                    icon: TMIconName.phone,
                    tooltip: 'Start a voice call',
                    onTap: () => onCall(CallKind.voice),
                  ),
                  const SizedBox(width: Space.xxs),
                  _ChatIconButton(
                    icon: TMIconName.video,
                    tooltip: 'Start a video call',
                    onTap: () => onCall(CallKind.video),
                  ),
                ] else ...<Widget>[
                  const SizedBox(width: Space.sm),
                  TMStatusPill(
                    tone: c.status.tone,
                    label: c.status.label,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One square action, 44 px, with a hover and focus state from the shared
/// vocabulary. Back, the two call buttons and every composer icon are this.
class _ChatIconButton extends StatelessWidget {
  const _ChatIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.onInk = false,
  });

  final TMIconName icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final Color base = onInk ? AppColors.onAccent : AppColors.ink;
    final Color fill = onInk
        ? AppColors.onAccent.withValues(alpha: 0.16)
        : AppColors.paperSunken;

    return Tooltip(
      message: tooltip,
      child: TMFocusable(
        onTap: onTap,
        semanticLabel: tooltip,
        builder: (BuildContext context, TMState s) => TMFocusRing(
          focused: s.focused,
          radius: Radii.sharp,
          child: SizedBox(
            width: Hit.min,
            height: Hit.min,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              decoration: BoxDecoration(
                color: active || s.hovered || s.focused
                    ? fill
                    : Colors.transparent,
                borderRadius: Radii.sharpAll,
              ),
              child: Center(
                child: TMIcon(icon, size: 20, color: base),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The asymmetric corner that gives a message a direction: the side the bubble
/// belongs to has the soft 12 px corner, the side nearest the other person has a
/// 3 px notch. Everything else in the product stays on [Radii.sharpAll].
BorderRadius _bubbleRadius(bool mine) => BorderRadius.only(
      topLeft: const Radius.circular(Radii.sharp),
      topRight: const Radius.circular(Radii.sharp),
      bottomLeft: Radius.circular(mine ? Radii.sharp : 3),
      bottomRight: Radius.circular(mine ? 3 : Radii.sharp),
    );

/// One message arriving. It travels 10 px from the side it belongs to and fades
/// in over 250 ms; only the first appearance in this session, never on scroll.
class _MessageArrival extends StatefulWidget {
  const _MessageArrival({
    required this.child,
    required this.fromMe,
    required this.animate,
  });

  final Widget child;
  final bool fromMe;
  final bool animate;

  @override
  State<_MessageArrival> createState() => _MessageArrivalState();
}

class _MessageArrivalState extends State<_MessageArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );
  bool _still = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = !widget.animate || Motion.reduced(context);
    if (_still) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = Motion.ease.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset((1 - t) * (widget.fromMe ? 10 : -10), 4 * (1 - t)),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX((1 - t) * 6 * math.pi / 180),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The empty thread: the person, what the thread is about, and the one sentence
/// that says why there is nothing here yet. The composer sits below it when the
/// request is accepted.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({
    required this.name,
    required this.subject,
    required this.role,
    required this.message,
    this.photo,
  });

  final String name;
  final String subject;
  final Role role;
  final String message;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: TMLayout.gutter(context),
          vertical: Space.xxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TMAvatar(name, size: 64, photo: photo),
              const SizedBox(height: Space.lg),
              Text(
                name,
                textAlign: TextAlign.center,
                style: AppType.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                '$subject · ${role == Role.tutor ? 'Tutor' : 'Student'}',
                textAlign: TextAlign.center,
                style: AppType.bodySmall.quieter,
              ),
              const SizedBox(height: Space.xl),
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: AppColors.paperRaised,
                  border: Border.all(color: AppColors.rule),
                  borderRadius: Radii.sharpAll,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: Space.md),
                      child: TMIcon(
                        TMIconName.chat,
                        size: 17,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        message,
                        style: AppType.body.quiet,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.name,
    this.photo,
    this.delivery,
    this.onOpenPhoto,
    this.onAnswerSession,
  });

  final ChatMessage message;
  final String name;

  /// The counterpart's picture, when the API has one and it has loaded.
  final Uint8List? photo;

  /// `Sent` or `Seen`, and only under the last line this side sent.
  final String? delivery;

  final ValueChanged<Uint8List>? onOpenPhoto;
  final ValueChanged<SessionState>? onAnswerSession;

  bool get _mine => message.fromMe;

  @override
  Widget build(BuildContext context) {
    // A call is an event in the thread, not a message with a side.
    if (message.kind == MessageKind.call) {
      return _CallLine(message: message);
    }

    final Widget content = switch (message.kind) {
      MessageKind.text => _textBubble(),
      MessageKind.image =>
        _ImageBubble(image: message.image, onOpen: onOpenPhoto),
      MessageKind.voice => _VoiceBubble(message: message, mine: _mine),
      MessageKind.session => _SessionCard(
          message: message,
          name: name,
          onAnswer: onAnswerSession,
        ),
      MessageKind.call => const SizedBox.shrink(),
    };

    final Widget stamp = Text(
      delivery == null ? message.sentAt : '${message.sentAt} · $delivery',
      style: AppType.micro.tone(AppColors.inkMuted),
    );

    if (_mine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  content,
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
          child: TMAvatar(name, size: 28, photo: photo),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                content,
                const SizedBox(height: Space.xs),
                stamp,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _textBubble() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md - 1,
        Space.lg,
        Space.md - 1,
      ),
      decoration: BoxDecoration(
        color: _mine ? AppColors.accent : AppColors.paperRaised,
        border: _mine ? null : Border.all(color: AppColors.rule),
        borderRadius: _bubbleRadius(_mine),
      ),
      child: Text(
        message.text,
        style: AppType.body.tone(
          _mine ? AppColors.onAccent : AppColors.ink,
        ),
      ),
    );
  }
}

/// A rounded picture bubble: the one shape in the product that is allowed the
/// soft radius, because a photograph is a thing placed on the page rather than
/// a row of it. Tapping opens it full-screen.
class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.image, required this.onOpen});

  final Uint8List? image;
  final ValueChanged<Uint8List>? onOpen;

  static const double _width = 260;
  static const double _height = 170;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = image;
    if (bytes == null) {
      return Container(
        width: _width,
        height: _height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.paperSunken,
          border: Border.all(color: AppColors.rule),
          borderRadius: Radii.softAll,
        ),
        child: Text('This photo is no longer here', style: AppType.bodySmall.quieter),
      );
    }

    return TMFocusable(
      onTap: onOpen == null ? null : () => onOpen!(bytes),
      semanticLabel: 'Open the photo full screen',
      builder: (BuildContext context, TMState s) => TMFocusRing(
        focused: s.focused,
        radius: Radii.soft,
        child: Container(
          width: _width,
          height: _height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.paperSunken,
            borderRadius: Radii.softAll,
            border: Border.all(color: AppColors.ruleStrong),
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  'This photo could not be shown.',
                  textAlign: TextAlign.center,
                  style: AppType.bodySmall.quieter,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A voice note with no audio: a play mark, an authored waveform, a duration,
/// and an animation that runs exactly as long as the note claims to.
class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble>
    with SingleTickerProviderStateMixin {
  static const List<double> _heights = <double>[
    6, 11, 16, 8, 19, 13, 22, 9, 17, 21,
    12, 18, 7, 15, 20, 10, 16, 22, 13, 19,
    9, 14,
  ];

  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.message.seconds < 1 ? 1 : widget.message.seconds),
  );
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _play.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _playing = false;
          _play.value = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _play.stop();
      setState(() => _playing = false);
      return;
    }
    if (_play.value >= 1) _play.value = 0;
    _play.forward();
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final bool mine = widget.mine;
    final Color fg = mine ? AppColors.onAccent : AppColors.ink;
    final Color played = mine ? AppColors.onAccent : AppColors.ink;
    final Color rest = mine
        ? AppColors.onAccent.withValues(alpha: 0.38)
        : AppColors.ruleStrong;

    return Container(
      padding: const EdgeInsets.only(
        left: Space.xs,
        right: Space.md,
        top: Space.xs,
        bottom: Space.xs,
      ),
      decoration: BoxDecoration(
        color: mine ? AppColors.accent : AppColors.paperRaised,
        border: mine ? null : Border.all(color: AppColors.rule),
        borderRadius: _bubbleRadius(mine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: _playing ? 'Pause the voice note' : 'Play the voice note',
            child: TMFocusable(
              onTap: _toggle,
              semanticLabel: _playing
                  ? 'Pause the voice note'
                  : 'Play the voice note, ${voiceLabel(widget.message.seconds)}',
              builder: (BuildContext context, TMState s) => TMFocusRing(
                focused: s.focused,
                radius: Radii.sharp,
                child: SizedBox(
                  width: Hit.min,
                  height: Hit.min,
                  child: Center(
                    child: TMIcon(
                      _playing ? TMIconName.pause : TMIconName.play,
                      size: 18,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          AnimatedBuilder(
            animation: _play,
            builder: (BuildContext context, Widget? child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < _heights.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == _heights.length - 1 ? 0 : 2,
                    ),
                    child: Container(
                      width: 2,
                      height: _heights[i],
                      color: i / (_heights.length - 1) <= _play.value
                          ? played
                          : rest,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            voiceLabel(widget.message.seconds),
            style: AppType.figure.tone(fg),
          ),
        ],
      ),
    );
  }
}

/// A session proposal. The date is the subject; the two answers live in the
/// card until one is chosen, and then the card says which.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.message,
    required this.name,
    required this.onAnswer,
  });

  final ChatMessage message;
  final String name;
  final ValueChanged<SessionState>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final bool proposed = message.sessionState == SessionState.proposed;
    final String when =
        message.sessionWhen.isEmpty ? 'Time to be agreed' : message.sessionWhen;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.ruleStrong),
          borderRadius: Radii.sharpAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const TMIcon(
                  TMIconName.calendar,
                  size: 15,
                  color: AppColors.inkSecondary,
                ),
                const SizedBox(width: Space.sm),
                const TMMicroLabelText('Session proposal'),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(when, style: AppType.sectionTitle),
            const SizedBox(height: Space.xs),
            Text(
              message.fromMe
                  ? 'You proposed this time.'
                  : '$name proposed this time.',
              style: AppType.bodySmall.quieter,
            ),
            const SizedBox(height: Space.lg),
            if (proposed)
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: <Widget>[
                  TMButton(
                    label: 'Accept',
                    icon: TMIconName.check,
                    minHeight: Hit.min,
                    onPressed: onAnswer == null
                        ? null
                        : () => onAnswer!(SessionState.accepted),
                  ),
                  TMButton(
                    label: 'Decline',
                    variant: TMButtonVariant.secondary,
                    minHeight: Hit.min,
                    onPressed: onAnswer == null
                        ? null
                        : () => onAnswer!(SessionState.declined),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  TMStatusPill(
                    tone: message.sessionState.tone,
                    label: message.sessionState.label,
                    dense: true,
                  ),
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text(
                      message.sessionState == SessionState.accepted
                          ? 'The time is held.'
                          : 'The proposal is closed.',
                      style: AppType.bodySmall.quieter,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A call the app recorded. Centered and quiet, because it happened between the
/// messages rather than being one of them.
class _CallLine extends StatelessWidget {
  const _CallLine({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool video = message.text.startsWith('Video');
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TMIcon(
            video ? TMIconName.video : TMIconName.phone,
            size: 14,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: Space.sm),
          Text(message.text, style: AppType.micro.tone(AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _DeclineChatDialog extends StatefulWidget {
  const _DeclineChatDialog();

  @override
  State<_DeclineChatDialog> createState() => _DeclineChatDialogState();
}

class _DeclineChatDialogState extends State<_DeclineChatDialog> {
  final TextEditingController _reason = TextEditingController(
    text: 'Not the right fit right now.',
  );

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paperRaised,
      title: const Text('Decline this request?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'The other person sees your reason in the closed thread. They can '
            'send a new request later.',
            style: AppType.bodySmall.quieter,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep it open'),
        ),
        FilledButton(
          onPressed: () {
            final String reason = _reason.text.trim();
            Navigator.of(context).pop(
              reason.isEmpty ? 'Not the right fit right now.' : reason,
            );
          },
          child: const Text('Decline'),
        ),
      ],
    );
  }
}

/// The photo, alone on ink, at the size the window allows. Picked bytes only:
/// nothing here is fetched, so there is nothing to wait for but the decode.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return TMInkContext(
      onInk: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(Space.lg),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Padding(
                // Room for the close button, and a margin so a bright photo
                // never runs into the edge of the window.
                padding: const EdgeInsets.fromLTRB(
                  Space.xl,
                  Space.xxxl,
                  Space.xl,
                  Space.xl,
                ),
                child: SizedBox.expand(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error,
                            StackTrace? stack) =>
                        Center(
                      child: Text(
                        'This photo could not be shown.',
                        style: AppType.bodySmall.tone(AppColors.onAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: _ChatIconButton(
                icon: TMIconName.close,
                tooltip: 'Close the photo',
                onTap: () => Navigator.of(context).pop(),
                onInk: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
