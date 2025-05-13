// items/presentation/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/auth/presentation/login.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/presentation/widgets/item_card.dart';
import 'package:lendly/features/items/data/item_repository.dart';
import 'package:lendly/features/items/domain/item_model.dart';
import 'package:lendly/features/items/presentation/profile_page.dart'; // Added import

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  final List<Widget> _screens = [
    const ItemListScreen(),
    Container(color: Colors.white, child: const Center(child: Text('Search'))),
    Container(color: Colors.white, child: const Center(child: Text('Borrowed'))),
    UserProfilePage(), // Updated to actual profile page
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
        title: const Text(
          'Lendly',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
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
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const AddItemDialog(),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Borrowed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outlined),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF90E0F3),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}

class ItemListScreen extends StatelessWidget {
  const ItemListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final itemRepo = ItemRepository();

    return StreamBuilder<List<Item>>(
      stream: itemRepo.getAllItems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ItemCard(
                name: item.name,
                price: 'P${item.price.toStringAsFixed(2)} / Day',
                imagePath: item.imageUrls.isNotEmpty
                    ? item.imageUrls.first
                    : 'assets/images/placeholder.jpg',
                isOwner: item.ownerId == FirebaseAuth.instance.currentUser?.uid,
              ),
            );
          },
        );
      },
    );
  }
}
