import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/items/data/repositories/item_repository_impl.dart';
import 'package:lendly/features/items/domain/entities/item.dart';

class AddItemDialog extends StatefulWidget {
  final String? itemId;
  final Map<String, dynamic>? initialData;

  const AddItemDialog({super.key, this.itemId, this.initialData});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _priceController;
  late TextEditingController _quantityController;
  final ImagePicker _picker = ImagePicker();
  DateTimeRange? _availability;
  String _condition = 'Like New';
  String _selectedCategory = 'Electronics';
  List<String> _imagePaths = [];

  final List<String> _categories = [
    'Electronics',
    'Appliances',
    'Tools',
    'Books',
    'Furniture',
    'Clothing',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.initialData?['name'] ?? '');
    _descController = TextEditingController(text: widget.initialData?['description'] ?? '');
    _priceController = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
    _quantityController = TextEditingController(text: widget.initialData?['quantity']?.toString() ?? '1');
    _condition = widget.initialData?['condition'] ?? 'Like New';
    _selectedCategory = widget.initialData?['category'] ?? 'Electronics';

    if (widget.initialData != null) {
      final fromTimestamp = widget.initialData!['availableFrom'];
      final toTimestamp = widget.initialData!['availableTo'];

      if (fromTimestamp != null && toTimestamp != null) {
        DateTime start = fromTimestamp is DateTime ? fromTimestamp : (fromTimestamp as dynamic).toDate();
        DateTime end = toTimestamp is DateTime ? toTimestamp : (toTimestamp as dynamic).toDate();

        _availability = DateTimeRange(start: start, end: end);
      }

      final images = widget.initialData!['imageUrls'];
      if (images != null && images is List<dynamic>) {
        _imagePaths = List<String>.from(images);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _imagePaths = images.map((e) => e.path).toList();
      });
    }
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDateRange: _availability,
    );
    if (picked != null) {
      setState(() => _availability = picked);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      List<String> imageUrls = [];

      if (widget.itemId != null) {
        final localImagePaths = _imagePaths.where((p) => !p.startsWith('http')).toList();
        final existingUrls = _imagePaths.where((p) => p.startsWith('http')).toList();
        final uploadedUrls = await ItemRepositoryImpl().uploadImages(localImagePaths);
        imageUrls = [...existingUrls, ...uploadedUrls];
      } else {
        imageUrls = await ItemRepositoryImpl().uploadImages(_imagePaths);
      }

      final user = FirebaseAuth.instance.currentUser!;
      final now = DateTime.now();

      final item = Item(
        id: widget.itemId ?? '',
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        category: _selectedCategory,
        quantity: int.parse(_quantityController.text),
        price: double.parse(_priceController.text),
        availableFrom: _availability?.start ?? now,
        availableTo: _availability?.end ?? now.add(const Duration(days: 30)),
        condition: _condition,
        imageUrls: imageUrls,
        ownerId: user.uid,
        ownerName: user.displayName ?? 'Anonymous',
        createdAt: widget.itemId == null
            ? now
            : (widget.initialData?['createdAt'] is DateTime
            ? widget.initialData!['createdAt']
            : (widget.initialData!['createdAt'] as dynamic).toDate()),
        isAvailable: true,
      );

      if (widget.itemId != null) {
        await ItemRepositoryImpl().updateItem(widget.itemId!, item);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item updated')),
          );
        }
      } else {
        await ItemRepositoryImpl().addItem(item);
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting item: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemId != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Item' : 'Add New Item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedCategory = value!),
              ),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Price per Day'),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _selectDates,
                  ),
                ],
              ),
              if (_availability != null)
                Text(
                  '${DateFormat('MMM d').format(_availability!.start)} - ${DateFormat('MMM d').format(_availability!.end)}',
                ),
              DropdownButtonFormField<String>(
                initialValue: _condition,
                decoration: const InputDecoration(labelText: 'Condition'),
                items: ['Like New', 'Good', 'Fair', 'Poor'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _condition = value!),
              ),
              ElevatedButton(
                onPressed: _pickImages,
                child: Text(isEditing ? 'Update Photos' : 'Add Photos'),
              ),
              if (_imagePaths.isNotEmpty)
                Text('${_imagePaths.length} photo(s) selected'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submitForm,
          child: Text(isEditing ? 'Update Item' : 'Add Item'),
        ),
      ],
    );
  }
}
