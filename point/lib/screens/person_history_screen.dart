import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/location_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

class LocationCluster {
  double lat;
  double lon;
  int totalSeconds;
  int pointCount;
  String? placeName;

  LocationCluster({
    required this.lat,
    required this.lon,
    this.totalSeconds = 0,
    this.pointCount = 0,
    this.placeName,
  });
}

class TrailHistoryPoint {
  final double lat;
  final double lon;
  final int timestamp;
  final double? speed;
  TrailHistoryPoint(this.lat, this.lon, this.timestamp, {this.speed});
}

class PersonHistoryScreen extends StatefulWidget {
  final String userId;
  final String displayName;
  final Color userColor;

  const PersonHistoryScreen({
    super.key,
    required this.userId,
    required this.displayName,
    required this.userColor,
  });

  @override
  State<PersonHistoryScreen> createState() => _PersonHistoryScreenState();
}

class _PersonHistoryScreenState extends State<PersonHistoryScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  int _selectedRange = 1;
  List<LocationCluster> _clusters = [];
  List<TrailHistoryPoint> _trailPoints = [];
  bool _loading = true;
  String? _error;

  // View mode: 0 = heatmap, 1 = trail playback
  int _viewMode = 0;

  // Trail playback state
  AnimationController? _playbackController;
  bool _isPlaying = false;
  double _playbackProgress = 0.0; // 0.0 to 1.0
  int _playbackSpeed = 1; // 1x, 2x, 4x, 8x
  static const _speeds = [1, 2, 4, 8];

  // Time range crop — start/end indices within _trailPoints
  RangeValues? _trailRange; // null = full range

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..addListener(() {
        setState(() => _playbackProgress = _playbackController!.value);
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _isPlaying = false);
        }
      });
    _fetchHistory();
  }

  @override
  void dispose() {
    _playbackController?.dispose();
    super.dispose();
  }

  int _sinceTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    switch (_selectedRange) {
      case 0: return now - 86400;
      case 1: return now - 604800;
      case 2: return now - 2592000;
      default: return now - 604800;
    }
  }

  int _limitForRange() {
    switch (_selectedRange) {
      case 0: return 200;
      case 1: return 500;
      case 2: return 500;
      default: return 500;
    }
  }

  Future<void> _fetchHistory() async {
    setState(() { _loading = true; _error = null; });

    try {
      final api = context.read<ApiService>();
      final history = await api.getHistory(
        widget.userId,
        since: _sinceTimestamp(),
        limit: _limitForRange(),
      );

      final places = context.read<LocationProvider>().places;
      final clusters = _clusterHistory(history, places);
      final trail = _parseTrailPoints(history);

      setState(() {
        _clusters = clusters;
        _trailPoints = trail;
        _loading = false;
      });

      _fitMapToData();
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<TrailHistoryPoint> _parseTrailPoints(List<Map<String, dynamic>> points) {
    final trail = <TrailHistoryPoint>[];
    for (final point in points) {
      if (point['encrypted_blob'] == null) continue;
      try {
        final decoded = jsonDecode(utf8.decode(base64Decode(point['encrypted_blob'])));
        final lat = (decoded['lat'] as num?)?.toDouble();
        final lon = (decoded['lon'] as num?)?.toDouble();
        final ts = (decoded['timestamp'] as num?)?.toInt();
        final speed = (decoded['speed'] as num?)?.toDouble();
        if (lat != null && lon != null && ts != null) {
          trail.add(TrailHistoryPoint(lat, lon, ts, speed: speed));
        }
      } catch (_) { continue; }
    }
    trail.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return trail;
  }

  List<LocationCluster> _clusterHistory(
    List<Map<String, dynamic>> points,
    List<Map<String, dynamic>> places,
  ) {
    final clusters = <LocationCluster>[];

    for (final point in points) {
      double? lat;
      double? lon;

      if (point['encrypted_blob'] != null) {
        try {
          final decoded = jsonDecode(utf8.decode(base64Decode(point['encrypted_blob'])));
          lat = (decoded['lat'] as num?)?.toDouble();
          lon = (decoded['lon'] as num?)?.toDouble();
        } catch (_) { continue; }
      }

      lat ??= (point['lat'] as num?)?.toDouble();
      lon ??= (point['lon'] as num?)?.toDouble();

      if (lat == null || lon == null) continue;

      LocationCluster? nearest;
      double nearestDist = double.infinity;

      for (final cluster in clusters) {
        final dist = _haversine(lat, lon, cluster.lat, cluster.lon);
        if (dist < 200 && dist < nearestDist) {
          nearest = cluster;
          nearestDist = dist;
        }
      }

      if (nearest != null) {
        final total = nearest.pointCount + 1;
        nearest.lat = (nearest.lat * nearest.pointCount + lat) / total;
        nearest.lon = (nearest.lon * nearest.pointCount + lon) / total;
        nearest.pointCount = total;
        nearest.totalSeconds += 300;
      } else {
        clusters.add(LocationCluster(lat: lat, lon: lon, totalSeconds: 300, pointCount: 1));
      }
    }

    for (final cluster in clusters) {
      for (final place in places) {
        final placeLat = (place['lat'] as num?)?.toDouble();
        final placeLon = (place['lon'] as num?)?.toDouble();
        final placeRadius = (place['radius'] as num?)?.toDouble() ?? 200;
        final placeName = place['name'] as String?;

        if (placeLat != null && placeLon != null && placeName != null) {
          if (_haversine(cluster.lat, cluster.lon, placeLat, placeLon) < placeRadius) {
            cluster.placeName = placeName;
            break;
          }
        }
      }
    }

    clusters.sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
    return clusters;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180;

  /// Get the cropped trail points based on the time range selector.
  List<TrailHistoryPoint> get _activeTrail {
    if (_trailRange == null || _trailPoints.isEmpty) return _trailPoints;
    final start = _trailRange!.start.round().clamp(0, _trailPoints.length - 1);
    final end = _trailRange!.end.round().clamp(start + 1, _trailPoints.length);
    return _trailPoints.sublist(start, end);
  }

  void _updatePlaybackDuration() {
    final baseDuration = 15; // seconds at 1x
    _playbackController?.duration = Duration(seconds: baseDuration ~/ _playbackSpeed);
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_playbackSpeed);
    _playbackSpeed = _speeds[(idx + 1) % _speeds.length];
    _updatePlaybackDuration();
    if (_isPlaying) {
      _playbackController?.forward(from: _playbackProgress);
    }
    setState(() {});
  }

  void _fitMapToData() {
    if (_mapController == null) return;
    final points = _viewMode == 0
        ? _clusters.map((c) => LatLng(c.lat, c.lon)).toList()
        : _trailPoints.map((p) => LatLng(p.lat, p.lon)).toList();

    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }

    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.005, minLon - 0.005),
        northeast: LatLng(maxLat + 0.005, maxLon + 0.005),
      ),
      60,
    ));
  }

  // ==================== Trail playback ====================

  Set<Polyline> _buildTrailPolylines() {
    final trail = _activeTrail;
    if (trail.isEmpty) return {};
    final visibleCount = (_playbackProgress * trail.length).ceil().clamp(1, trail.length);
    final visible = trail.sublist(0, visibleCount);

    final polylines = <Polyline>{};

    // Faded trail (full path up to current point)
    if (visible.length > 1) {
      polylines.add(Polyline(
        polylineId: const PolylineId('trail_bg'),
        points: visible.map((p) => LatLng(p.lat, p.lon)).toList(),
        color: widget.userColor.withValues(alpha: 0.2),
        width: 3,
      ));
    }

    // Bright recent segment (last 20% of visible trail)
    final recentStart = (visible.length * 0.8).floor().clamp(0, visible.length - 1);
    final recent = visible.sublist(recentStart);
    if (recent.length > 1) {
      polylines.add(Polyline(
        polylineId: const PolylineId('trail_recent'),
        points: recent.map((p) => LatLng(p.lat, p.lon)).toList(),
        color: widget.userColor,
        width: 5,
      ));
    }

    return polylines;
  }

  Set<Marker> _buildTrailMarkers() {
    final trail = _activeTrail;
    if (trail.isEmpty) return {};
    final visibleCount = (_playbackProgress * trail.length).ceil().clamp(1, trail.length);
    final currentPoint = trail[visibleCount - 1];

    return {
      Marker(
        markerId: const MarkerId('trail_head'),
        position: LatLng(currentPoint.lat, currentPoint.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          HSLColor.fromColor(widget.userColor).hue,
        ),
        anchor: const Offset(0.5, 0.5),
      ),
      // Start marker
      Marker(
        markerId: const MarkerId('trail_start'),
        position: LatLng(trail.first.lat, trail.first.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
      ),
    };
  }

  void _togglePlayback() {
    if (_activeTrail.isEmpty) return;
    if (_isPlaying) {
      _playbackController!.stop();
      setState(() => _isPlaying = false);
    } else {
      if (_playbackProgress >= 1.0) {
        _playbackController!.reset();
      }
      _playbackController!.forward(from: _playbackProgress);
      setState(() => _isPlaying = true);
    }
  }

  String _timestampForProgress(double progress) {
    final trail = _activeTrail;
    if (trail.isEmpty) return '';
    final idx = (progress * (trail.length - 1)).round();
    final ts = trail[idx].timestamp;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts > 9999999999 ? ts : ts * 1000,
    );
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ==================== Heatmap circles ====================

  Set<Circle> _buildCircles() {
    if (_clusters.isEmpty) return {};
    final maxTime = _clusters.first.totalSeconds;
    final circles = <Circle>{};

    for (int i = 0; i < _clusters.length; i++) {
      final c = _clusters[i];
      final ratio = maxTime > 0 ? c.totalSeconds / maxTime : 0.0;
      final radius = 50.0 + (450.0 * ratio);
      final opacity = 0.05 + (0.20 * ratio);

      circles.add(Circle(
        circleId: CircleId('cluster_$i'),
        center: LatLng(c.lat, c.lon),
        radius: radius,
        fillColor: widget.userColor.withValues(alpha: opacity),
        strokeColor: i == 0 ? widget.userColor.withValues(alpha: 0.5) : Colors.transparent,
        strokeWidth: i == 0 ? 2 : 0,
      ));
    }
    return circles;
  }

  String _formatDuration(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).round()}m';
    final hours = seconds / 3600;
    if (hours < 24) return '${hours.toStringAsFixed(1)}h';
    return '${(hours / 24).toStringAsFixed(1)}d';
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _clusters.fold<int>(0, (sum, c) => sum + c.totalSeconds);

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(38.627, -90.199), zoom: 10,
            ),
            circles: _viewMode == 0 ? _buildCircles() : {},
            polylines: _viewMode == 1 ? _buildTrailPolylines() : {},
            markers: _viewMode == 1 ? _buildTrailMarkers() : {},
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitMapToData();
            },
          ),

          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12, right: 12, bottom: 12,
              ),
              decoration: BoxDecoration(
                color: context.cardBg,
                boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: context.subtleBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.arrow_back_ios_new, size: 14, color: context.secondaryText),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "${widget.displayName}'s History",
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.primaryText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // View mode toggle
                      _viewToggle(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _timePill('24h', 0),
                      const SizedBox(width: 8),
                      _timePill('7d', 1),
                      const SizedBox(width: 8),
                      _timePill('30d', 2),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_loading) const Center(child: CircularProgressIndicator()),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, style: const TextStyle(color: PointColors.danger)),
              ),
            ),

          // Trail playback controls
          if (_viewMode == 1 && !_loading && _trailPoints.isNotEmpty)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16, right: 16,
              child: _buildPlaybackControls(),
            ),

          // Heatmap bottom stats
          if (_viewMode == 0 && !_loading && _clusters.isNotEmpty)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildHeatmapStats(totalSeconds),
            ),

          // Empty state
          if (!_loading && _clusters.isEmpty && _trailPoints.isEmpty && _error == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: context.tertiaryText),
                  const SizedBox(height: 12),
                  Text('No history available',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.secondaryText)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: context.subtleBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewToggleBtn(Icons.blur_on_rounded, 0, 'Heatmap'),
          _viewToggleBtn(Icons.route_rounded, 1, 'Trail'),
        ],
      ),
    );
  }

  Widget _viewToggleBtn(IconData icon, int mode, String tooltip) {
    final selected = _viewMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _viewMode = mode);
        if (mode == 1 && _playbackProgress == 0) {
          _playbackController?.value = 1.0;
          _playbackProgress = 1.0;
        }
        _fitMapToData();
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? PointColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: selected ? Colors.white : context.secondaryText),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    final trail = _activeTrail;
    final timeLabel = _timestampForProgress(_playbackProgress);
    final pointCount = trail.length;
    final visibleCount = (_playbackProgress * pointCount).ceil().clamp(1, pointCount);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time range crop — pick which portion of history to play
          if (_trailPoints.length > 2) ...[
            Row(
              children: [
                Icon(Icons.content_cut_rounded, size: 12, color: context.secondaryText),
                const SizedBox(width: 4),
                Text('TIME RANGE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: context.secondaryText)),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: widget.userColor.withValues(alpha: 0.5),
                inactiveTrackColor: context.subtleBg,
                rangeValueIndicatorShape: const PaddleRangeSliderValueIndicatorShape(),
                showValueIndicator: ShowValueIndicator.always,
              ),
              child: RangeSlider(
                values: _trailRange ?? RangeValues(0, _trailPoints.length.toDouble()),
                min: 0,
                max: _trailPoints.length.toDouble(),
                divisions: _trailPoints.length,
                labels: RangeLabels(
                  _trailPoints.isNotEmpty ? _timestampFromIndex((_trailRange?.start ?? 0).round()) : '',
                  _trailPoints.isNotEmpty ? _timestampFromIndex((_trailRange?.end ?? _trailPoints.length).round().clamp(0, _trailPoints.length - 1)) : '',
                ),
                onChanged: (values) {
                  setState(() {
                    _trailRange = values;
                    _playbackController?.reset();
                    _playbackProgress = 0;
                    _isPlaying = false;
                  });
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
          // Current time label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trail.isNotEmpty ? _timestampForProgress(0) : '',
                style: TextStyle(fontSize: 10, color: context.secondaryText),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PointColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(timeLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PointColors.accent)),
              ),
              Text(
                trail.isNotEmpty ? _timestampForProgress(1.0) : '',
                style: TextStyle(fontSize: 10, color: context.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Playback scrubber
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: widget.userColor,
              inactiveTrackColor: context.subtleBg,
              thumbColor: widget.userColor,
              overlayColor: widget.userColor.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _playbackProgress,
              onChanged: (v) {
                _playbackController?.stop();
                setState(() {
                  _playbackProgress = v;
                  _playbackController?.value = v;
                  _isPlaying = false;
                });
              },
            ),
          ),
          // Play controls + speed
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind
              IconButton(
                icon: Icon(Icons.replay_rounded, color: context.secondaryText, size: 20),
                onPressed: () {
                  _playbackController?.reset();
                  setState(() { _playbackProgress = 0; _isPlaying = false; });
                },
              ),
              const SizedBox(width: 4),
              // Play/Pause
              GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: widget.userColor,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: widget.userColor.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Speed button
              GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.subtleBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.dividerClr),
                  ),
                  child: Text('${_playbackSpeed}x',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _playbackSpeed > 1 ? widget.userColor : context.primaryText,
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$visibleCount/$pointCount',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.secondaryText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timestampFromIndex(int idx) {
    if (idx < 0 || idx >= _trailPoints.length) return '';
    final ts = _trailPoints[idx].timestamp;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts > 9999999999 ? ts : ts * 1000);
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildHeatmapStats(int totalSeconds) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 20, offset: const Offset(0, -4))],
      ),
      padding: EdgeInsets.only(
        top: 16, left: 16, right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: context.dividerClr, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Text('LOCATIONS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: context.tertiaryText)),
          const SizedBox(height: 8),
          ...List.generate(
            _clusters.length > 5 ? 5 : _clusters.length,
            (i) {
              final c = _clusters[i];
              final pct = totalSeconds > 0 ? (c.totalSeconds / totalSeconds * 100).round() : 0;
              final label = c.placeName ?? '${c.lat.toStringAsFixed(2)}, ${c.lon.toStringAsFixed(2)}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: i == 0 ? widget.userColor : widget.userColor.withValues(alpha: 0.3 + 0.7 * (1 - i / 5)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.primaryText),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: context.subtleBg,
                          valueColor: AlwaysStoppedAnimation(widget.userColor),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: Text('$pct% - ${_formatDuration(c.totalSeconds)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.secondaryText),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _timePill(String label, int index) {
    final selected = _selectedRange == index;
    return GestureDetector(
      onTap: () {
        if (_selectedRange != index) {
          setState(() => _selectedRange = index);
          _playbackController?.reset();
          _playbackProgress = 0;
          _isPlaying = false;
          _fetchHistory();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? PointColors.accent : context.subtleBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: selected ? Colors.white : context.secondaryText)),
      ),
    );
  }
}
