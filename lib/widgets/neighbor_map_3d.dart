// ─────────────────────────────────────────────────────────────────────────────
// The neighbour map.
//
// Matching is a distance problem, so it is drawn as one: you at the centre, the
// closest tutors on the nearest ring, the rest further back and smaller, all
// turning slowly around the answer. Nothing here is a chart. It is the shape of
// the result explained before a single card is read.
//
// Native 3D, no packages and no model files: a perspective Matrix4 on the whole
// plane, a CustomPainter for the field, rings, connector and avatars, and two
// controllers: a linear 60-second orbit, and a one-shot settle after a search.
// The orbit is the only ambient loop in the product; it pauses when the map
// leaves the viewport, when the tab is hidden, and under
// MediaQuery.disableAnimations.
//
// Below 360 px the map becomes a flat, readable list of nearby people. A phone
// that narrow should get the fact, not a compressed instrument.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_avatar.dart';

/// One person on the map. Deliberately tiny: the map never needs a Candidate.
class NeighborNode {
  const NeighborNode({
    required this.id,
    required this.name,
    required this.subject,
    required this.score,
    this.tint,
  });

  final String id;
  final String name;
  final String subject;
  final int score;
  final Color? tint;
}

class NeighborMap3D extends StatefulWidget {
  const NeighborMap3D({
    required this.nodes,
    this.height = 420,
    this.userLabel = 'You',
    this.selectedId,
    this.searchTick = 0,
    this.onSelect,
    this.background = AppColors.ink,
    this.showLegend = true,
    super.key,
  });

  final List<NeighborNode> nodes;
  final double height;
  final String userLabel;
  final String? selectedId;

  /// Increment to re-ring the map after a search. The 500 ms gesture is the
  /// result set visibly arriving, not a spinner.
  final int searchTick;
  final ValueChanged<NeighborNode>? onSelect;
  final Color background;
  final bool showLegend;

  @override
  State<NeighborMap3D> createState() => _NeighborMap3DState();
}

