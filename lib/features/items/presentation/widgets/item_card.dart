import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/items/presentation/item_detail_screen.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/data/item_repository.dart';

import 'add_item_dialog.dart';

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
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
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
      await ItemRepository().deleteItem(itemId);
      if (onDelete != null) onDelete!();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item deleted')),
      );
    }
  }

  void _handleBorrow(BuildContext context) {
    if (!isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorry, this item is currently unavailable.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrow Item'),
        content: const Text('Are you sure you want to borrow this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ItemDetailScreen(itemData: itemData, itemId: itemId),
                ),
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(
              imagePath,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, color: Colors.red),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
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
                        backgroundColor: const Color(0xFF90E0F3),
                      ),
                      child: Text(
                        isOwner ? 'Manage' : (isAvailable ? 'Borrow Now' : 'Unavailable'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
