import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/item.dart';
import '../providers.dart';

class ItemState {
  final List<Item> items;

  const ItemState({this.items = const []});

  ItemState copyWith({List<Item>? items}) {
    return ItemState(items: items ?? this.items);
  }
}

class ItemNotifier extends Notifier<ItemState> {
  @override
  ItemState build() {
    return const ItemState();
  }

  Future<void> loadItems() async {
    final api = ref.read(apiServiceProvider);
    try {
      final items = await api.listItems();
      state = state.copyWith(items: items);
    } catch (e) {
      debugPrint('ItemNotifier error: $e');
    }
  }

  Future<Item?> createItem(
    String name,
    String trackerType, {
    String? sourceId,
  }) async {
    final api = ref.read(apiServiceProvider);
    try {
      final item = await api.createItem(name, trackerType, sourceId: sourceId);
      state = state.copyWith(items: [...state.items, item]);
      return item;
    } catch (_) {
      return null;
    }
  }
}
