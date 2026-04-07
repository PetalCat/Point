import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/group_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

class PlaceCreationScreen extends StatefulWidget {
  final LatLng initialPosition;
  const PlaceCreationScreen({super.key, required this.initialPosition});

  @override
  State<PlaceCreationScreen> createState() => _PlaceCreationScreenState();
}

class _PlaceCreationScreenState extends State<PlaceCreationScreen> {
  String _mode = 'circle';
  late LatLng _center;
  double _radius = 150;
  final List<LatLng> _polygonPoints = [];
  final _nameController = TextEditingController();
  // null means personal, otherwise group id
  String? _selectedGroupId;
  bool _isPersonal = false;
  bool _notifyArrive = true;
  bool _notifyLeave = true;
  bool _saving = false;

  static const String _personalValue = '__personal__';

  @override
  void initState() {
    super.initState();
    _center = widget.initialPosition;
    // Default to personal
    _isPersonal = true;
    _selectedGroupId = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a place name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_isPersonal && _selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No group selected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_mode == 'polygon' && _polygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Polygon needs at least 3 points'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = context.read<ApiService>();
      if (_isPersonal) {
        await api.createPersonalPlace(
          name,
          geometryType: _mode,
          lat: _mode == 'circle' ? _center.latitude : null,
          lon: _mode == 'circle' ? _center.longitude : null,
          radius: _mode == 'circle' ? _radius : null,
          polygonPoints: _mode == 'polygon'
              ? _polygonPoints
                    .map((p) => {'lat': p.latitude, 'lon': p.longitude})
                    .toList()
              : null,
        );
      } else {
        await api.createPlace(
          _selectedGroupId!,
          name,
          geometryType: _mode,
          lat: _mode == 'circle' ? _center.latitude : null,
          lon: _mode == 'circle' ? _center.longitude : null,
          radius: _mode == 'circle' ? _radius : null,
          polygonPoints: _mode == 'polygon'
              ? _polygonPoints
                    .map((p) => {'lat': p.latitude, 'lon': p.longitude})
                    .toList()
              : null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupProvider>();

    // Build markers
    final markers = <Marker>{};

    if (_mode == 'circle') {
      markers.add(
        Marker(
          markerId: const MarkerId('circle_center'),
          position: _center,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: const Offset(0.5, 0.5),
          zIndex: 20,
          onDragEnd: (newPos) => setState(() => _center = newPos),
        ),
      );
    }

    if (_mode == 'polygon') {
      for (int i = 0; i < _polygonPoints.length; i++) {
        markers.add(
          Marker(
            markerId: MarkerId('poly_node_$i'),
            position: _polygonPoints[i],
            draggable: true,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
            anchor: const Offset(0.5, 0.5),
            zIndex: 20,
            onDragEnd: (newPos) => setState(() => _polygonPoints[i] = newPos),
          ),
        );
      }
    }

    // Build circles
    final circles = <Circle>{};
    if (_mode == 'circle') {
      circles.add(
        Circle(
          circleId: const CircleId('creation_circle'),
          center: _center,
          radius: _radius,
          strokeColor: PointColors.accent.withValues(alpha: 0.4),
          fillColor: PointColors.accent.withValues(alpha: 0.08),
          strokeWidth: 2,
        ),
      );
    }

    // Build polygons
    final polygons = <Polygon>{};
    if (_mode == 'polygon' && _polygonPoints.length >= 3) {
      polygons.add(
        Polygon(
          polygonId: const PolygonId('creation_polygon'),
          points: _polygonPoints,
          strokeColor: PointColors.accent.withValues(alpha: 0.4),
          fillColor: PointColors.accent.withValues(alpha: 0.08),
          strokeWidth: 2,
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.cardBg,
      body: Stack(
        children: [
          // Full-screen map
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.initialPosition,
                zoom: 16,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: markers,
              circles: circles,
              polygons: polygons,
              padding: const EdgeInsets.only(top: 100, bottom: 340),
              onTap: _mode == 'polygon'
                  ? (pos) => setState(() => _polygonPoints.add(pos))
                  : null,
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 8)],
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 20,
                        color: context.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'New Place',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.primaryText,
                      ),
                    ),
                    const Spacer(),
                    // Mode toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.subtleBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildModeChip('Circle', 'circle'),
                          const SizedBox(width: 2),
                          _buildModeChip('Polygon', 'polygon'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.shadowClr,
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.dividerClr,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Name field
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Place name (e.g. Home, Work)',
                        hintStyle: const TextStyle(
                          color: PointColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: context.subtleBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: PointColors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Circle: radius presets
                    if (_mode == 'circle') ...[
                      const Text(
                        'Radius',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: PointColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: ['50m', '150m', '300m', '500m', '1km'].map((
                          label,
                        ) {
                          final r = label == '1km'
                              ? 1000.0
                              : double.parse(label.replaceAll('m', ''));
                          final active = (_radius - r).abs() < 1;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => setState(() => _radius = r),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? PointColors.accent
                                        : context.subtleBg,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: active
                                        ? [
                                            const BoxShadow(
                                              color: PointColors.accentGlow,
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: active
                                            ? Colors.white
                                            : PointColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Polygon: point count + undo
                    if (_mode == 'polygon') ...[
                      Row(
                        children: [
                          Text(
                            '${_polygonPoints.length} points',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '-- tap map to add',
                            style: TextStyle(
                              fontSize: 12,
                              color: PointColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          if (_polygonPoints.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _polygonPoints.removeLast()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: context.subtleBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Undo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: PointColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Scope dropdown
                    const Text(
                      'Scope',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: PointColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: context.subtleBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: _isPersonal ? _personalValue : _selectedGroupId,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.primaryText,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _personalValue,
                            child: Text('Personal (just me)'),
                          ),
                          ...groups.groups.map(
                            (g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == _personalValue) {
                            _isPersonal = true;
                            _selectedGroupId = null;
                          } else {
                            _isPersonal = false;
                            _selectedGroupId = v;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Arrive/Leave toggles
                    Row(
                      children: [
                        Expanded(
                          child: _buildAlertToggle(
                            'Arrive',
                            _notifyArrive,
                            (v) => setState(() => _notifyArrive = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAlertToggle(
                            'Leave',
                            _notifyLeave,
                            (v) => setState(() => _notifyLeave = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Save button
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _saving
                              ? PointColors.accent.withValues(alpha: 0.5)
                              : PointColors.accent,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            const BoxShadow(
                              color: PointColors.accentGlow,
                              blurRadius: 12,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Save Place',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, String mode) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? PointColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : PointColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertToggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: value
              ? PointColors.accent.withValues(alpha: 0.08)
              : context.subtleBg,
          borderRadius: BorderRadius.circular(12),
          border: value
              ? Border.all(color: PointColors.accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: value ? PointColors.accent : PointColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: value ? PointColors.accent : PointColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
