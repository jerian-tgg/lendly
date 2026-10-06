import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/items/data/repositories/item_repository_impl.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/presentation/widgets/ribbon_banner.dart';
import 'package:lendly/features/profile/presentation/pages/profile_page.dart';
import 'package:lendly/core/utils/image_utils.dart';

class ItemCard extends StatelessWidget {
  final String itemId;
  final Map<String, dynamic> itemData;
  final String name;
  final String price;
  final String imagePath;
  final bool isOwner;
  final bool isAvailable;
  final bool isGrid;
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
    this.isGrid = true,
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

  void _openOwnerProfile(BuildContext context, String ownerId) {
    if (ownerId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(userId: ownerId),
      ),
    );
  }

  RibbonType? _getRibbonType() {
    if (itemData['isBoosted'] == true) return RibbonType.boosted;
    if (itemData['isFeatured'] == true) return RibbonType.featured;
    if (itemData['isNew'] == true || itemData['ribbon'] == 'NEW') return RibbonType.newArrival;
    if (itemData['isPopular'] == true || itemData['ribbon'] == 'POPULAR') return RibbonType.popular;
    if ((itemData['rating'] as num?) != null && (itemData['rating'] as num) >= 4.8) return RibbonType.topRated;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = itemData['ownerId'] as String? ?? '';
    final ownerName = itemData['ownerName'] ?? 'Lender';
    final category = itemData['category'] as String? ?? 'General';
    final condition = itemData['condition'] as String? ?? 'Good';
    final rating = (itemData['rating'] as num?)?.toDouble() ?? 4.8;
    final ribbonType = _getRibbonType();

    // Distance calculation/display
    final distanceKm = (itemData['distanceKm'] as num?)?.toDouble() ??
        (itemId.hashCode % 15 + 1.2);
    final locationText = itemData['location'] is String && (itemData['location'] as String).isNotEmpty
        ? itemData['location']
        : '${distanceKm.toStringAsFixed(1)} km away';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner Header Bar (Tapping owner avatar/name opens User Profile!)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isGrid ? 8 : 12,
              vertical: isGrid ? 6 : 10,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _openOwnerProfile(context, ownerId),
                  child: FutureBuilder<DocumentSnapshot>(
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
                        radius: isGrid ? 13 : 16,
                        backgroundColor: const Color(0xFFEFE8FA),
                        backgroundImage: isValidImageUrl(photoUrl)
                            ? NetworkImage(photoUrl!)
                            : null,
                        child: !isValidImageUrl(photoUrl)
                            ? Icon(Icons.person, size: isGrid ? 14 : 18, color: const Color(0xFF7B40B5))
                            : null,
                      );
                    },
                  ),
                ),
                SizedBox(width: isGrid ? 6 : 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openOwnerProfile(context, ownerId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ownerName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isGrid ? 12 : 13,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 10, color: Color(0xFF7B40B5)),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                locationText,
                                style: TextStyle(
                                  fontSize: isGrid ? 9 : 11,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Direct Chat Bubble Icon
                if (!isOwner)
                  InkWell(
                    onTap: () => _openDirectChat(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        color: const Color(0xFF7B40B5),
                        size: isGrid ? 18 : 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.6),

          // Main Card Image & Body
          Expanded(
            child: InkWell(
              onTap: () => _handleBorrow(context),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image with Ribbon Overlay & Badges
                  Expanded(
                    flex: 5,
                    child: Stack(
                      children: [
                        ClipRRect(
                          child: isValidImageUrl(imagePath)
                              ? Image.network(
                                  imagePath,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: Colors.grey[100],
                                    child: const Center(
                                      child: Icon(Icons.photo_outlined, size: 36, color: Colors.grey),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[100],
                                  child: const Center(
                                    child: Icon(Icons.photo_outlined, size: 36, color: Colors.grey),
                                  ),
                                ),
                        ),

                        // Ribbon Banner
                        if (ribbonType != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: RibbonBanner.fromType(ribbonType),
                          ),

                        // Certified Appraised Badge
                        if (itemData['appraisalStatus'] == 'certified')
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber[800],
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield, color: Colors.white, size: 10),
                                  SizedBox(width: 2),
                                  Text(
                                    'APPRAISED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Availability Tag Badge
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAvailable
                                  ? Colors.green.withValues(alpha: 0.9)
                                  : Colors.red.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAvailable ? 'Available' : 'Borrowed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card Content Details
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category & Condition
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF90E0F3).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF007A9B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                condition,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Item Title
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 3),

                        // Star Rating Row
                        Row(
                          children: [
                            Icon(Icons.star, size: 12, color: Colors.amber[700]),
                            const SizedBox(width: 2),
                            Text(
                              '$rating',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              ' (12)',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Price & Action Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    price,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF7B40B5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '/ day',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Compact Borrow / Manage Button
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isOwner ? 'Manage' : 'Borrow',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
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
          ),
        ],
      ),
    );
  }
}
