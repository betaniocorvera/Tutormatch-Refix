// ─────────────────────────────────────────────────────────────────────────────
// A call.
//
// Nothing rings and nothing is captured: the screen says "Calling..." for two
// seconds, decides that the other side picked up, and then counts. Muting and
// turning the camera off are local switches with no devices behind them, and
// the note at the foot says so rather than letting the interface imply a
// capability it does not have.
//
// The one real effect is the line it leaves in the thread: a length when the
// call connected, "Missed call" when it was put down while still ringing.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';
import 'package:tutormatch/widgets/tm_button.dart';
import 'package:tutormatch/widgets/tm_icon.dart';
import 'package:tutormatch/widgets/tm_layout.dart';

enum CallKind { voice, video }

class CallScreen extends StatefulWidget {
  const CallScreen({
    required this.conversationId,
    required this.kind,
    super.key,
  });

  final String conversationId;
  final CallKind kind;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  /// Two seconds of ringing, then a connected call. The whole simulation.
  static const Duration _ringFor = Duration(seconds: 2);

  Timer? _connect;
  Timer? _tick;
  bool _connected = false;
  int _seconds = 0;
  bool _ended = false;

  bool _muted = false;
  bool _speaker = false;
  bool _cameraOff = false;
  bool _frontCamera = true;

  bool get _video => widget.kind == CallKind.video;

  @override
  void initState() {
    super.initState();
    _connect = Timer(_ringFor, () {
      if (!mounted) return;
      setState(() => _connected = true);
      _tick = Timer.periodic(const Duration(seconds: 1), (Timer _) {
        if (!mounted) return;
        setState(() => _seconds++);
      });
    });
  }

  @override
  void dispose() {
    _connect?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _connect?.cancel();
    _tick?.cancel();
    AppStateScope.read(context).logCall(
      widget.conversationId,
      video: _video,
      connected: _connected,
      duration: Duration(seconds: _seconds),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final Conversation? conversation =
        state.conversation(widget.conversationId);
    final String name = conversation?.counterpartName ?? 'This conversation';
    final Color? tint = conversation == null
        ? null
        : candidateById(conversation.counterpartId)?.photoTint;
    final String subtitle = conversation == null
        ? ''
        : '${conversation.subject} · '
            '${conversation.counterpartRole == Role.tutor ? 'Tutor' : 'Student'}';

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _video ? 880 : 640),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                TMLayout.gutter(context),
                Space.lg,
                TMLayout.gutter(context),
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _topLine(),
                  const SizedBox(height: Space.lg),
                  Expanded(
                    child: _video
                        ? _videoStage(context, state, name, tint, subtitle)
                        : _voiceStage(name, tint, subtitle),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    'Simulated call, no real audio or video yet',
                    textAlign: TextAlign.center,
                    style: AppType.bodySmall.quieter,
                  ),
                  const SizedBox(height: Space.lg),
                  _controls(),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topLine() {
    return Row(
      children: <Widget>[
        Text(
          _video ? 'VIDEO CALL' : 'VOICE CALL',
          style: AppType.micro.tone(AppColors.inkMuted),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: Motion.respect(context, Motion.base),
          switchInCurve: Motion.ease,
          switchOutCurve: Motion.ease,
          child: Row(
            key: ValueKey<bool>(_connected),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: Space.sm),
                decoration: BoxDecoration(
                  color: _connected ? AppColors.accepted : AppColors.pending,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                _connected ? 'CONNECTED' : 'RINGING',
                style: AppType.micro.tone(
                  _connected ? AppColors.accepted : AppColors.pending,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Voice has no picture to show, so the person is the screen.
  Widget _voiceStage(String name, Color? tint, String subtitle) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TMAvatar(name, size: 104, tint: tint),
            const SizedBox(height: Space.xl),
            Text(
              name,
              textAlign: TextAlign.center,
              style: AppType.titleLarge,
            ),
            if (subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.xs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppType.bodySmall.quieter,
              ),
            ],
            const SizedBox(height: Space.xxl),
            _status(),
          ],
        ),
      ),
    );
  }

  /// Video is one large solid stage for the other person, with a small box for
  /// the person holding the phone. Both are placeholders, and neither pretends
  /// to be a camera.
  Widget _videoStage(
    BuildContext context,
    AppState state,
    String name,
    Color? tint,
    String subtitle,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: Radii.sharpAll,
        border: Border.all(color: AppColors.ink),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TMAvatar(name, size: 120, tint: tint),
                  const SizedBox(height: Space.xl),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: AppType.titleLarge.tone(AppColors.onAccent),
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.xs),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppType.bodySmall.tone(AppColors.onInkFaint),
                    ),
                  ],
                  const SizedBox(height: Space.xxl),
                  _status(onInk: true),
                ],
              ),
            ),
          ),
          Positioned(
            right: Space.lg,
            bottom: Space.lg,
            child: _YouBox(
              viewerName: state.profile.name,
              photo: state.photo,
              cameraOff: _cameraOff,
              frontCamera: _frontCamera,
            ),
          ),
        ],
      ),
    );
  }

  Widget _status({bool onInk = false}) {
    final Color quiet =
        onInk ? AppColors.onInkQuiet : AppColors.inkSecondary;
    final Color bright = onInk ? AppColors.onAccent : AppColors.ink;

    final Widget content = _connected
        ? Column(
            key: const ValueKey<String>('connected'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Connected', style: AppType.bodySmall.tone(quiet)),
              const SizedBox(height: Space.xs),
              Text(
                elapsedClock(Duration(seconds: _seconds)),
                style: AppType.figureLarge.tone(bright),
              ),
            ],
          )
        : Text(
            'Calling...',
            key: const ValueKey<String>('calling'),
            style: AppType.bodyLarge.tone(quiet),
          );

    return AnimatedSwitcher(
      duration: Motion.respect(context, Motion.base),
      switchInCurve: Motion.ease,
      switchOutCurve: Motion.ease,
      transitionBuilder: (Widget child, Animation<double> animation) {
        if (Motion.reduced(context)) return child;
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: content,
    );
  }

  Widget _controls() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.lg,
      runSpacing: Space.md,
      children: <Widget>[
        _CallButton(
          icon: _muted ? TMIconName.micOff : TMIconName.mic,
          tooltip: _muted ? 'Unmute' : 'Mute',
          selected: _muted,
          onTap: () => setState(() => _muted = !_muted),
        ),
        if (_video)
          _CallButton(
            icon: _cameraOff ? TMIconName.videoOff : TMIconName.video,
            tooltip: _cameraOff ? 'Turn the camera on' : 'Turn the camera off',
            selected: _cameraOff,
            onTap: () => setState(() => _cameraOff = !_cameraOff),
          )
        else
          _CallButton(
            icon: _speaker ? TMIconName.speakerOff : TMIconName.speaker,
            tooltip: _speaker ? 'Speaker off' : 'Speaker on',
            selected: _speaker,
            onTap: () => setState(() => _speaker = !_speaker),
          ),
        if (_video)
          _CallButton(
            icon: TMIconName.cameraFlip,
            tooltip: _frontCamera ? 'Use the back camera' : 'Use the front camera',
            onTap: () => setState(() => _frontCamera = !_frontCamera),
          ),
        _CallButton(
          icon: TMIconName.phoneDown,
          tooltip: 'End call',
          danger: true,
          size: 64,
          onTap: _end,
        ),
      ],
    );
  }
}

