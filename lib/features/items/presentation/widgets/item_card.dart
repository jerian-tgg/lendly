import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/items/data/repositories/item_repository_impl.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';

class ItemCard extends StatelessWidget {
  final String itemId;
  final Map<String, dynamic> itemData;
  final String name;
  final String price;
  final String imagePath;
  final bool isOwner;
  final bool isAvailable;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ItemCard({
    super.key,
    required this.itemId,
    required this.itemData,
    required this.name,
    required this.price,
    required this.imagePath,
    this.isOwner = false,
    this.isAvailable = true,
    this.onEdit,
    this.onDelete,
  });

  void _showManageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF7B40B5)),
              title: const Text('Edit Item'),
              onTap: () {
                Navigator.pop(context);
                _handleEdit(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Item', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _handleEdit(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AddItemDialog(
        itemId: itemId,
        initialData: itemData,
      ),
    ).then((_) {
      if (onEdit != null) onEdit!();
    });
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ItemRepositoryImpl().deleteItem(itemId);
      if (onDelete != null) onDelete!();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item deleted')),
        );
      }
    }
  }

  void _handleBorrow(BuildContext context) {
    if (!isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorry, this item is currently unavailable.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemDetailScreen(
          itemData: itemData,
          itemId: itemId,
        ),
      ),
    );
  }

  Future<void> _openDirectChat(BuildContext context) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to chat with the owner')),
      );
      return;
    }

    final ownerId = itemData['ownerId'] as String? ?? '';
    if (ownerId.isEmpty || ownerId == currentUserId) return;

    final ownerName = itemData['ownerName'] ?? 'Owner';

    try {
      final convoId = await createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: ownerId,
        itemId: itemId,
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              convoId: convoId,
              currentUserId: currentUserId,
              otherUserId: ownerId,
              otherUserName: ownerName,
              itemId: itemId,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = itemData['ownerId'] as String? ?? '';
    final ownerName = itemData['ownerName'] ?? 'Lender';
    final category = itemData['category'] as String? ?? 'General';
    final condition = itemData['condition'] as String? ?? 'Good';
    final rating = (itemData['rating'] as num?)?.toDouble() ?? 4.8;
    final isBoosted = itemData['isBoosted'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner Header Bar (From Wireframe 1 & 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                FutureBuilder<DocumentSnapshot>(
                  future: ownerId.isNotEmpty
                      ? FirebaseFirestore.instance.collection('users').doc(ownerId).get()
                      : null,
                  builder: (context, snapshot) {
                    String? photoUrl;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final uData = snapshot.data!.data() as Map<String, dynamic>?;
                      photoUrl = uData?['photoURL'] ?? uData?['profilePictureUrl'];
                    }

                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFEFE8FA),
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                          ? NetworkImage(photoUrl)
                          : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? const Icon(Icons.person, size: 20, color: Color(0xFF7B40B5))
                          : null,
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ownerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        itemData['location'] ?? 'Nearby • Verified Lender',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Direct Chat Bubble Icon (From Wireframe 1 & 2)
                if (!isOwner)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF7B40B5)),
                    tooltip: 'Message Owner',
                    onPressed: () => _openDirectChat(context),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.8),

          // Main Card Media & Details Container
          InkWell(
            onTap: () => _handleBorrow(context),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image with Badges
                Stack(
                  children: [
                    ClipRRect(
                      child: imagePath.isNotEmpty
                          ? Image.network(
                              imagePath,
                              height: 190,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 190,
                                color: Colors.grey[100],
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.photo_outlined, size: 48, color: Colors.grey),
                                    SizedBox(height: 4),
                                    Text('No Image', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              height: 190,
                              color: Colors.grey[100],
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_outlined, size: 48, color: Colors.grey),
                                  SizedBox(height: 4),
                                  Text('No Image', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                    ),

                    // Availability Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? Colors.green.withValues(alpha: 0.9)
                              : Colors.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isAvailable ? 'Available' : 'Borrowed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Featured / Boosted Badge (From Wireframe 2 - Discord style boosting tag)
                    if (isBoosted)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, color: Colors.amber, size: 14),
                              SizedBox(width: 2),
                              Text(
                                'BOOSTED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // Card Details Body
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category & Condition Pills
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF90E0F3).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF007A9B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•  $condition',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Item Title
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),

                      // Star Rating Row (Wireframe 1 & Wireframe 2 feature!)
                      Row(
                        children: [
                          ...List.generate(5, (index) {
                            return Icon(
                              index < rating.floor()
                                  ? Icons.star
                                  : (index < rating ? Icons.star_half : Icons.star_border),
                              size: 16,
                              color: Colors.amber[700],
                            );
                          }),
                          const SizedBox(width: 6),
                          Text(
                            '$rating',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            ' (12 reviews)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Price and Action Call-to-Action Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                price,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7B40B5),
                                ),
                              ),
                              Text(
                                'per day',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),

                          // Call to action button (Borrow / Manage)
                          ElevatedButton(
                            onPressed: () {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please login to borrow items')),
                                );
                                return;
                              }
                              if (isOwner) {
                                _showManageOptions(context);
                              } else {
                                _handleBorrow(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isOwner
                                  ? const Color(0xFF7B40B5)
                                  : const Color(0xFF90E0F3),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              isOwner ? 'Manage' : (isAvailable ? 'Borrow Now' : 'Unavailable'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
