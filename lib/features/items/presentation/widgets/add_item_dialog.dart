import 'dart:io';
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
  bool _photoError = false;
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Electronics',
    'Appliances',
    'Tools',
    'Books',
    'Furniture',
    'Clothing',
    'Other',
  ];

  final List<String> _conditions = [
    'Like New',
    'Good',
    'Fair',
    'Poor',
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

  // Camera-Only Image Capture (Required feature!)
  Future<void> _takeCameraPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1200,
      );

      if (photo != null) {
        setState(() {
          _imagePaths.add(photo.path);
          _photoError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _imagePaths.removeAt(index);
    });
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDateRange: _availability,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF7B40B5),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _availability = picked);
    }
  }

  Future<void> _submitForm() async {
    // Validate required camera photo
    if (_imagePaths.isEmpty) {
      setState(() {
        _photoError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📷 A camera photo is required to list an item!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _photoError = false;
    });

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
        quantity: int.parse(_quantityController.text.trim().isEmpty ? '1' : _quantityController.text.trim()),
        price: double.parse(_priceController.text.trim()),
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
            const SnackBar(content: Text('Item updated successfully!')),
          );
        }
      } else {
        await ItemRepositoryImpl().addItem(item);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🎉 Item added successfully with camera verification!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting item: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemId != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Redesigned Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.camera_enhance_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit Item' : 'Add New Item',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Camera verification required',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Scrollable Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Camera-Only Required Image Upload Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _photoError ? Colors.red.shade50 : const Color(0xFFF9F5FE),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _photoError ? Colors.redAccent : const Color(0xFF7B40B5).withValues(alpha: 0.4),
                            width: _photoError ? 2 : 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.camera_alt_rounded, color: Color(0xFF7B40B5), size: 20),
                                const SizedBox(width: 6),
                                const Text(
                                  'Item Photos (Camera Only)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF7B40B5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'REQUIRED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Please snap a live photo using your camera to verify your item.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),

                            // Camera Photo Thumbnails List
                            if (_imagePaths.isNotEmpty)
                              SizedBox(
                                height: 90,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _imagePaths.length,
                                  itemBuilder: (context, index) {
                                    final path = _imagePaths[index];
                                    final isNetwork = path.startsWith('http');
                                    return Container(
                                      margin: const EdgeInsets.only(right: 10),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: isNetwork
                                                ? Image.network(path, width: 80, height: 80, fit: BoxFit.cover)
                                                : Image.file(File(path), width: 80, height: 80, fit: BoxFit.cover),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: InkWell(
                                              onTap: () => _removePhoto(index),
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.7),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 2,
                                            left: 2,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.camera_alt, size: 9, color: Colors.amber),
                                                  SizedBox(width: 2),
                                                  Text('Camera', style: TextStyle(color: Colors.white, fontSize: 8)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),

                            const SizedBox(height: 8),

                            // Take Photo Button (Camera only!)
                            ElevatedButton.icon(
                              onPressed: _takeCameraPhoto,
                              icon: const Icon(Icons.photo_camera_rounded, size: 18),
                              label: Text(_imagePaths.isEmpty ? 'Take Photo with Camera' : 'Snap Additional Photo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B40B5),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),

                            if (_photoError) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '⚠️ You must take at least 1 photo using the camera before submitting.',
                                style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Item Name Input
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Item Name',
                          hintText: 'e.g. Sony DSLR Camera',
                          prefixIcon: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 2),
                          ),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Item name is required' : null,
                      ),

                      const SizedBox(height: 14),

                      // Description Input
                      TextFormField(
                        controller: _descController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          hintText: 'Describe your item features, condition, guidelines...',
                          prefixIcon: const Icon(Icons.description_outlined, color: Color(0xFF7B40B5)),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Category & Price Inputs (Row)
                      Row(
                        children: [
                          // Category Dropdown
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF7B40B5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: _categories.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _selectedCategory = value!),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Price Input
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Price / Day',
                                prefixText: '₱ ',
                                prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF7B40B5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (value) => (value == null || value.trim().isEmpty) ? 'Price required' : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Quantity & Condition Inputs
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                prefixIcon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _condition,
                              decoration: InputDecoration(
                                labelText: 'Condition',
                                prefixIcon: const Icon(Icons.stars_outlined, color: Color(0xFF7B40B5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: _conditions.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _condition = value!),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Availability Range Button
                      InkWell(
                        onTap: _selectDates,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined, color: Color(0xFF7B40B5)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _availability != null
                                      ? 'Availability: ${DateFormat('MMM d').format(_availability!.start)} - ${DateFormat('MMM d').format(_availability!.end)}'
                                      : 'Select Available Date Range (Optional)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _availability != null ? Colors.black87 : Colors.grey[600],
                                    fontWeight: _availability != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Form Footer Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B40B5),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            isEditing ? 'Update Item' : 'Add Item',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
