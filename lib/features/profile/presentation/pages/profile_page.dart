import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';

class UserProfilePage extends StatefulWidget {
  final String? userId; // If null, displays current logged-in user's profile

  const UserProfilePage({super.key, this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String get _targetUserId {
    return widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  bool get _isSelf {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return widget.userId == null || widget.userId == currentUid;
  }

  Future<void> _handleDirectChat(BuildContext context, String targetName) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to send a message.')),
      );
      return;
    }

    try {
      final convoId = await createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: _targetUserId,
        itemId: '',
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              convoId: convoId,
              currentUserId: currentUserId,
              otherUserId: _targetUserId,
              otherUserName: targetName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _isSelf ? 'My Profile' : 'User Profile',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_targetUserId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5))),
                  );
                }

                Map<String, dynamic> userData = {};
                if (snapshot.hasData && snapshot.data!.exists) {
                  userData = snapshot.data!.data() as Map<String, dynamic>;
                }

                final displayName = userData['username'] ??
                    '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
                final nameStr = displayName.isNotEmpty ? displayName : 'Lendly User';
                final location = userData['location'] is String && (userData['location'] as String).isNotEmpty
                    ? userData['location']
                    : 'Location not specified';
                final phone = userData['phone'] ?? '';
                final profilePictureUrl = userData['photoURL'] ?? userData['profilePictureUrl'];
                final imageUrl = profilePictureUrl is String ? profilePictureUrl : '';

                return Column(
                  children: [
                    // Profile Header Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 52,
                                backgroundColor: const Color(0xFFEFE8FA),
                                backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                                child: imageUrl.isEmpty
                                    ? const Icon(Icons.person, size: 55, color: Color(0xFF7B40B5))
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            nameStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Color(0xFF7B40B5)),
                              const SizedBox(width: 4),
                              Text(
                                location,
                                style: TextStyle(color: Colors.grey[700], fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.star, size: 14, color: Colors.amber),
                                    SizedBox(width: 4),
                                    Text(
                                      '4.9 Verified Lender',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7B40B5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Action Buttons (Edit Profile if Self, Message/Contact if Viewing Another User)
                          if (_isSelf)
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const EditProfilePage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit Profile'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B40B5),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _handleDirectChat(context, nameStr),
                                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                                  label: const Text('Send Message'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7B40B5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  ),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Contact: $phone')),
                                      );
                                    },
                                    icon: const Icon(Icons.phone, size: 18),
                                    label: const Text('Call'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF7B40B5),
                                      side: const BorderSide(color: Color(0xFF7B40B5)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Section 1: Items Listed by this User
                    _buildSectionHeader(
                      _isSelf ? 'My Listed Items' : 'Items Listed by $nameStr',
                      Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildUserItemsList(_targetUserId),

                    const SizedBox(height: 24),

                    // Section 2: Reviews Received
                    _buildSectionHeader(
                      'Reviews & Ratings',
                      Icons.rate_review_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildUserReviewsList(_targetUserId),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7B40B5), size: 20),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildUserItemsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('ownerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'No items listed yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final item = doc.data() as Map<String, dynamic>;
            final itemTitle = item['name'] ?? item['title'] ?? 'Unnamed Item';
            final itemDesc = item['description'] ?? '';
            final itemPrice = '₱${item['price'] ?? 0}/day';

            List<String> imgs = [];
            if (item['imageUrls'] is List && (item['imageUrls'] as List).isNotEmpty) {
              imgs = List<String>.from(item['imageUrls']);
            } else if (item['imageUrl'] is String && (item['imageUrl'] as String).isNotEmpty) {
              imgs = [item['imageUrl']];
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imgs.isNotEmpty
                      ? Image.network(
                          imgs[0],
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey[200],
                            child: const Icon(Icons.shopping_bag_outlined),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[200],
                          child: const Icon(Icons.shopping_bag_outlined),
                        ),
                ),
                title: Text(itemTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(itemDesc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  itemPrice,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(itemData: item, itemId: doc.id),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserReviewsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('revieweeId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'No reviews received yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final review = docs[index].data() as Map<String, dynamic>;
            final ratingVal = (review['rating'] as num?)?.toDouble() ?? 5.0;
            final comment = review['comment'] ?? review['reviewText'] ?? 'Great lender!';
            final reviewerName = review['reviewerName'] ?? 'Verified Borrower';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEFE8FA),
                  child: Text(
                    reviewerName.isNotEmpty ? reviewerName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Color(0xFF7B40B5), fontWeight: FontWeight.bold),
                  ),
                ),
                title: Row(
                  children: [
                    ...List.generate(5, (starIdx) {
                      return Icon(
                        starIdx < ratingVal.floor() ? Icons.star : Icons.star_border,
                        size: 14,
                        color: Colors.amber[700],
                      );
                    }),
                    const SizedBox(width: 6),
                    Text(
                      reviewerName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                subtitle: Text(comment, style: const TextStyle(fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
