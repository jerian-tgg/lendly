import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/items/presentation/widgets/item_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _sortOption = 'Date';
  final TextEditingController _searchController = TextEditingController();

  List<String> categories = ['All', 'Electronics', 'Books', 'Clothing', 'Tools', 'Others'];

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    value: _selectedCategory,
                    items: categories.map((String category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedCategory = value!),
                  ),
                  DropdownButton<String>(
                    value: _sortOption,
                    items: const [
                      DropdownMenuItem(value: 'Date', child: Text('Newest First')),
                      DropdownMenuItem(value: 'Price', child: Text('Price: Low to High')),
                    ],
                    onChanged: (value) => setState(() => _sortOption = value!),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('items')
                .orderBy(_sortOption == 'Date' ? 'createdAt' : 'price')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];

              final filtered = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] ?? '').toString().toLowerCase();
                final category = (data['category'] ?? '').toString();
                final matchesSearch = name.contains(_searchQuery);
                final matchesCategory = _selectedCategory == 'All' || category == _selectedCategory;
                return matchesSearch && matchesCategory;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('No items found.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isOwner = data['ownerId'] == userId;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ItemCard(
                      itemId: doc.id,
                      itemData: doc.data() as Map<String, dynamic>,  // pass the whole item data
                      name: doc['name'] ?? 'No Name',
                      price: '₱${doc['price']}',
                      imagePath: (doc['imageUrls'] as List).isNotEmpty ? doc['imageUrls'][0] : '',
                      isOwner: doc['ownerId'] == FirebaseAuth.instance.currentUser?.uid,
                      isAvailable: doc['isAvailable'] ?? true,
                      onEdit: () {
                        // your edit handler here
                      },
                      onDelete: () {
                        // your delete handler here
                      },
                    )

                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
