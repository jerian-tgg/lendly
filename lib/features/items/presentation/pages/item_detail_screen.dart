import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/core/utils/convo_id.dart';


class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final String itemId;

  const ItemDetailScreen({
    super.key,
    required this.itemData,
    required this.itemId,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  DateTime? _startDate;
  DateTime? _endDate;

  Future<String> createOrGetConversation({
    required String currentUserId,
    required String otherUserId,
    required String itemId, // <--- add this
  }) async {
    final convoRef = FirebaseFirestore.instance.collection('conversations');
    final querySnapshot = await convoRef
        .where('participants', arrayContains: currentUserId)
        .get();

    QueryDocumentSnapshot? existingConvo;

    try {
      existingConvo = querySnapshot.docs.firstWhere((doc) {
        final participants = List<String>.from(doc['participants']);
        return participants.contains(currentUserId) &&
            participants.contains(otherUserId) &&
            doc['itemId'] == itemId; // <--- check for itemId match too
      });
    } catch (e) {
      existingConvo = null;
    }

    if (existingConvo != null) {
      return existingConvo.id;
    } else {
      final convoId = getConvoId(currentUserId, otherUserId);
      final newConvoRef = convoRef.doc(convoId);

      await newConvoRef.set({
        'participants': [currentUserId, otherUserId],
        'itemOwnerId': otherUserId,
        'itemId': itemId, // ✅ Add this!
        'approved': false,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return convoId;
    }
  }


  Future<void> _pickDates(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.itemData['ownerId'] as String? ?? '';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isVisitor = currentUserId.isEmpty || FirebaseAuth.instance.currentUser == null;
    final itemTitle = widget.itemData['title'] ?? widget.itemData['name'] ?? 'Item Details';
    final imageUrl = widget.itemData['imageUrl'] ??
        ((widget.itemData['imageUrls'] != null && (widget.itemData['imageUrls'] as List).isNotEmpty)
            ? widget.itemData['imageUrls'][0]
            : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(itemTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey, size: 48),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              itemTitle,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.itemData['description'] ?? 'No description provided.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (widget.itemData['category'] != null)
              Chip(
                label: Text(widget.itemData['category']),
                backgroundColor: Colors.blue.shade50,
              ),
            const SizedBox(height: 24),

            if (isVisitor) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF90E0F3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline, color: Color(0xFF007799), size: 32),
                    const SizedBox(height: 8),
                    const Text(
                      'Log in to borrow this item',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Visitors can browse items, but booking and messaging the owner require an account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF90E0F3),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text('Log In / Sign Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ] else if (ownerId != currentUserId) ...[
              ElevatedButton(
                onPressed: () => _pickDates(context),
                child: Text(_startDate != null && _endDate != null
                    ? 'Borrow Dates: ${_startDate!.toLocal().toString().split(' ')[0]} - ${_endDate!.toLocal().toString().split(' ')[0]}'
                    : 'Select Borrow Dates'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_startDate == null || _endDate == null)
                      ? null
                      : () async {
                    if (ownerId.isEmpty || currentUserId.isEmpty) return;

                    final convoId = await createOrGetConversation(
                      currentUserId: currentUserId,
                      otherUserId: ownerId,
                      itemId: widget.itemId, // ✅ pass itemId here
                    );

                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          convoId: convoId,
                          currentUserId: currentUserId,
                          otherUserId: ownerId,
                          itemId: widget.itemId, otherUserName: '',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Message Owner'),
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Text(
              'Similar items in this category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('items')
                  .where('category', isEqualTo: widget.itemData['category'])
                  .where(FieldPath.documentId, isNotEqualTo: widget.itemId)
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
                        child: Image.network(
                          data['imageUrl'],
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                          : const Icon(Icons.image_not_supported),
                      title: Text(data['title'] ?? 'Unnamed Item'),
                      subtitle: Text(data['description'] ?? ''),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ItemDetailScreen(itemData: data, itemId: doc.id),
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