class _NeighborMap3DState extends State<NeighborMap3D>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: Motion.orbit,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.flip,
    value: 1,
  );

  static const int _maxNodes = 12;

  Offset _tilt = Offset.zero;
  Offset _tiltTarget = Offset.zero;
  String? _hoverId;
  String? _tappedId;
  Size _size = Size.zero;
  List<_NodeLayout> _layouts = const <_NodeLayout>[];
  bool _reduce = false;
  bool _visible = true;
  bool _paused = false;
  bool _dragging = false;
  bool _checkScheduled = false;
  double _manualSpin = 0;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orbit.addListener(_tick);
    _pulse.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = Motion.reduced(context);

    final ScrollPosition? next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _scrollPosition)) {
      _scrollPosition?.removeListener(_scheduleVisibility);
      _scrollPosition = next;
      _scrollPosition?.addListener(_scheduleVisibility);
    }

    _syncMotion();
    _scheduleVisibility();
  }

  @override
  void didUpdateWidget(NeighborMap3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTick != widget.searchTick) {
      _tappedId = null;
      if (!_reduce) _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_scheduleVisibility);
    _orbit.removeListener(_tick);
    _pulse.removeListener(_tick);
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _syncMotion();
  }

  void _tick() {
    if (!mounted) return;
    final Offset next = Offset.lerp(_tilt, _tiltTarget, 0.16)!;
    setState(() => _tilt = next);
  }

  void _syncMotion() {
    final bool routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final bool shouldRun =
        !_reduce && _visible && !_paused && !_dragging && routeCurrent;
    if (shouldRun) {
      if (!_orbit.isAnimating) _orbit.repeat();
    } else {
      _orbit.stop();
    }
  }

  void _scheduleVisibility() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _syncVisibility();
    });
  }

  void _syncVisibility() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final Offset origin = box.localToGlobal(Offset.zero);
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final bool visible =
        origin.dy < screenHeight && origin.dy + box.size.height > 0;
    if (visible == _visible) return;
    setState(() => _visible = visible);
    _syncMotion();
  }

  String? get _activeId => _hoverId ?? _tappedId ?? widget.selectedId;

  _NodeLayout? _hitTest(Offset local) {
    for (int i = _layouts.length - 1; i >= 0; i--) {
      final _NodeLayout layout = _layouts[i];
      if ((local - layout.position).distance <= layout.radius + 8) {
        return layout;
      }
    }
    return null;
  }

  void _onHover(PointerHoverEvent event) {
    if (_reduce) return;
    final _NodeLayout? hit = _hitTest(event.localPosition);
    if (hit?.node.id != _hoverId) {
      setState(() => _hoverId = hit?.node.id);
    }
    if (_size.width > 0 && _size.height > 0) {
      _tiltTarget = Offset(
        (event.localPosition.dx / _size.width - 0.5) * 2,
        (event.localPosition.dy / _size.height - 0.5) * 2,
      );
    }
  }

  void _onExit(PointerExitEvent event) {
    if (_hoverId == null) return;
    setState(() => _hoverId = null);
    _tiltTarget = Offset.zero;
  }

  void _onTap(TapUpDetails details) {
    final _NodeLayout? hit = _hitTest(details.localPosition);
    setState(() {
      _tappedId = hit?.node.id;
      _hoverId = hit?.node.id;
    });
    if (hit != null) widget.onSelect?.call(hit.node);
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
    _syncMotion();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_size.width <= 0 || _size.height <= 0) return;
    setState(() {
      _manualSpin += (details.delta.dx / _size.width) * 1.8;
      final double pitch =
          (_tiltTarget.dy + details.delta.dy / _size.height * 0.9)
              .clamp(-0.7, 0.7);
      _tiltTarget = Offset(_tiltTarget.dx, pitch);
    });
  }

  void _onPanEnd() {
    _dragging = false;
    _syncMotion();
  }

  List<_NodeLayout> _layoutNodes(List<NeighborNode> nodes) {
    final double w = _size.width;
    final double h = _size.height;
    final Offset center = Offset(w / 2, h * 0.5);
    final double base = math.min(w * 0.44, h * 0.47);
    final double baseDisc =
        (math.min(w, h) * 0.055).clamp(16.0, 27.0);
    final double angle = _reduce ? 0.55 : _orbit.value * math.pi * 2;
    final double t = _reduce ? 1 : Curves.easeOutCubic.transform(_pulse.value);
    final double ringProgress = 0.88 + 0.12 * t;
    final String? active = _activeId;

    // Closeness is the map's one promise, so it must survive any caller that
    // hands the nodes over in another order. The nearest ring and the largest
    // disc belong to the highest score, in order.
    final List<NeighborNode> ordered = List<NeighborNode>.of(nodes)
      ..sort((NeighborNode a, NeighborNode b) => b.score.compareTo(a.score));
    final int count = ordered.length;

    final List<_NodeLayout> layouts = <_NodeLayout>[];
    for (int i = 0; i < count; i++) {
      final int ring = math.min(2, (i * 3) ~/ count);
      final double ringFactor = <double>[0.6, 0.82, 1.0][ring];
      final double radiusX = base * ringFactor * ringProgress;
      final double radiusY =
          radiusX * <double>[0.30, 0.36, 0.42][ring] * ringProgress;
      final double phase =
          (i / count) * math.pi * 2 + angle + _manualSpin + ring * 0.65;
      final double depth = math.sin(phase) * (1 - ring * 0.06);
      final bool isActive = ordered[i].id == active;
      final double closeness = count == 1 ? 1 : 1 - i / (count - 1);
      // Rank sets the size; depth only breathes ±3% around it, so a nearer
      // match can never end up drawn smaller than a distant one.
      final double scale = isActive
          ? 1.28
          : (0.82 + 0.25 * closeness) * (0.97 + 0.03 * ((depth + 1) / 2));
      final double radius = baseDisc * scale;
      final Offset position = Offset(
        center.dx + math.cos(phase) * radiusX,
        center.dy +
            math.sin(phase) * radiusY -
            (isActive ? math.min(10, h * 0.025) : 0),
      );
      layouts.add(
        _NodeLayout(
          node: ordered[i],
          position: position,
          radius: radius,
          depth: depth,
          opacity: isActive
              ? 1
              : (0.52 + 0.30 * closeness + 0.18 * ((depth + 1) / 2)),
          active: isActive,
          top: ordered[i].score == _topScore(ordered),
        ),
      );
    }

    // Back nodes first, so a front avatar always overlaps the one behind it.
    layouts.sort((_NodeLayout a, _NodeLayout b) {
      if (a.active != b.active) return a.active ? 1 : -1;
      return a.depth.compareTo(b.depth);
    });
    return layouts;
  }

  int _topScore(List<NeighborNode> nodes) {
    int top = 0;
    for (final NeighborNode node in nodes) {
      if (node.score > top) top = node.score;
    }
    return top;
  }

  @override
  Widget build(BuildContext context) {
    final List<NeighborNode> nodes =
        widget.nodes.take(_maxNodes).toList(growable: false);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // The breakpoint is about the window, not the content column: a
          // 390 px phone with 20 px gutters still has room for the map, and
          // the brief asks for the flat reading only below 360 px.
          final bool flat = MediaQuery.sizeOf(context).width <
                  AppBreakpoints.flat3d ||
              constraints.maxWidth < 280;
          if (flat) {
            return _FlatNeighbourMap(
              nodes: nodes,
              userLabel: widget.userLabel,
              background: widget.background,
              showLegend: widget.showLegend,
              onSelect: widget.onSelect,
            );
          }

          _size = Size(constraints.maxWidth, constraints.maxHeight);
          _layouts = _layoutNodes(nodes);
          final bool onInk =
              widget.background.computeLuminance() < 0.5;
          final Color fg = onInk ? AppColors.onAccent : AppColors.ink;
          final String? top = nodes.isEmpty ? null : nodes.first.name;

          final Matrix4 tilt = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(_reduce ? 0 : _tilt.dy * 0.10)
            ..rotateY(_reduce ? 0 : _tilt.dx * 0.18);

          return Semantics(
            container: true,
            label: nodes.isEmpty
                ? 'Neighbour map. Nobody is within reach yet.'
                : 'Neighbour map. ${nodes.length} people around you. '
                    'Nearest: $top.',
            hint: 'Drag to orbit. Hover or tap a person to bring them forward.',
            child: ClipRRect(
              borderRadius: Radii.softAll,
              child: ColoredBox(
                color: widget.background,
                child: Transform(
                  alignment: Alignment.center,
                  transform: tilt,
                  child: MouseRegion(
                    cursor: _hoverId != null
                        ? SystemMouseCursors.click
                        : (_dragging
                            ? SystemMouseCursors.grabbing
                            : SystemMouseCursors.grab),
                    onHover: _onHover,
                    onExit: _onExit,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _onTap,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: (_) => _onPanEnd(),
                      onPanCancel: _onPanEnd,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _NeighbourPainter(
                                  layouts: _layouts,
                                  center: Offset(
                                    constraints.maxWidth / 2,
                                    constraints.maxHeight * 0.5,
                                  ),
                                  foreground: fg,
                                  onInk: onInk,
                                  pulse: tPulse(_pulse.value, _reduce),
                                  userLabel: widget.userLabel,
                                  topScore: _topScore(nodes),
                                ),
                              ),
                            ),
                          ),
                          if (widget.showLegend)
                            Positioned(
                              left: Space.lg,
                              right: Space.lg,
                              bottom: Space.md,
                              child: ExcludeSemantics(
                                child: Row(
                                  children: <Widget>[
                                    Text(
                                      'DRAG TO ORBIT',
                                      style: AppType.micro
                                          .copyWith(
                                            fontSize: 9,
                                            letterSpacing: 1.4,
                                          )
                                          .tone(fg.withValues(alpha: 0.42)),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${nodes.length} NEARBY',
                                      style: AppType.micro
                                          .copyWith(
                                            fontSize: 9,
                                            letterSpacing: 1.4,
                                          )
                                          .tone(fg.withValues(alpha: 0.42)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double tPulse(double value, bool reduce) =>
      reduce ? 1 : Curves.easeOutCubic.transform(value.clamp(0.0, 1.0));
}

class _NodeLayout {
  const _NodeLayout({
    required this.node,
    required this.position,
    required this.radius,
    required this.depth,
    required this.opacity,
    required this.active,
    required this.top,
  });

  final NeighborNode node;
  final Offset position;
  final double radius;
  final double depth;
  final double opacity;
  final bool active;
  final bool top;
}

class _NeighbourPainter extends CustomPainter {
  _NeighbourPainter({
    required this.layouts,
    required this.center,
    required this.foreground,
    required this.onInk,
    required this.pulse,
    required this.userLabel,
    required this.topScore,
  });

  final List<_NodeLayout> layouts;
  final Offset center;
  final Color foreground;
  final bool onInk;
  final double pulse;
  final String userLabel;
  final int topScore;

  @override
  void paint(Canvas canvas, Size size) {
    _drawField(canvas, size);
    _drawRings(canvas, size);
    _drawConnector(canvas);

    for (final _NodeLayout layout in layouts) {
      _drawNode(canvas, layout);
    }

    _drawCenter(canvas);

    final _NodeLayout? active = _activeLayout();
    if (active != null) _drawCallout(canvas, size, active);
    if (layouts.isEmpty) _drawNoOne(canvas, size);
  }

  _NodeLayout? _activeLayout() {
    for (final _NodeLayout layout in layouts) {
      if (layout.active) return layout;
    }
    return null;
  }

  void _drawField(Canvas canvas, Size size) {
    final Paint dot = Paint()
      ..color = foreground.withValues(alpha: onInk ? 0.075 : 0.05);
    const double step = 28;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, dot);
      }
    }
  }

  void _drawRings(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double base = math.min(w * 0.44, h * 0.47);

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = foreground.withValues(alpha: onInk ? 0.13 : 0.10);

    for (int i = 0; i < 3; i++) {
      final double rx = base * <double>[0.6, 0.82, 1.0][i] * pulse;
      final double ry = rx * <double>[0.30, 0.36, 0.42][i] * pulse;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        ring,
      );
    }

    // Graduations on the outer ring. A map, not an ornament.
    final Paint tick = Paint()
      ..strokeWidth = 1
      ..color = foreground.withValues(alpha: onInk ? 0.22 : 0.15);
    final double rx = base * pulse;
    final double ry = rx * 0.42 * pulse;
    for (int i = 0; i < 48; i++) {
      final double a = (i / 48) * math.pi * 2;
      final double major = i % 4 == 0 ? 6 : 3;
      final Offset outer = Offset(
        center.dx + math.cos(a) * rx,
        center.dy + math.sin(a) * ry,
      );
      final Offset inner = Offset(
        center.dx + math.cos(a) * (rx - major),
        center.dy + math.sin(a) * (ry - major * 0.42),
      );
      canvas.drawLine(inner, outer, tick);
    }

    // The crosshair under the user. Two short rules, not a target.
    final Paint cross = Paint()
      ..strokeWidth = 1
      ..color = foreground.withValues(alpha: 0.28);
    canvas.drawLine(center - const Offset(44, 0), center - const Offset(20, 0), cross);
    canvas.drawLine(center + const Offset(20, 0), center + const Offset(44, 0), cross);
  }

  void _drawConnector(Canvas canvas) {
    final _NodeLayout? active = _activeLayout();
    if (active == null) return;

    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.amber.withValues(alpha: 0.72);

    final Offset a = center;
    final Offset b = active.position;
    final double distance = (b - a).distance;
    if (distance < 1) return;
    final Offset direction = (b - a) / distance;
    double travelled = 14;
    while (travelled < distance - active.radius - 4) {
      final double end = math.min(travelled + 6, distance - active.radius - 4);
      canvas.drawLine(
        a + direction * travelled,
        a + direction * end,
        line,
      );
      travelled = end + 7;
    }
  }

  void _drawCenter(Canvas canvas) {
    final Paint halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.accent.withValues(alpha: 0.55);
    canvas.drawCircle(center, 30, halo);

    final Paint fill = Paint()..color = AppColors.paperRaised;
    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.accent;
    canvas.drawCircle(center, 24, fill);
    canvas.drawCircle(center, 24, edge);

    final TextPainter label = _text(
      userLabel,
      AppType.labelSmall.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      maxWidth: 44,
    );
    label.paint(canvas, center - Offset(label.width / 2, label.height / 2));

    final TextPainter you = _text(
      'YOU',
      AppType.micro.copyWith(
        color: AppColors.inkMuted,
        fontSize: 8.5,
        letterSpacing: 1.4,
      ),
      maxWidth: 44,
    );
    you.paint(canvas, Offset(center.dx - you.width / 2, center.dy + 31));
  }

  void _drawNode(Canvas canvas, _NodeLayout layout) {
    final double r = layout.radius;
    final Color dye = layout.node.tint ?? TMAvatar.dyeFor(layout.node.name);
    final double opacity = layout.opacity;

    if (layout.active) {
      canvas.drawCircle(
        layout.position,
        r + 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.amber.withValues(alpha: 0.8),
      );
    } else if (layout.top) {
      canvas.drawCircle(
        layout.position,
        r + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.amber.withValues(alpha: 0.7 * opacity),
      );
    }

    canvas.drawCircle(
      layout.position,
      r,
      Paint()..color = dye.withValues(alpha: opacity),
    );
    canvas.drawCircle(
      layout.position,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = layout.active ? 2 : 1
        ..color = (layout.active ? AppColors.amber : AppColors.paperRaised)
            .withValues(alpha: layout.active ? 1 : 0.42 * opacity),
    );

    final TextPainter initials = _text(
      TMAvatar.initialsOf(layout.node.name),
      AppType.label.copyWith(
        color: AppColors.onAccent.withValues(alpha: opacity),
        fontSize: r * 0.66,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      maxWidth: r * 1.7,
    );
    initials.paint(
      canvas,
      layout.position - Offset(initials.width / 2, initials.height / 2),
    );

    if (layout.top && !layout.active) {
      canvas.drawCircle(
        layout.position + Offset(r * 0.72, -r * 0.72),
        3.4,
        Paint()..color = AppColors.amber,
      );
    }
  }

  void _drawCallout(Canvas canvas, Size size, _NodeLayout layout) {
    const double pad = 12;
    final TextPainter name = _text(
      layout.node.name,
      AppType.sectionTitle.copyWith(fontSize: 15, height: 1.1),
      maxWidth: 132,
    );
    final TextPainter subject = _text(
      layout.node.subject,
      AppType.bodySmall.copyWith(color: AppColors.inkMuted, fontSize: 12),
      maxWidth: 132,
    );
    final TextPainter score = _text(
      '${layout.node.score}',
      AppType.figure.copyWith(
        color: AppColors.accent,
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: 44,
    );
    final TextPainter match = _text(
      'MATCH',
      AppType.micro.copyWith(
        color: AppColors.inkMuted,
        fontSize: 8,
        letterSpacing: 1.2,
      ),
      maxWidth: 44,
    );

    final double boxW =
        (math.max(name.width, subject.width) + score.width + pad * 3)
            .clamp(168.0, 218.0);
    const double boxH = 60;
    final bool toLeft = layout.position.dx > center.dx;
    double x = toLeft
        ? layout.position.dx - layout.radius - 14 - boxW
        : layout.position.dx + layout.radius + 14;
    x = x.clamp(12.0, math.max(12.0, size.width - boxW - 12));
    final double y = (layout.position.dy - boxH / 2)
        .clamp(12.0, math.max(12.0, size.height - boxH - 12));

    final Rect rect = Rect.fromLTWH(x, y, boxW, boxH);
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawShadow(Path()..addRRect(rrect), const Color(0x77000000), 12, false);
    canvas.drawRRect(rrect, Paint()..color = AppColors.paperRaised);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.rule,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 0.5, y + 12, 2.5, boxH - 24),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.accent,
    );

    name.paint(canvas, Offset(x + pad + 4, y + 11));
    subject.paint(canvas, Offset(x + pad + 4, y + 32));
    score.paint(
      canvas,
      Offset(x + boxW - pad - score.width, y + 10),
    );
    match.paint(
      canvas,
      Offset(x + boxW - pad - match.width, y + 31),
    );
  }

  void _drawNoOne(Canvas canvas, Size size) {
    final TextPainter line = _text(
      'No one within reach yet',
      AppType.body.copyWith(
        color: foreground.withValues(alpha: 0.62),
        fontSize: 13,
      ),
      maxWidth: size.width - 80,
    );
    line.paint(
      canvas,
      Offset(center.dx - line.width / 2, center.dy + 56),
    );
  }

  TextPainter _text(String text, TextStyle style, {required double maxWidth}) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  bool shouldRepaint(_NeighbourPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.foreground != foreground ||
      oldDelegate.layouts != layouts ||
      oldDelegate.center != center;
}

// ─────────────────────────────────────────────────────────────────────────────
// Flat fallback
// ─────────────────────────────────────────────────────────────────────────────

class _FlatNeighbourMap extends StatelessWidget {
  const _FlatNeighbourMap({
    required this.nodes,
    required this.userLabel,
    required this.background,
    required this.showLegend,
    required this.onSelect,
  });

  final List<NeighborNode> nodes;
  final String userLabel;
  final Color background;
  final bool showLegend;
  final ValueChanged<NeighborNode>? onSelect;

  @override
  Widget build(BuildContext context) {
    final bool onInk = background.computeLuminance() < 0.5;
    final Color fg = onInk ? AppColors.onAccent : AppColors.ink;
    final Color quiet = onInk ? AppColors.onInkQuiet : AppColors.inkSecondary;

    return ClipRRect(
      borderRadius: Radii.softAll,
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.paperRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      userLabel,
                      style: AppType.micro.copyWith(fontSize: 8).tone(AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    'Closest first',
                    style: AppType.micro.copyWith(fontSize: 9).tone(quiet),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: <Widget>[
                      for (final NeighborNode node in nodes)
                        GestureDetector(
                          onTap: onSelect == null ? null : () => onSelect!(node),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: Space.xs + 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.paperRaised.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(Radii.pill),
                              border: Border.all(
                                color: fg.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                TMAvatar(
                                  node.name,
                                  size: 22,
                                  tint: node.tint,
                                ),
                                const SizedBox(width: Space.sm),
                                Text(
                                  node.name,
                                  style: AppType.labelSmall.tone(fg),
                                ),
                                const SizedBox(width: Space.sm),
                                Text(
                                  '${node.score}',
                                  style: AppType.figure.copyWith(fontSize: 12).tone(
                                        node.score == _top(nodes)
                                            ? AppColors.amber
                                            : quiet,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showLegend) ...<Widget>[
                const SizedBox(height: Space.sm),
                Text(
                  'The map needs a little more width.',
                  style: AppType.bodySmall.copyWith(fontSize: 11).tone(quiet),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static int _top(List<NeighborNode> nodes) {
    int top = 0;
    for (final NeighborNode n in nodes) {
      if (n.score > top) top = n.score;
    }
    return top;
  }
}
