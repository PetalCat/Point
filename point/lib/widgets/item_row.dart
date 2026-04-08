import 'package:flutter/material.dart';
import '../models/item.dart';
import '../theme.dart';

class ItemRow extends StatelessWidget {
  final Item item;

  const ItemRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.trackerType) {
      'airtag' => Icons.key_rounded,
      'tile' => Icons.location_on_rounded,
      'smarttag' => Icons.phone_android_rounded,
      _ => Icons.inventory_2_rounded,
    };

    final (badgeLabel, badgeColor) = switch (item.trackerType) {
      'airtag' => ('Find My', const Color(0xFFE85D5D)),
      'tile' => ('Tile', const Color(0xFFC49A5A)),
      'smarttag' => ('SmartTag', const Color(0xFF5A8AAB)),
      _ => ('Tracker', const Color(0xFF999999)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(icon, size: 18, color: badgeColor),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.primaryText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.shares.isEmpty
                      ? 'Not shared'
                      : '${item.shares.length} share${item.shares.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: context.midGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
