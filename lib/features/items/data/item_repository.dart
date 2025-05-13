// items/data/item_repository.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:lendly/features/items/domain/item_model.dart';

class ItemRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Stream<List<Item>> getAllItems() {
    return _firestore
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Item.fromFirestore(doc))
        .toList());
  }

  Stream<List<Item>> getItemsByOwner(String ownerId) {
    return _firestore
        .collection('items')
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Item.fromFirestore(doc))
        .toList());
  }

  Future<List<String>> uploadImages(List<String> imagePaths) async {
    List<String> imageUrls = [];
    for (var path in imagePaths) {
      final ref = _storage.ref().child('items/${DateTime.now().millisecondsSinceEpoch}');
      await ref.putFile(File(path));
      imageUrls.add(await ref.getDownloadURL());
    }
    return imageUrls;
  }

  Future<void> addItem(Item item) async {
    await _firestore.collection('items').add(item.toMap());
  }

  Future<void> updateItem(Item item) async {
    await _firestore.collection('items').doc(item.id).update(item.toMap());
  }

  Future<void> deleteItem(String itemId) async {
    await _firestore.collection('items').doc(itemId).delete();
  }
}