import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/profile/data/datasources/firebase_user_service.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';

class UserProfilePage extends StatefulWidget {
  @override
  _UserProfilePageState createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final FirebaseUserService _userService = FirebaseUserService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _userService.getUserProfileStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No user data found.'));
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>;
                final displayName = userData['username'] ?? 'User';
                final location = userData['location'] is String
                    ? userData['location']
                    : 'Location not available';
                final profilePictureUrl = userData['photoURL'] ?? userData['profilePictureUrl'];
                final imageUrl = profilePictureUrl is String ? profilePictureUrl : '';

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      const Text(
                        'User Profile',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                        child: imageUrl.isEmpty
                            ? const Icon(Icons.person, size: 50)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        location,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EditProfilePage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 144, 224, 243),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Items Listed'),
                      _buildItemsList(),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Reviews Received'),
                      _buildReviews(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _userService.getUserItems(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final items = snapshot.data!.docs;
          if (items.isEmpty) {
            return const Text('No items listed.');
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text(item['title'] ?? ''),
                subtitle: Text(item['description'] ?? ''),
              );
            },
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }

  Widget _buildReviews() {
    return StreamBuilder<QuerySnapshot>(
      stream: _userService.getUserReviews(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final reviews = snapshot.data!.docs;
          if (reviews.isEmpty) {
            return const Text('No reviews received.');
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text('⭐ ${review['rating'] ?? '0'}'),
                subtitle: const Text('Review'),
                trailing: Text(review['reviewerName'] ?? ''),
              );
            },
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }
}
