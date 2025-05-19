import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class BorrowedItemsScreen extends StatelessWidget {
  final String userId = FirebaseAuth.instance.currentUser!.uid;

  BorrowedItemsScreen({super.key});

  void _openChat(BuildContext context, String ownerId) {
    // Implement your navigation to chat screen here
    // Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(ownerId: ownerId)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat feature coming soon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borrowRequestRef = FirebaseFirestore.instance.collection('borrowList');
    final itemsRef = FirebaseFirestore.instance.collection('items');

    return StreamBuilder<QuerySnapshot>(
      stream: borrowRequestRef
          .where('borrowerID', isEqualTo: userId)
          .orderBy('startDate', descending: true)
          .snapshots(),
      builder: (context, borrowSnapshot) {
        if (borrowSnapshot.hasError) {
          return Center(child: Text('Error: ${borrowSnapshot.error}'));
        }
        if (borrowSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final borrowDocs = borrowSnapshot.data?.docs ?? [];
        if (borrowDocs.isEmpty) {
          return const Center(child: Text('No borrowed items found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: borrowDocs.length,
          itemBuilder: (context, index) {
            final borrowData = borrowDocs[index].data() as Map<String, dynamic>;
            final itemId = borrowData['itemID'] as String;

            return FutureBuilder<DocumentSnapshot>(
              future: itemsRef.doc(itemId).get(),
              builder: (context, itemSnapshot) {
                if (itemSnapshot.hasError) return const Text('Error loading item');
                if (!itemSnapshot.hasData) return const CircularProgressIndicator();

                final itemData = itemSnapshot.data!.data() as Map<String, dynamic>?;

                if (itemData == null) return const Text('Item not found');

                final itemName = itemData['name'] ?? 'Unnamed Item';
                final imageUrls = (itemData['imageUrls'] as List<dynamic>?) ?? [];
                final ownerId = itemData['ownerId'] ?? '';

                final startDate = borrowData['startDate'] != null
                    ? (borrowData['startDate'] as Timestamp).toDate()
                    : null;
                final endDate = borrowData['endDate'] != null
                    ? (borrowData['endDate'] as Timestamp).toDate()
                    : null;
                final status = borrowData['status'] ?? 'unknown';

                return Card(
                  margin: const EdgeInsets.only(bottom: 20),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: imageUrls.isNotEmpty
                            ? Image.network(
                          imageUrls[0],
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator(value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                  : null)),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            height: 180,
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image, size: 80, color: Colors.grey),
                          ),
                        )
                            : Container(
                          height: 180,
                          color: Colors.grey[300],
                          child: const Icon(Icons.inventory, size: 80, color: Colors.grey),
                        ),
                      ),

                      // Details Padding
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (startDate != null)
                              Text(
                                'Borrowed from: ${DateFormat('MMM d, yyyy').format(startDate)}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            if (endDate != null)
                              Text(
                                'Due by: ${DateFormat('MMM d, yyyy').format(endDate)}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Status: $status',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: status.toLowerCase() == 'returned'
                                    ? Colors.green
                                    : status.toLowerCase() == 'pending'
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Chat Owner'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF90E0F3),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => _openChat(context, ownerId),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
