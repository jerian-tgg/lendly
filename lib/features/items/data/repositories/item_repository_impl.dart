import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:lendly/features/items/domain/entities/item.dart';
import 'package:lendly/features/items/domain/repositories/item_repository.dart';

class ItemRepositoryImpl implements ItemRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Item>> getAllItems() {
    return _firestore
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList());
  }

  @override
  Stream<List<Item>> getItemsByOwner(String ownerId) {
    return _firestore
        .collection('items')
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList());
  }

  // Cloudinary upload configuration
  final String cloudName = 'dpnsayn8m'; // REPLACE with your Cloudinary cloud name
  final String uploadPreset = 'lendly_preset'; // REPLACE with your upload preset

  @override
  Future<List<String>> uploadImages(List<String> imagePaths) async {
    List<String> imageUrls = [];
    for (var path in imagePaths) {
      final url = await uploadToCloudinary(File(path));
      imageUrls.add(url);
    }
    return imageUrls;
  }

  Future<String> uploadToCloudinary(File file) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

    var request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final resStr = await response.stream.bytesToString();
    final resJson = json.decode(resStr);

    if (response.statusCode == 200) {
      return resJson['secure_url']; // Cloudinary image URL
    } else {
      throw Exception('Cloudinary upload failed: $resStr');
    }
  }

  @override
  Future<void> addItem(Item item) async {
    await _firestore.collection('items').add(item.toMap());
  }

  @override
  Future<void> updateItem(String itemId, Item item) async {
    await _firestore.collection('items').doc(itemId).update(item.toMap());
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await _firestore.collection('items').doc(itemId).delete();
  }
}
