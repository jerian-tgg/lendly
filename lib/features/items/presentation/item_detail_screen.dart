import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/chat/utils/convo_id.dart';

class ItemDetailScreen extends StatelessWidget {
  final Map<String, dynamic> itemData;
  final String itemId;

  const ItemDetailScreen({
    super.key,
    required this.itemData,
    required this.itemId,
  });

  @override
  Widget build(BuildContext context) {
    final ownerId = itemData['ownerId'];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final convoId = getConvoId(currentUserId, ownerId);

    return Scaffold(
      appBar: AppBar(
        title: Text(itemData['title'] ?? 'Item Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (itemData['imageUrl'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  itemData['imageUrl'],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),

            // Title
            Text(
              itemData['title'] ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              itemData['description'] ?? 'No description provided.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            // Category
            if (itemData['category'] != null)
              Chip(
                label: Text(itemData['category']),
                backgroundColor: Colors.blue.shade50,
              ),
            const SizedBox(height: 24),

            // Message Button
            if (ownerId != currentUserId)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          convoId: convoId,
                          receiverId: ownerId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Message Owner'),
                ),
              ),

            const SizedBox(height: 24),
            // Other items in category (optional placeholder)
            const Text(
              'Similar items in this category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('items')
                  .where('category', isEqualTo: itemData['category'])
                  .where('id', isNotEqualTo: itemId)
                  .limit(3)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();

                final items = snapshot.data!.docs;
                if (items.isEmpty) return const Text('No similar items found.');

                return Column(
                  children: items.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: data['imageUrl'] != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(data['imageUrl'], width: 50, height: 50, fit: BoxFit.cover),
                      )
                          : const Icon(Icons.image_not_supported),
                      title: Text(data['title'] ?? 'Unnamed Item'),
                      subtitle: Text(data['description'] ?? ''),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ItemDetailScreen(itemData: data, itemId: doc.id),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
