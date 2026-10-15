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
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? city;

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
    this.location,
    this.latitude,
    this.longitude,
    this.address,
    this.city,
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
      availableFrom: data['availableFrom'] != null
          ? (data['availableFrom'] as Timestamp).toDate()
          : DateTime.now(),
      availableTo: data['availableTo'] != null
          ? (data['availableTo'] as Timestamp).toDate()
          : DateTime.now(),
      condition: data['condition'] ?? 'Pending Appraisal',
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? 'Anonymous',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isAvailable: data['isAvailable'] ?? false,
      location: data['location'] is String ? data['location'] : null,
      latitude: (data['latitude'] as num?)?.toDouble() ?? (data['lat'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble() ?? (data['lng'] as num?)?.toDouble(),
      address: data['address'] is String ? data['address'] : null,
      city: data['city'] is String ? data['city'] : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'quantity': quantity,
      'price': price,
      'availableFrom': Timestamp.fromDate(availableFrom),
      'availableTo': Timestamp.fromDate(availableTo),
      'condition': condition,
      'imageUrls': imageUrls,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'createdAt': Timestamp.fromDate(createdAt),
      'isAvailable': isAvailable,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (city != null && city!.isNotEmpty) 'city': city,
    };
  }
}
