import 'package:flutter/foundation.dart';
import '../models/item.dart';
import '../services/api_service.dart';

class ItemProvider extends ChangeNotifier {
  final ApiService _api;
  List<Item> _items = [];

  List<Item> get items => _items;

  ItemProvider(this._api);

  Future<void> loadItems() async {
    try {
      _items = await _api.listItems();
    } catch (e) {
      debugPrint('ItemProvider error: $e');
    }
    notifyListeners();
  }

  Future<Item?> createItem(
    String name,
    String trackerType, {
    String? sourceId,
  }) async {
    try {
      final item = await _api.createItem(name, trackerType, sourceId: sourceId);
      _items.add(item);
      notifyListeners();
      return item;
    } catch (_) {
      return null;
    }
  }
}
