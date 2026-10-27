// ─────────────────────────────────────────────────────────────────────────────
// The map.
//
// One reusable, read-only map for a public area: a soft circle around an
// approximate centre, OpenStreetMap tiles, and a text alternative that carries
// the same fact for anyone who cannot see it. Small versions do not take
// gestures; the full profile map enables pan and zoom (and nothing else — no
// rotation, because a map that can be turned is a map that can be lost).
//
// The map is deliberately incapable of showing an exact address. It receives a
// [PublicPlace], whose coordinates are already the neighbourhood or city centre
// chosen by that person's privacy setting, and it draws a circle rather than a
// pin. There is no house-shaped mark in this product.
//
// When tiles cannot load, the map becomes a solid neutral surface carrying a
// map mark, the area name and a quiet line saying the tiles need a connection.
// The area name and distance are never replaced by an error.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// The coordinate type is part of flutter_map's public API, but flutter_map does
// not re-export it. Importing the transitive package avoids a second declared
// dependency for one value type.
// ignore: depend_on_referenced_packages
import 'package:latlong2/latlong.dart';
import 'package:tutormatch/data/models.dart';
import 'package:tutormatch/theme/app_theme.dart';
import 'package:tutormatch/widgets/tm_icon.dart';

/// Set to false by widget tests so no tile request leaves the process. The map
/// still renders its neutral ground, circles and markers; only the OSM layer is
/// omitted. Production leaves this true.
bool debugLoadMapTiles = true;

/// A transparent 1×1 tile used in place of a failed request. It keeps the map's
/// own error tile out of the picture; the offline line explains the rest.
final ImageProvider _blankTile = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

/// The map plus its caption: the unit used on a person's page and on the
/// profile. It reads only a [PublicPlace], so a hidden location has no object
/// to pass and therefore no card.
class LocationCard extends StatelessWidget {
  const LocationCard({
    required this.place,
    this.distanceKm,
    this.height = 200,
    this.interactive = false,
    super.key,
  });

  final PublicPlace place;

  /// Distance from the viewer, when this card sits on a matched person's page.
  final double? distanceKm;

  final double height;

  /// True only for the full map on your own profile. Everything else is still.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final String? distance = distanceKm == null
        ? null
        : describeDistance(distanceKm!);
    final String label = place.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LocationMap(
          centerLatitude: place.latitude,
          centerLongitude: place.longitude,
          height: height,
          interactive: interactive,
          showCenterCircle: true,
          caption: label,
          captionNote: distance,
          fallbackTitle: label,
          fallbackNote: distance,
          semanticLabel:
              'Approximate area: ${place.label}'
              '${distance == null ? '' : ', $distance'}.',
        ),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: TMIcon(
                TMIconName.pin,
                size: 13,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                place.cityOnly
                    ? 'City only — the neighbourhood is not shown.'
                    : 'Approximate area — exact addresses are never shown.',
                style: AppType.bodySmall.quieter,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One tappable person on a results map. Kept as plain doubles so callers do not
/// need to import the coordinate package themselves.
class LocationPin {
  const LocationPin({
    required this.latitude,
    required this.longitude,
    required this.child,
    required this.semanticLabel,
    this.onTap,
  });

  final double latitude;
  final double longitude;
  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;
}

class LocationMap extends StatefulWidget {
  const LocationMap({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.semanticLabel,
    this.zoom = 12.4,
    this.height = 200,
    this.pins = const <LocationPin>[],
    this.fitPins = false,
    this.showCenterCircle = true,
    this.showPinCircles = false,
    this.interactive = false,
    this.caption,
    this.captionNote,
    this.fallbackTitle,
    this.fallbackNote,
    super.key,
  });

  final double centerLatitude;
  final double centerLongitude;

  /// The text alternative. It should say the area and, when there is one, the
  /// distance — the same facts the sighted map carries.
  final String semanticLabel;

  final double zoom;
  final double height;
  final List<LocationPin> pins;

  /// Fit every pin inside the frame instead of using [centerLatitude],
  /// [centerLongitude] and [zoom]. Used by the results map.
  final bool fitPins;

  final bool showCenterCircle;
  final bool showPinCircles;

  /// Pan and zoom only. Small, in-page maps stay still so a scroll or a tap
  /// never turns into a pan.
  final bool interactive;

  /// The small paper label in the corner: "Highbury, London", "about 3 km away".
  final String? caption;
  final String? captionNote;

  /// What to say when the tiles are unavailable. Defaults to [caption].
  final String? fallbackTitle;
  final String? fallbackNote;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  bool _tilesFailed = false;

  bool get _offline => !debugLoadMapTiles || _tilesFailed;

  LatLng get _center => LatLng(widget.centerLatitude, widget.centerLongitude);

  String get _cameraKey {
    final String pins = widget.pins
        .map((LocationPin p) => '${p.latitude},${p.longitude}')
        .join('|');
    return '${widget.centerLatitude},${widget.centerLongitude},'
        '${widget.fitPins},${widget.zoom},$pins';
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (!mounted || _tilesFailed) return;
    // The callback arrives while images are resolving, but deferring the
    // rebuild keeps it out of any build that might be in progress.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tilesFailed) setState(() => _tilesFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = <LatLng>[
      for (final LocationPin pin in widget.pins)
        LatLng(pin.latitude, pin.longitude),
    ];

    return Semantics(
      container: true,
      image: true,
      label: widget.semanticLabel,
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.paperSunken,
          borderRadius: Radii.sharpAll,
          border: Border.all(color: AppColors.ruleStrong),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (!_offline) const _MapGround(),
            if (!_offline)
              FlutterMap(
                key: ValueKey<String>(_cameraKey),
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: widget.zoom,
                  initialCameraFit: widget.fitPins && points.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(points),
                          padding: const EdgeInsets.all(56),
                          maxZoom: 13,
                        )
                      : null,
                  minZoom: 3,
                  maxZoom: 17,
                  backgroundColor: Colors.transparent,
                  interactionOptions: InteractionOptions(
                    flags: widget.interactive
                        ? InteractiveFlag.drag |
                              InteractiveFlag.flingAnimation |
                              InteractiveFlag.pinchMove |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom |
                              InteractiveFlag.scrollWheelZoom
                        : InteractiveFlag.none,
                  ),
                ),
                children: <Widget>[
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.tutormatch',
                    errorImage: _blankTile,
                    errorTileCallback: _onTileError,
                    tileDisplay: const TileDisplay.instantaneous(),
                  ),
                  if (widget.showCenterCircle)
                    CircleLayer(circles: <CircleMarker>[_circle(_center)]),
                  if (widget.showPinCircles && points.isNotEmpty)
                    CircleLayer(
                      circles: <CircleMarker>[
                        for (final LatLng point in points) _circle(point),
                      ],
                    ),
                  if (widget.pins.isNotEmpty)
                    MarkerLayer(
                      markers: <Marker>[
                        for (final LocationPin pin in widget.pins)
                          Marker(
                            point: LatLng(pin.latitude, pin.longitude),
                            width: 60,
                            height: 60,
                            child: _Pin(pin: pin),
                          ),
                      ],
                    ),
                ],
              ),
            if (_offline)
              _OfflineMap(
                title: widget.fallbackTitle ?? widget.caption,
                note: widget.fallbackNote,
              )
            else
              Positioned(
                left: Space.sm,
                right: Space.sm,
                bottom: Space.sm,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    // The caption gets every pixel the attribution does not.
                    // A Spacer here would split the leftover in half and squeeze
                    // a two-fact caption on a phone for no reason.
                    if (widget.caption != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: _MapCaption(
                            caption: widget.caption!,
                            note: widget.captionNote,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: Space.sm),
                    const _Attribution(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  CircleMarker _circle(LatLng point) => CircleMarker(
    point: point,
    radius: 1200,
    useRadiusInMeter: true,
    color: AppColors.accent.withValues(alpha: 0.13),
    borderColor: AppColors.accent.withValues(alpha: 0.55),
    borderStrokeWidth: 1.5,
  );
}

/// A faint grid, so a map that is still loading reads as a made surface rather
/// than a failed image. The offline fallback paints over it with a solid
/// neutral panel.
class _MapGround extends StatelessWidget {
  const _MapGround();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MapGroundPainter());
  }
}

class _MapGroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.rule.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const double step = 34;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Pin extends StatelessWidget {
  const _Pin({required this.pin});

