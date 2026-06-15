import '../entities/item.dart';

abstract class ItemRepository {
  Stream<List<Item>> getAllItems();
  Stream<List<Item>> getItemsByOwner(String ownerId);
  Future<List<String>> uploadImages(List<String> imagePaths);
  Future<void> addItem(Item item);
  Future<void> updateItem(String itemId, Item item);
  Future<void> deleteItem(String itemId);
}
