import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lendly/core/utils/image_utils.dart';

class BorrowedItemsScreen extends StatefulWidget {
  const BorrowedItemsScreen({super.key});

  @override
  State<BorrowedItemsScreen> createState() => _BorrowedItemsScreenState();
}

class _BorrowedItemsScreenState extends State<BorrowedItemsScreen> {
  bool showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text("Not logged in."));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Borrowed Items (Records)"),
        backgroundColor: const Color(0xFF98259A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .where('participants', arrayContains: currentUser.uid)
            .where('approved', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final conversations = snapshot.data!.docs;

          if (conversations.isEmpty) {
            return const Center(child: Text("No approved borrowed items yet."));
          }

          final ongoing = conversations.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return !(data['isPaid'] == true &&
                data['isReceived'] == true &&
                data['isReturned'] == true &&
                data['isReturnConfirmed'] == true);
          }).toList();

          final completed = conversations.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['isPaid'] == true &&
                data['isReceived'] == true &&
                data['isReturned'] == true &&
                data['isReturnConfirmed'] == true;
          }).toList();

          return SingleChildScrollView(
            child: Column(
              children: [
                // Ongoing transactions
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ongoing.length,
                  itemBuilder: (context, index) {
                    return _buildItemTile(ongoing[index], currentUser.uid);
                  },
                ),

                // Completed Transactions Toggle
                ExpansionTile(
                  title: const Text("Completed Transactions"),
                  initiallyExpanded: showCompleted,
                  onExpansionChanged: (val) {
                    setState(() => showCompleted = val);
                  },
                  children: completed
                      .map((doc) => _buildItemTile(doc, currentUser.uid, isCompleted: true))
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemTile(DocumentSnapshot convoDoc, String currentUserId, {bool isCompleted = false}) {
    final convo = convoDoc.data() as Map<String, dynamic>;
    final itemId = convo['itemId'] ?? '';

    if (itemId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('items').doc(itemId).get(),
      builder: (context, itemSnapshot) {
        if (!itemSnapshot.hasData || !itemSnapshot.data!.exists) {
          return const ListTile(title: Text("Item not found"));
        }

        final itemData = itemSnapshot.data!.data() as Map<String, dynamic>;
        final isPaid = convo['isPaid'] ?? false;
        final isReceived = convo['isReceived'] ?? false;
        final isReturned = convo['isReturned'] ?? false;
        final isReturnConfirmed = convo['isReturnConfirmed'] ?? false;

        final imageUrl = (itemData['imageUrls'] is List && itemData['imageUrls'].isNotEmpty)
            ? itemData['imageUrls'][0]
            : null;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: isValidImageUrl(imageUrl)
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      imageUrl!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 50),
                    ),
                  )
                      : const Icon(Icons.image_not_supported, size: 50),
                  title: Text(itemData['name'] ?? 'No title'),
                  subtitle: Text(itemData['description'] ?? ''),
                ),
                const SizedBox(height: 10),

                // View-only record status
                _buildReadOnlyStatus(isCompleted, isPaid, isReceived, isReturned, isReturnConfirmed),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadOnlyStatus(
    bool isCompleted,
    bool isPaid,
    bool isReceived,
    bool isReturned,
    bool isReturnConfirmed,
  ) {
    String label;
    Color color;
    IconData icon;

    if (isCompleted) {
      label = 'Transaction Completed';
      color = const Color(0xFF2ECC71);
      icon = Icons.check_circle_outline;
    } else if (!isPaid) {
      label = 'Awaiting Escrow Payment';
      color = const Color(0xFFE67E22);
      icon = Icons.payment_outlined;
    } else if (!isReceived) {
      label = 'Payment Secured • Awaiting Handover';
      color = const Color(0xFF98259A);
      icon = Icons.handshake_outlined;
    } else if (!isReturned) {
      label = 'Rental Active • Item in Custody';
      color = const Color(0xFF16A085);
      icon = Icons.timelapse;
    } else {
      label = 'Returned • Pending Return Confirmation';
      color = const Color(0xFF98259A);
      icon = Icons.published_with_changes;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '• View-Only Record',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}
