// items/domain/item_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Item {
  final String id;
  final String name;
  final String description;
  final String category;
  final int quantity;
  final double price;
  final DateTime availableFrom;
  final DateTime availableTo;
  final String condition;
  final List<String> imageUrls;
  final String ownerId;
  final String ownerName;
  final DateTime createdAt;
  final bool isAvailable;

  Item({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.quantity,
    required this.price,
    required this.availableFrom,
    required this.availableTo,
    required this.condition,
    required this.imageUrls,
    required this.ownerId,
    required this.ownerName,
    required this.createdAt,
    required this.isAvailable,
  });

  factory Item.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Item(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      quantity: data['quantity'] ?? 1,
      price: (data['price'] ?? 0).toDouble(),
      availableFrom: (data['availableFrom'] as Timestamp).toDate(),
      availableTo: (data['availableTo'] as Timestamp).toDate(),
      condition: data['condition'] ?? 'Like New',
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? 'Anonymous',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isAvailable: data['isAvailable'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'quantity': quantity,
      'price': price,
      'availableFrom': availableFrom,
      'availableTo': availableTo,
      'condition': condition,
      'imageUrls': imageUrls,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'createdAt': createdAt,
      'isAvailable': isAvailable,
    };
  }
}