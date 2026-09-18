import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';
import 'package:lendly/features/chat/presentation/pages/conversation_screen.dart';
import 'package:lendly/features/items/presentation/pages/borrowed_items_screen.dart';
import 'package:lendly/features/items/presentation/pages/search_screen.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/presentation/widgets/item_card.dart';
import 'package:lendly/features/profile/presentation/pages/profile_page.dart';

class HomeScreen extends StatefulWidget {
  final bool isGuest;
  const HomeScreen({super.key, this.isGuest = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  bool get isVisitor => widget.isGuest || FirebaseAuth.instance.currentUser == null;

  List<Widget> get _screens => [
    const ItemListScreen(),
    const SearchScreen(),
    isVisitor
        ? const VisitorPromptView(
            title: 'Borrowed Items',
            message: 'Log in to track and view your borrowed items.',
            icon: Icons.shopping_cart_outlined,
          )
        : const BorrowedItemsScreen(),
    isVisitor
        ? const VisitorPromptView(
            title: 'Conversations',
            message: 'Log in to chat with lenders and discuss borrowing.',
            icon: Icons.chat_outlined,
          )
        : ConversationScreen(),
    isVisitor
        ? const VisitorPromptView(
            title: 'Your Profile',
            message: 'Log in to view your profile and account settings.',
            icon: Icons.person_outlined,
          )
        : const UserProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _showLogoutConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Log Out', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
        backgroundColor: const Color(0xFF90E0F3),
        title: Row(
          children: [
            const Text('Lendly', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            if (isVisitor) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Visitor',
                  style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (isVisitor)
            TextButton.icon(
              icon: const Icon(Icons.login, color: Colors.white),
              label: const Text('Log In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _showLogoutConfirmation,
            ),
        ],
      )
          : null,
      body: _screens[_selectedIndex],
      floatingActionButton: (!isVisitor && _selectedIndex == 0)
          ? FloatingActionButton(
        backgroundColor: const Color(0xFF90E0F3),
        onPressed: () => showDialog(context: context, builder: (_) => const AddItemDialog()),
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search_outlined), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Borrowed'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_outlined), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF90E0F3),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}

class VisitorPromptView extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const VisitorPromptView({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF90E0F3).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: const Color(0xFF007799)),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF90E0F3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: const Text(
                    'Log In / Sign Up',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
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

            );          },
        );

      },
    );
  }
}
