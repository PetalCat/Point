import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' as ll;

import '../config.dart';
import '../models/map_provider.dart';
import '../theme.dart';

/// Unified map widget that renders Google Maps or flutter_map
/// based on the user's map provider setting.
class PointMap extends StatelessWidget {
  final double initialLat;
  final double initialLon;
  final double initialZoom;
  final List<PointMapMarker> markers;
  final List<PointMapPolyline> polylines;
  final List<PointMapCircle> circles;
  final void Function(gmap.GoogleMapController)? onGoogleMapCreated;
  final void Function(MapController)? onFlutterMapCreated;
  final void Function(double lat, double lon)? onLongPress;
  final bool myLocationEnabled;

  const PointMap({
    super.key,
    this.initialLat = 38.627,
    this.initialLon = -90.199,
    this.initialZoom = 10,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
    this.onGoogleMapCreated,
    this.onFlutterMapCreated,
    this.onLongPress,
    this.myLocationEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (AppConfig.mapProvider) {
      case MapProviderType.google:
        return _buildGoogleMap(context);
      case MapProviderType.osm:
        return _buildFlutterMap(context, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      case MapProviderType.mapbox:
        final token = AppConfig.mapboxToken ?? '';
        return _buildFlutterMap(context,
          'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}@2x?access_token=$token');
      case MapProviderType.selfHosted:
        return _buildFlutterMap(context,
          AppConfig.selfHostedTileUrl ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    }
  }

  Widget _buildGoogleMap(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(
        target: gmap.LatLng(initialLat, initialLon),
        zoom: initialZoom,
      ),
      markers: markers.map((m) => m.toGoogleMarker()).toSet(),
      polylines: polylines.map((p) => p.toGooglePolyline()).toSet(),
      circles: circles.map((c) => c.toGoogleCircle()).toSet(),
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      colorScheme: isDark ? gmap.MapColorScheme.dark : gmap.MapColorScheme.light,
      onMapCreated: onGoogleMapCreated,
      onLongPress: onLongPress != null
          ? (pos) => onLongPress!(pos.latitude, pos.longitude)
          : null,
    );
  }

  Widget _buildFlutterMap(BuildContext context, String tileUrl) {
    final mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onFlutterMapCreated?.call(mapController);
    });

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: ll.LatLng(initialLat, initialLon),
        initialZoom: initialZoom,
        onLongPress: onLongPress != null
            ? (_, point) => onLongPress!(point.latitude, point.longitude)
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'dev.petalcat.point',
        ),
        // Circles
        if (circles.isNotEmpty)
          CircleLayer(
            circles: circles.map((c) => CircleMarker(
              point: ll.LatLng(c.lat, c.lon),
              radius: c.radiusPixels ?? 20,
              color: c.fillColor,
              borderColor: c.strokeColor,
              borderStrokeWidth: c.strokeWidth,
            )).toList(),
          ),
        // Polylines
        if (polylines.isNotEmpty)
          PolylineLayer(
            polylines: polylines.map((p) => Polyline(
              points: p.points.map((pt) => ll.LatLng(pt.lat, pt.lon)).toList(),
              color: p.color,
              strokeWidth: p.width,
            )).toList(),
          ),
        // Markers
        if (markers.isNotEmpty)
          MarkerLayer(
            markers: markers.map((m) => Marker(
              point: ll.LatLng(m.lat, m.lon),
              width: 40,
              height: 40,
              child: m.child ?? Container(
                decoration: BoxDecoration(
                  color: m.color ?? PointColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    m.label ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
            )).toList(),
          ),
      ],
    );
  }
}

/// Unified marker that works with both map backends.
class PointMapMarker {
  final String id;
  final double lat;
  final double lon;
  final String? label;
  final Color? color;
  final Widget? child; // for flutter_map
  final gmap.BitmapDescriptor? googleIcon; // for google_maps
  final VoidCallback? onTap;

  const PointMapMarker({
    required this.id,
    required this.lat,
    required this.lon,
    this.label,
    this.color,
    this.child,
    this.googleIcon,
    this.onTap,
  });

  gmap.Marker toGoogleMarker() => gmap.Marker(
    markerId: gmap.MarkerId(id),
    position: gmap.LatLng(lat, lon),
    icon: googleIcon ?? gmap.BitmapDescriptor.defaultMarker,
    onTap: onTap,
    anchor: const Offset(0.5, 0.5),
  );
}

/// Unified polyline.
class PointMapPolyline {
  final String id;
  final List<PointMapLatLng> points;
  final Color color;
  final double width;

  const PointMapPolyline({
    required this.id,
    required this.points,
    this.color = Colors.blue,
    this.width = 3,
  });

  gmap.Polyline toGooglePolyline() => gmap.Polyline(
    polylineId: gmap.PolylineId(id),
    points: points.map((p) => gmap.LatLng(p.lat, p.lon)).toList(),
    color: color,
    width: width.toInt(),
  );
}

/// Unified circle.
class PointMapCircle {
  final String id;
  final double lat;
  final double lon;
  final double radiusMeters;
  final double? radiusPixels; // for flutter_map (doesn't support meter radius directly)
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const PointMapCircle({
    required this.id,
    required this.lat,
    required this.lon,
    this.radiusMeters = 100,
    this.radiusPixels,
    this.fillColor = const Color(0x203F51FF),
    this.strokeColor = const Color(0x603F51FF),
    this.strokeWidth = 2,
  });

  gmap.Circle toGoogleCircle() => gmap.Circle(
    circleId: gmap.CircleId(id),
    center: gmap.LatLng(lat, lon),
    radius: radiusMeters,
    fillColor: fillColor,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth.toInt(),
  );
}

/// Simple lat/lon point.
class PointMapLatLng {
  final double lat;
  final double lon;
  const PointMapLatLng(this.lat, this.lon);
}
