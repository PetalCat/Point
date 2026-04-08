import 'package:flutter/material.dart';
import '../config.dart';
import '../models/map_provider.dart';
import '../theme.dart';

class MapProviderPicker extends StatefulWidget {
  final MapProviderType? initialValue;
  final ValueChanged<MapProviderType>? onChanged;
  final bool showTokenFields;

  const MapProviderPicker({
    super.key,
    this.initialValue,
    this.onChanged,
    this.showTokenFields = true,
  });

  /// Show as a bottom sheet and return the selected provider.
  static Future<MapProviderType?> show(BuildContext context) {
    return showModalBottomSheet<MapProviderType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _MapProviderSheet(),
    );
  }

  @override
  State<MapProviderPicker> createState() => _MapProviderPickerState();
}

class _MapProviderPickerState extends State<MapProviderPicker> {
  late MapProviderType _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue ?? AppConfig.mapProvider;
  }

  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    // Show Google + OSM by default, Mapbox + self-hosted behind "Advanced"
    final mainProviders = [MapProviderType.google, MapProviderType.osm];
    final advancedProviders = [MapProviderType.mapbox, MapProviderType.selfHosted];
    final visibleProviders = _showAdvanced
        ? MapProviderType.values.toList()
        : mainProviders;

    // If current selection is advanced, show all
    if (advancedProviders.contains(_selected) && !_showAdvanced) {
      _showAdvanced = true;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visibleProviders.map((provider) {
        final isSelected = _selected == provider;
        return GestureDetector(
          onTap: () {
            setState(() => _selected = provider);
            widget.onChanged?.call(provider);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? PointColors.accent.withValues(alpha: 0.08)
                  : context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? PointColors.accent.withValues(alpha: 0.4)
                    : context.dividerClr,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? PointColors.accent.withValues(alpha: 0.15)
                        : context.subtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(provider),
                    size: 18,
                    color: isSelected ? PointColors.accent : context.secondaryText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(provider.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.primaryText,
                              )),
                          if (provider == MapProviderType.osm) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FF88).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('MOST PRIVATE',
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
                                      color: Color(0xFF00FF88))),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(provider.description,
                          style: TextStyle(fontSize: 11, color: context.secondaryText)),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: PointColors.accent, size: 22),
              ],
            ),
          ),
        );
      }),
        if (!_showAdvanced)
          GestureDetector(
            onTap: () => setState(() => _showAdvanced = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Show advanced options',
                  style: TextStyle(fontSize: 12, color: context.hintText)),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(MapProviderType provider) {
    switch (provider) {
      case MapProviderType.google: return Icons.map;
      case MapProviderType.osm: return Icons.public;
      case MapProviderType.mapbox: return Icons.terrain;
      case MapProviderType.selfHosted: return Icons.dns;
    }
  }
}

class _MapProviderSheet extends StatefulWidget {
  const _MapProviderSheet();

  @override
  State<_MapProviderSheet> createState() => _MapProviderSheetState();
}

class _MapProviderSheetState extends State<_MapProviderSheet> {
  MapProviderType _selected = AppConfig.mapProvider;
  final _tokenCtl = TextEditingController(text: AppConfig.mapboxToken ?? '');
  final _tileUrlCtl = TextEditingController(text: AppConfig.selfHostedTileUrl ?? '');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
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
          const SizedBox(height: 16),
          Text('Map Provider',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.primaryText)),
          const SizedBox(height: 4),
          Text('Choose where your map tiles come from.',
              style: TextStyle(fontSize: 12, color: context.secondaryText)),
          const SizedBox(height: 16),

          MapProviderPicker(
            initialValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),

          // Mapbox token field
          if (_selected == MapProviderType.mapbox) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _tokenCtl,
              decoration: InputDecoration(
                labelText: 'Mapbox Access Token',
                hintText: 'pk.eyJ1...',
                filled: true, fillColor: context.subtleBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],

          // Self-hosted tile URL + optional token
          if (_selected == MapProviderType.selfHosted) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _tileUrlCtl,
              decoration: InputDecoration(
                labelText: 'Tile Server URL',
                hintText: 'https://tiles.example.com/{z}/{x}/{y}.png',
                filled: true, fillColor: context.subtleBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenCtl,
              decoration: InputDecoration(
                labelText: 'API Token (optional)',
                hintText: 'Leave empty if not required',
                filled: true, fillColor: context.subtleBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await AppConfig.setMapProvider(
                  _selected,
                  token: _tokenCtl.text.isNotEmpty ? _tokenCtl.text : null,
                  tileUrl: _tileUrlCtl.text.isNotEmpty ? _tileUrlCtl.text : null,
                );
                if (context.mounted) Navigator.pop(context, _selected);
              },
              style: FilledButton.styleFrom(
                backgroundColor: PointColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