  final LocationPin pin;

  @override
  Widget build(BuildContext context) {
    final Widget mark = Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: pin.child,
    );

    if (pin.onTap == null) return Center(child: mark);

    return Semantics(
      button: true,
      label: pin.semanticLabel,
      child: Tooltip(
        message: pin.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pin.onTap,
            child: Center(child: mark),
          ),
        ),
      ),
    );
  }
}

class _MapCaption extends StatelessWidget {
  const _MapCaption({required this.caption, this.note});

  final String caption;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.paperRaised.withValues(alpha: 0.94),
        borderRadius: Radii.sharpAll,
        border: Border.all(color: AppColors.ruleStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const TMIcon(TMIconName.pin, size: 13, color: AppColors.accent),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: caption,
                style: AppType.bodySmall.tone(AppColors.ink),
                children: note == null
                    ? null
                    : <InlineSpan>[
                        TextSpan(
                          text: ' · $note',
                          style: AppType.bodySmall.tone(AppColors.inkMuted),
                        ),
                      ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral stand-in when tiles cannot load. It carries the same facts the
/// map would — the area and, where there is one, the distance — so a failed
/// request never becomes a blank rectangle.
class _OfflineMap extends StatelessWidget {
  const _OfflineMap({this.title, this.note});

  final String? title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('map-offline'),
      color: AppColors.paperSunken,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xl,
            vertical: Space.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const TMIcon(TMIconName.map, size: 28, color: AppColors.inkMuted),
              const SizedBox(height: Space.sm),
              Text(
                title ?? 'Approximate area',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.tone(AppColors.inkSecondary),
              ),
              if (note != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodySmall.quieter,
                ),
              ],
              const SizedBox(height: Space.xs),
              Text(
                'Map tiles need a connection.',
                textAlign: TextAlign.center,
                style: AppType.micro.tone(AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      color: AppColors.paperRaised.withValues(alpha: 0.9),
      child: Text(
        '© OpenStreetMap contributors',
        style: AppType.bodySmall
            .copyWith(fontSize: 10.5)
            .tone(AppColors.inkMuted),
      ),
    );
  }
}
