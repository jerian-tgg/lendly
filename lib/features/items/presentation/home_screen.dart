import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/auth/presentation/login.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/presentation/widgets/item_card.dart';
import 'package:lendly/features/items/presentation/profile_page.dart';
import 'package:lendly/features/items/presentation/search_screen.dart';
import 'package:lendly/features/items/presentation/borrowed_items_screen.dart';
import 'package:lendly/features/chat/presentation/pages/conversation_screen.dart';// Import borrowed screen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const ItemListScreen(),
    const SearchScreen(),
    BorrowedItemsScreen(),
    ConversationScreen(), // <- Add this
    UserProfilePage(),
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
        title: const Text('Lendly', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _showLogoutConfirmation,
          ),
        ],
      )
          : null,
      body: _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
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
          BottomNavigationBarItem(icon: Icon(Icons.chat_outlined), label: 'Messages'), // <- Add this
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

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  final userId = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _deleteItem(String itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('items').doc(itemId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete item: $e')));
        }
      }
    }
  }

  void _editItem(String itemId, Map<String, dynamic> currentData) {
    showDialog(
      context: context,
      builder: (_) => AddItemDialog(
        itemId: itemId,
        initialData: currentData,
      ),
    );
  }

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
            final data = doc.data() as Map<String, dynamic>;
            final isOwner = data['ownerId'] == userId;

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
