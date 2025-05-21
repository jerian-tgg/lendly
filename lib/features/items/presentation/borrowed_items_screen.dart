import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
        title: const Text("Borrowed Items"),
        backgroundColor: const Color(0xFF90E0F3),
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
    final ownerId = convo['itemOwnerId'] ?? '';
    final convoId = convoDoc.id;

    if (itemId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('items').doc(itemId).get(),
      builder: (context, itemSnapshot) {
        if (!itemSnapshot.hasData || !itemSnapshot.data!.exists) {
          return const ListTile(title: Text("Item not found"));
        }

        final itemData = itemSnapshot.data!.data() as Map<String, dynamic>;
        final isOwner = currentUserId == ownerId;
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
                  leading: imageUrl != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  )
                      : const Icon(Icons.image_not_supported),
                  title: Text(itemData['name'] ?? 'No title'),
                  subtitle: Text(itemData['description'] ?? ''),
                ),
                const SizedBox(height: 10),

                // Status / Action Buttons
                if (isCompleted)
                  const Text(
                    'Transaction completed.',
                    style: TextStyle(color: Colors.green),
                  )
                else if (isOwner && !isPaid)
                  ElevatedButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('conversations')
                          .doc(convoId)
                          .update({'isPaid': true});
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Mark as Paid'),
                  )
                else if (!isOwner && isPaid && !isReceived)
                    ElevatedButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('conversations')
                            .doc(convoId)
                            .update({'isReceived': true});
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      child: const Text('Mark as Received'),
                    )
                  else if (!isOwner && isPaid && isReceived && !isReturned)
                      ElevatedButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('conversations')
                              .doc(convoId)
                              .update({'isReturned': true});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: const Text('Mark as Returned'),
                      )
                    else if (isOwner && isReturned && !isReturnConfirmed)
                        ElevatedButton(
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('conversations')
                                .doc(convoId)
                                .update({'isReturnConfirmed': true});
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                          child: const Text('Confirm Return'),
                        )
                      else
                        Text(
                          isOwner
                              ? (isReturnConfirmed
                              ? 'Transaction complete.'
                              : isReturned
                              ? 'Confirm item return.'
                              : isPaid
                              ? 'Waiting for borrower to return item.'
                              : 'Waiting for payment...')
                              : isReturnConfirmed
                              ? 'Transaction complete.'
                              : isReturned
                              ? 'Waiting for owner to confirm return.'
                              : isReceived
                              ? 'Mark as returned after use.'
                              : 'Waiting for delivery...',
                          style: const TextStyle(color: Colors.grey),
                        ),
              ],
            ),
          ),
        );
      },
    );
  }
}


