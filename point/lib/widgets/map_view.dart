import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart' show Position;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config.dart';
import '../models/map_provider.dart';
import '../providers.dart';
import '../theme.dart';

class MapView extends ConsumerStatefulWidget {
  final Function(String userId)? onPersonTap;
  final bool showTrails;
  final Function(LatLng)? onLongPress;

  const MapView({
    super.key,
    this.onPersonTap,
    this.showTrails = true,
    this.onLongPress,
  });
  @override
  ConsumerState<MapView> createState() => MapViewState();
}

class MapViewState extends ConsumerState<MapView> {
  GoogleMapController? _controller;
  fm.MapController? _fmController;
  bool _initialFitDone = false;
  final Map<String, BitmapDescriptor> _iconCache = {};
  final Map<String, LatLng> _animatedPositions = {};
  final Map<String, LatLng> _targetPositions = {};
  Timer? _animationTimer;
  String? _followingUserId;

  void followUser(String? userId) {
    final locationNotifier = ref.read(locationProvider.notifier);
    // Stop viewing previous person
    if (_followingUserId != null && _followingUserId != userId) {
      locationNotifier.stopViewing();
    }
    setState(() => _followingUserId = userId);
    if (userId != null) {
      locationNotifier.startViewing(userId); // nudge for fresh location
      final target = _targetPositions[userId];
      if (target != null) {
        _animateCameraTo(target, zoom: 15);
      }
    } else {
      locationNotifier.stopViewing();
    }
  }