/// The small "you" box in the corner of a video call. It shows the viewer's own
/// picture when there is one, and is honest when the camera is meant to be off.
class _YouBox extends StatelessWidget {
  const _YouBox({
    required this.viewerName,
    required this.photo,
    required this.cameraOff,
    required this.frontCamera,
  });

  final String viewerName;
  final Uint8List? photo;
  final bool cameraOff;
  final bool frontCamera;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.ruleStrong),
        borderRadius: Radii.softAll,
      ),
      child: cameraOff
          ? Row(
              children: <Widget>[
                const TMIcon(
                  TMIconName.videoOff,
                  size: 16,
                  color: AppColors.inkSecondary,
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text('Camera off', style: AppType.micro.quieter),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                TMAvatar(viewerName, size: 34, photo: photo),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('You', style: AppType.labelSmall),
                      const SizedBox(height: 1),
                      Text(
                        frontCamera ? 'Front camera' : 'Back camera',
                        style: AppType.micro.quieter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// A circular call control. Circles are the one place the product allows a
/// fully round container: these sit above the page the way the call itself
/// does, and the shape is the entire convention for a call surface.
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.size = 56,
  });

  final TMIconName icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TMFocusable(
        onTap: onTap,
        semanticLabel: tooltip,
        builder: (BuildContext context, TMState s) {
          final Color fill = danger
              ? (s.pressed ? AppColors.ink : AppColors.alert)
              : selected
                  ? AppColors.ink
                  : s.hovered
                      ? AppColors.paperSunken
                      : AppColors.paperRaised;
          final Color ink = danger || selected ? AppColors.onAccent : AppColors.ink;

          return TMFocusRing(
            focused: s.focused,
            radius: size / 2,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.ease,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: danger
                      ? AppColors.alert
                      : selected
                          ? AppColors.ink
                          : AppColors.ruleStrong,
                ),
              ),
              child: Center(child: TMIcon(icon, size: 22, color: ink)),
            ),
          );
        },
      ),
    );
  }
}
