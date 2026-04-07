class Item {
  final String id;
  final String ownerId;
  final String name;
  final String trackerType;
  final String? sourceId;
  final List<ItemShare> shares;

  Item({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.trackerType,
    this.sourceId,
    required this.shares,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'],
    ownerId: json['owner_id'],
    name: json['name'],
    trackerType: json['tracker_type'],
    sourceId: json['source_id'],
    shares: (json['shares'] as List? ?? [])
        .map((s) => ItemShare.fromJson(s))
        .toList(),
  );
}

class ItemShare {
  final String targetType;
  final String targetId;
  final String precision;

  ItemShare({
    required this.targetType,
    required this.targetId,
    required this.precision,
  });

  factory ItemShare.fromJson(Map<String, dynamic> json) => ItemShare(
    targetType: json['target_type'],
    targetId: json['target_id'],
    precision: json['precision'],
  );
}