  @override
  void initState() {
    super.initState();
    _animationTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _animateMarkers(),
    );
  }

  void _animateMarkers() {
    bool changed = false;
    for (final entry in _targetPositions.entries) {
      final current = _animatedPositions[entry.key];
      final target = entry.value;
      if (current == null) {
        _animatedPositions[entry.key] = target;
        changed = true;
        continue;
      }
      final newLat =
          current.latitude + (target.latitude - current.latitude) * 0.3;
      final newLng =
          current.longitude + (target.longitude - current.longitude) * 0.3;
      if ((newLat - target.latitude).abs() > 0.000001 ||
          (newLng - target.longitude).abs() > 0.000001) {
        _animatedPositions[entry.key] = LatLng(newLat, newLng);
        changed = true;
      } else {
        _animatedPositions[entry.key] = target;
      }
    }
    // Only auto-follow when explicitly following someone (tap on person).
    // Don't auto-center on self — let user pan freely.
    if (_followingUserId != null &&
        _animatedPositions.containsKey(_followingUserId) &&
        changed) {
      final pos = _animatedPositions[_followingUserId!]!;
      if (_controller != null) {
        _controller!.moveCamera(CameraUpdate.newLatLng(pos));
      } else if (_fmController != null) {
        _fmController!.move(
          ll.LatLng(pos.latitude, pos.longitude),
          _fmController!.camera.zoom,
        );
      }
    }
    if (changed) setState(() {});
  }

  /// Call this from outside to fit all markers
  void fitAllMarkers() {
    final locationState = ref.read(locationProvider);
    final people = locationState.people;
    final myPos = locationState.myPosition;

    final allPoints = <LatLng>[];
    if (myPos != null) allPoints.add(LatLng(myPos.latitude, myPos.longitude));
    for (final person in people.values) {
      if (person.lat != 0 || person.lon != 0) {
        allPoints.add(LatLng(person.lat, person.lon));
      }
    }

    if (allPoints.length > 1) {
      _fitBounds(allPoints);
    } else if (allPoints.length == 1) {
      _animateCameraTo(allPoints.first, zoom: 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationProvider);
    final auth = ref.watch(authProvider);
    final people = locationState.people;
    final myPos = locationState.myPosition;

    final markers = <Marker>{};
    final allPoints = <LatLng>[];

    // My position as a custom bubble
    if (myPos != null) {
      final myLatLng = LatLng(myPos.latitude, myPos.longitude);
      _targetPositions['_me'] = myLatLng;
      final animatedMyLatLng = _animatedPositions['_me'] ?? myLatLng;
      allPoints.add(animatedMyLatLng);

      final myName = auth.displayName ?? auth.userId?.split('@').first ?? 'Me';
      final myInitial = myName.isNotEmpty ? myName[0].toUpperCase() : 'M';

      _getCircleIcon(
        myInitial,
        const Color(0xFF1A1A1A),
        isStale: false,
        online: true,
        isMe: true,
      ).then((icon) {
        if (mounted && _iconCache['_me'] != icon) {
          setState(() => _iconCache['_me'] = icon);
        }
      });

      markers.add(
        Marker(
          markerId: const MarkerId('_me'),
          position: animatedMyLatLng,
          icon:
              _iconCache['_me'] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: myName),
          zIndex: 10, // always on top
        ),
      );
    }

    // People markers (with precision-based rendering)
    final precisionCircles = <Circle>{};
    for (final entry in people.entries) {
      final person = entry.value;
      if (person.lat == 0 && person.lon == 0) continue;

      final targetPos = LatLng(person.lat, person.lon);
      _targetPositions[person.userId] = targetPos;
      final pos = _animatedPositions[person.userId] ?? targetPos;
      allPoints.add(pos);
      final name = person.userId.split('@').first;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final color = _colorForUser(person.userId);
      final isStale =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - person.timestamp) >
          7200;

      if (person.precision == 'approximate') {
        // 500m radius semi-transparent circle
        precisionCircles.add(
          Circle(
            circleId: CircleId('approx_${person.userId}'),
            center: pos,
            radius: 500,
            fillColor: color.withValues(alpha: 0.10),
            strokeColor: color.withValues(alpha: 0.25),
            strokeWidth: 2,
          ),
        );
        // Still show initial marker in the center
        _getCircleIcon(
          initial,
          color,
          isStale: isStale,
          online: person.online,
        ).then((icon) {
          if (mounted && _iconCache[person.userId] != icon) {
            setState(() => _iconCache[person.userId] = icon);
          }
        });
        markers.add(
          Marker(
            markerId: MarkerId(person.userId),
            position: pos,
            icon:
                _iconCache[person.userId] ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(title: '$name (approx)'),
            onTap: () => widget.onPersonTap?.call(person.userId),
          ),
        );
      } else if (person.precision == 'city') {
        // 5km radius very faint circle, name label but no precise dot
        precisionCircles.add(
          Circle(
            circleId: CircleId('city_${person.userId}'),
            center: pos,
            radius: 5000,
            fillColor: color.withValues(alpha: 0.05),
            strokeColor: color.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        );
        // Use a transparent marker just for the info window / tap target
        markers.add(
          Marker(
            markerId: MarkerId(person.userId),
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            anchor: const Offset(0.5, 0.5),
            visible: false,
            infoWindow: InfoWindow(title: '$name (city)'),
            onTap: () => widget.onPersonTap?.call(person.userId),
          ),
        );
      } else {
        // Exact precision — normal marker
        _getCircleIcon(
          initial,
          color,
          isStale: isStale,
          online: person.online,
        ).then((icon) {
          if (mounted && _iconCache[person.userId] != icon) {
            setState(() => _iconCache[person.userId] = icon);
          }
        });
        markers.add(
          Marker(
            markerId: MarkerId(person.userId),
            position: pos,
            icon:
                _iconCache[person.userId] ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(title: name),
            onTap: () => widget.onPersonTap?.call(person.userId),
          ),
        );
      }
    }

    // Build trail polylines with smooth curves (only if enabled)
    final polylines = <Polyline>{};
    if (widget.showTrails) {
      for (final entry in locationState.trails.entries) {
        final trail = entry.value;
        if (trail.length < 2) continue;
        final color = _colorForUser(entry.key);
        final rawPoints = trail.map((p) => LatLng(p.lat, p.lon)).toList();
        // Append current animated position so trail connects to marker
        final currentPos = _animatedPositions[entry.key];
        if (currentPos != null) rawPoints.add(currentPos);
        // Smooth the path with Catmull-Rom spline interpolation
        final smoothed = _smoothPath(rawPoints);
        polylines.add(
          Polyline(
            polylineId: PolylineId('trail_${entry.key}'),
            points: smoothed,
            color: color.withValues(alpha: 0.35),
            width: 4,
          ),
        );
      }
    } // end showTrails

    // Auto-fit on first load — includes "me" if we have a position
    final hasController = _controller != null || _fmController != null;
    if (hasController && !_initialFitDone && allPoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (allPoints.length > 1) {
          _fitBounds(allPoints);
        } else {
          _animateCameraTo(allPoints.first, zoom: 15);
        }
        _initialFitDone = true;
      });
    }

    final initialTarget = myPos != null
        ? LatLng(myPos.latitude, myPos.longitude)
        : allPoints.isNotEmpty
        ? _averagePoint(allPoints)
        : const LatLng(37.7749, -122.4194);

    // Build circles for saved places
    final circles = <Circle>{};

    // Build polygons for saved places
    final polygons = <Polygon>{};

    // Saved-place data in provider-neutral form for flutter_map
    final placeCircleData = <_CircleData>[];
    final placePolygonData = <_PolygonData>[];

    // Draw saved places
    for (final place in locationState.places) {
      final placeId = place['id'] as String? ?? '';
      final geometryType = place['geometry_type'] as String? ?? 'circle';
      if (geometryType == 'polygon') {
        List<dynamic>? pts;
        final raw = place['polygon_points'];
        if (raw is String) {
          try {
            pts = jsonDecode(raw) as List<dynamic>;
          } catch (_) {}
        } else if (raw is List) {
          pts = raw;
        }
        if (pts != null && pts.length >= 3) {
          final latLngs = pts
              .map(
                (p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lon'] as num).toDouble(),
                ),
              )
              .toList();
          polygons.add(
            Polygon(
              polygonId: PolygonId('place_$placeId'),
              points: latLngs,
              strokeColor: PointColors.accent.withValues(alpha: 0.3),
              fillColor: PointColors.accent.withValues(alpha: 0.04),
              strokeWidth: 2,
            ),
          );
          placePolygonData.add(_PolygonData(
            points: latLngs,
            strokeColor: PointColors.accent.withValues(alpha: 0.3),
            fillColor: PointColors.accent.withValues(alpha: 0.04),
          ));
        }
      } else {
        final placeLat = (place['lat'] as num?)?.toDouble();
        final placeLon = (place['lon'] as num?)?.toDouble();
        final radius = (place['radius'] as num?)?.toDouble();
        if (placeLat != null && placeLon != null && radius != null) {
          circles.add(
            Circle(
              circleId: CircleId('place_$placeId'),
              center: LatLng(placeLat, placeLon),
              radius: radius,
              strokeColor: PointColors.accent.withValues(alpha: 0.3),
              fillColor: PointColors.accent.withValues(alpha: 0.04),
              strokeWidth: 2,
            ),
          );
          placeCircleData.add(_CircleData(
            lat: placeLat,
            lon: placeLon,
            radiusMeters: radius,
            strokeColor: PointColors.accent.withValues(alpha: 0.3),
            fillColor: PointColors.accent.withValues(alpha: 0.04),
          ));
        }
      }
    }

    // Add precision-based circles for approximate/city people
    circles.addAll(precisionCircles);

    // --- Provider switch ---
    if (AppConfig.mapProvider == MapProviderType.google) {
      return _buildGoogleMap(
        context: context,
        initialTarget: initialTarget,
        markers: markers,
        polylines: polylines,
        circles: circles,
        polygons: polygons,
      );
    } else {
      return _buildFlutterMap(
        context: context,
        initialTarget: initialTarget,
        people: people,
        myPos: myPos,
        auth: auth,
        precisionCircles: precisionCircles,
        polylines: polylines,
        placeCircleData: placeCircleData,
        placePolygonData: placePolygonData,
      );
    }
  }

  // ─── Google Maps renderer (existing, optimized path) ───
  Widget _buildGoogleMap({
    required BuildContext context,
    required LatLng initialTarget,
    required Set<Marker> markers,
    required Set<Polyline> polylines,
    required Set<Circle> circles,
    required Set<Polygon> polygons,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      colorScheme: isDark ? MapColorScheme.dark : MapColorScheme.light,
      markers: markers,
      polylines: polylines,
      circles: circles,
      polygons: polygons,
      padding: const EdgeInsets.only(top: 60, bottom: 40),
      onMapCreated: (controller) {
        _controller = controller;
      },
      onLongPress: (pos) => widget.onLongPress?.call(pos),
    );
  }

  // ─── flutter_map renderer (OSM / Mapbox / self-hosted) ───
  Widget _buildFlutterMap({
    required BuildContext context,
    required LatLng initialTarget,
    required Map<String, PersonLocation> people,
    required Position? myPos,
    required AuthState auth,
    required Set<Circle> precisionCircles,
    required Set<Polyline> polylines,
    required List<_CircleData> placeCircleData,
    required List<_PolygonData> placePolygonData,
  }) {
    // Determine tile URL
    String tileUrl;
    switch (AppConfig.mapProvider) {
      case MapProviderType.osm:
        tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
        break;
      case MapProviderType.mapbox:
        final token = AppConfig.mapboxToken ?? '';
        tileUrl = 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}@2x?access_token=$token';
        break;
      case MapProviderType.selfHosted:
        tileUrl = AppConfig.selfHostedTileUrl ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
        final token = AppConfig.selfHostedToken;
        if (token != null && token.isNotEmpty) {
          tileUrl += '${tileUrl.contains('?') ? '&' : '?'}access_token=$token';
        }
        break;
      default:
        tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }

    // Build flutter_map markers as real widgets (resolution-independent)
    final fmMarkers = <fm.Marker>[];

    // "Me" marker
    if (myPos != null) {
      final animatedMyLatLng = _animatedPositions['_me'] ??
          LatLng(myPos.latitude, myPos.longitude);
      final myName = auth.displayName ?? auth.userId?.split('@').first ?? 'Me';
      final myInitial = myName.isNotEmpty ? myName[0].toUpperCase() : 'M';

      fmMarkers.add(fm.Marker(
        point: ll.LatLng(animatedMyLatLng.latitude, animatedMyLatLng.longitude),
        width: 44,
        height: 44,
        child: _FlutterMapCircleMarker(
          initial: myInitial,
          color: const Color(0xFF1A1A1A),
          isMe: true,
          isStale: false,
          online: true,
        ),
      ));
    }

    // People markers
    for (final entry in people.entries) {
      final person = entry.value;
      if (person.lat == 0 && person.lon == 0) continue;
      if (person.precision == 'city') continue; // city = no visible dot

      final pos = _animatedPositions[person.userId] ??
          LatLng(person.lat, person.lon);
      final name = person.userId.split('@').first;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final color = _colorForUser(person.userId);
      final isStale =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - person.timestamp) > 7200;

      fmMarkers.add(fm.Marker(
        point: ll.LatLng(pos.latitude, pos.longitude),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => widget.onPersonTap?.call(person.userId),
          child: _FlutterMapCircleMarker(
            initial: initial,
            color: color,
            isMe: false,
            isStale: isStale,
            online: person.online,
          ),
        ),
      ));
    }

    // Build flutter_map circle markers from precision circles + saved places
    final fmCircles = <fm.CircleMarker>[];
    for (final c in precisionCircles) {
      // Use a pixel approximation: precision circles are 500m or 5000m.
      // flutter_map CircleMarker uses pixels, so we use useRadiusInMeter.
      fmCircles.add(fm.CircleMarker(
        point: ll.LatLng(c.center.latitude, c.center.longitude),
        radius: c.radius, // meters
        useRadiusInMeter: true,
        color: c.fillColor,
        borderColor: c.strokeColor,
        borderStrokeWidth: c.strokeWidth.toDouble(),
      ));
    }
    for (final cd in placeCircleData) {
      fmCircles.add(fm.CircleMarker(
        point: ll.LatLng(cd.lat, cd.lon),
        radius: cd.radiusMeters,
        useRadiusInMeter: true,
        color: cd.fillColor,
        borderColor: cd.strokeColor,
        borderStrokeWidth: 2,
      ));
    }

    // Build flutter_map polylines from trail polylines
    final fmPolylines = <fm.Polyline>[];
    for (final p in polylines) {
      fmPolylines.add(fm.Polyline(
        points: p.points.map((pt) => ll.LatLng(pt.latitude, pt.longitude)).toList(),
        color: p.color,
        strokeWidth: p.width.toDouble(),
      ));
    }

    // Build flutter_map polygons from saved places
    final fmPolygons = <fm.Polygon>[];
    for (final pd in placePolygonData) {
      fmPolygons.add(fm.Polygon(
        points: pd.points.map((pt) => ll.LatLng(pt.latitude, pt.longitude)).toList(),
        color: pd.fillColor,
        borderColor: pd.strokeColor,
        borderStrokeWidth: 2,
      ));
    }

    _fmController ??= fm.MapController();

    // Deliver controller on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_fmController != null && !_initialFitDone) {
        // controller is ready
      }
    });

    return fm.FlutterMap(
      mapController: _fmController!,
      options: fm.MapOptions(
        initialCenter: ll.LatLng(initialTarget.latitude, initialTarget.longitude),
        initialZoom: 14,
        onLongPress: widget.onLongPress != null
            ? (_, point) => widget.onLongPress!(LatLng(point.latitude, point.longitude))
            : null,
      ),
      children: [
        fm.TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'dev.petalcat.point',
        ),
        if (fmCircles.isNotEmpty)
          fm.CircleLayer(circles: fmCircles),
        if (fmPolylines.isNotEmpty)
          fm.PolylineLayer(polylines: fmPolylines),
        if (fmPolygons.isNotEmpty)
          fm.PolygonLayer(polygons: fmPolygons),
        if (fmMarkers.isNotEmpty)
          fm.MarkerLayer(markers: fmMarkers),
      ],
    );
  }

  /// Animate camera to a position, works with either controller.
  void _animateCameraTo(LatLng target, {double zoom = 15}) {
    if (_controller != null) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } else if (_fmController != null) {
      _fmController!.move(
        ll.LatLng(target.latitude, target.longitude),
        zoom,
      );
    }
  }

  LatLng _averagePoint(List<LatLng> points) {
    double lat = 0, lon = 0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLon = points.first.longitude, maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    if (_controller != null) {
      _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLon),
            northeast: LatLng(maxLat, maxLon),
          ),
          80,
        ),
      );
    } else if (_fmController != null) {
      _fmController!.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds(
            ll.LatLng(minLat, minLon),
            ll.LatLng(maxLat, maxLon),
          ),
          padding: const EdgeInsets.all(80),
        ),
      );
    }
  }

  Future<BitmapDescriptor> _getCircleIcon(
    String initial,
    Color color, {
    bool isStale = false,
    bool online = false,
    bool isMe = false,
  }) async {
    final cacheKey = '$initial-${color.value}-$isStale-$online-$isMe';
    if (_iconCache.containsKey(cacheKey)) return _iconCache[cacheKey]!;

    // Render at 3x regardless of device DPR for consistent crisp quality
    const renderScale = 3.0;
    final displaySize = isMe ? 44.0 : 36.0;
    final canvasSize = displaySize * renderScale;
    final center = Offset(canvasSize / 2, canvasSize / 2);
    final borderWidth = (isMe ? 2.5 : 2.0) * renderScale;
    final radius = canvasSize / 2 - (2 * renderScale);
    final opacity = isStale ? 0.35 : 1.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Outer glow (subtle)
    if (!isStale) {
      canvas.drawCircle(
        center,
        radius + 2 * renderScale,
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * renderScale)
          ..isAntiAlias = true,
      );
    }

    // Shadow
    canvas.drawCircle(
      Offset(center.dx, center.dy + 1.5 * renderScale),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * renderScale)
        ..isAntiAlias = true,
    );

    // Fill with subtle gradient
    final gradient = ui.Gradient.radial(
      Offset(center.dx - radius * 0.25, center.dy - radius * 0.25),
      radius * 1.5,
      [
        Color.lerp(color, Colors.white, 0.15)!.withValues(alpha: opacity),
        color.withValues(alpha: opacity),
      ],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = gradient
        ..isAntiAlias = true,
    );

    // White border
    canvas.drawCircle(
      center,
      radius - borderWidth / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..isAntiAlias = true,
    );

    // Letter — render with paragraph for better quality
    final fontSize = (isMe ? 16.0 : 13.0) * renderScale;
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    ))
      ..pushStyle(ui.TextStyle(
        color: Colors.white.withValues(alpha: opacity),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ))
      ..addText(initial);
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: canvasSize));
    canvas.drawParagraph(
      paragraph,
      Offset(0, (canvasSize - paragraph.height) / 2),
    );

    // Online indicator dot
    if (online && !isStale) {
      final dotR = 4.0 * renderScale;
      final dotC = Offset(
        canvasSize - dotR - 0.5 * renderScale,
        canvasSize - dotR - 0.5 * renderScale,
      );
      // Dot shadow
      canvas.drawCircle(
        Offset(dotC.dx, dotC.dy + 0.5 * renderScale),
        dotR,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 * renderScale)
          ..isAntiAlias = true,
      );
      // Green dot
      canvas.drawCircle(
        dotC,
        dotR,
        Paint()
          ..color = const Color(0xFF22C55E)
          ..isAntiAlias = true,
      );
      // White ring
      canvas.drawCircle(
        dotC,
        dotR,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * renderScale
          ..isAntiAlias = true,
      );
    }

    final image = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final descriptor = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: displaySize,
      height: displaySize,
    );
    _iconCache[cacheKey] = descriptor;
    return descriptor;
  }

  /// Catmull-Rom spline interpolation for smooth trails
  List<LatLng> _smoothPath(List<LatLng> points) {
    if (points.length < 3) return points;

    final result = <LatLng>[];
    const segments = 8; // interpolated points per segment

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i > 0 ? i - 1 : 0];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];

      for (int j = 0; j < segments; j++) {
        final t = j / segments;
        final t2 = t * t;
        final t3 = t2 * t;

        // Catmull-Rom matrix
        final lat =
            0.5 *
            ((2 * p1.latitude) +
                (-p0.latitude + p2.latitude) * t +
                (2 * p0.latitude -
                        5 * p1.latitude +
                        4 * p2.latitude -
                        p3.latitude) *
                    t2 +
                (-p0.latitude +
                        3 * p1.latitude -
                        3 * p2.latitude +
                        p3.latitude) *
                    t3);
        final lng =
            0.5 *
            ((2 * p1.longitude) +
                (-p0.longitude + p2.longitude) * t +
                (2 * p0.longitude -
                        5 * p1.longitude +
                        4 * p2.longitude -
                        p3.longitude) *
                    t2 +
                (-p0.longitude +
                        3 * p1.longitude -
                        3 * p2.longitude +
                        p3.longitude) *
                    t3);
        result.add(LatLng(lat, lng));
      }
    }
    // Add final point
    result.add(points.last);
    return result;
  }

  Color _colorForUser(String userId) {
    return PointColors.colorForUser(userId);
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _controller?.dispose();
    _fmController?.dispose();
    super.dispose();
  }
}

// ─── Helper data classes ───

class _CircleData {
  final double lat;
  final double lon;
  final double radiusMeters;
  final Color strokeColor;
  final Color fillColor;
  const _CircleData({
    required this.lat,
    required this.lon,
    required this.radiusMeters,
    required this.strokeColor,
    required this.fillColor,
  });
}

class _PolygonData {
  final List<LatLng> points;
  final Color strokeColor;
  final Color fillColor;
  const _PolygonData({
    required this.points,
    required this.strokeColor,
    required this.fillColor,
  });
}

// ─── Resolution-independent circle marker widget for flutter_map ───

class _FlutterMapCircleMarker extends StatelessWidget {
  final String initial;
  final Color color;
  final bool isMe;
  final bool isStale;
  final bool online;

  const _FlutterMapCircleMarker({
    required this.initial,
    required this.color,
    required this.isMe,
    required this.isStale,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final size = isMe ? 44.0 : 36.0;
    final opacity = isStale ? 0.35 : 1.0;
    final effectiveColor = color.withValues(alpha: opacity);
    final highlightColor =
        Color.lerp(color, Colors.white, 0.15)!.withValues(alpha: opacity);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Main circle with gradient-like effect
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.25, -0.25),
                radius: 0.75,
                colors: [highlightColor, effectiveColor],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95 * opacity),
                width: isMe ? 2.5 : 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25 * opacity),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
                if (!isStale)
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: opacity),
                  fontWeight: FontWeight.w800,
                  fontSize: isMe ? 16 : 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Online indicator dot
          if (online && !isStale)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
