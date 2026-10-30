import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/items/data/repositories/item_repository_impl.dart';
import 'package:lendly/features/items/domain/entities/item.dart';
import 'package:lendly/features/items/presentation/widgets/location_picker_map_dialog.dart';

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
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  final ImagePicker _picker = ImagePicker();

  DateTimeRange? _availability;
  String _condition = 'Pending Appraisal';
  String _selectedCategory = 'Electronics';
  List<String> _imagePaths = [];
  bool _photoError = false;
  bool _isSubmitting = false;
  double? _itemLatitude;
  double? _itemLongitude;

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
    _condition = widget.initialData?['conditionGrade'] ?? widget.initialData?['condition'] ?? 'Pending Appraisal';
    _selectedCategory = widget.initialData?['category'] ?? 'Electronics';

    String initialAddress = widget.initialData?['address']?.toString() ?? '';
    String initialCity = widget.initialData?['city']?.toString() ?? '';

    // If address or city not split yet, parse from composite location
    if (initialAddress.isEmpty && initialCity.isEmpty && widget.initialData?['location'] != null) {
      final rawLoc = widget.initialData!['location'].toString();
      if (rawLoc.contains(',')) {
        final lastComma = rawLoc.lastIndexOf(',');
        initialAddress = rawLoc.substring(0, lastComma).trim();
        initialCity = rawLoc.substring(lastComma + 1).trim();
      } else {
        initialCity = rawLoc;
      }
    }

    _addressController = TextEditingController(text: initialAddress);
    _cityController = TextEditingController(text: initialCity);

    if (widget.initialData != null) {
      _itemLatitude = (widget.initialData!['latitude'] as num?)?.toDouble() ??
          (widget.initialData!['lat'] as num?)?.toDouble();
      _itemLongitude = (widget.initialData!['longitude'] as num?)?.toDouble() ??
          (widget.initialData!['lng'] as num?)?.toDouble();

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
    } else {
      _fetchUserDefaultLocation();
    }
  }

  Future<void> _fetchUserDefaultLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        final locData = data?['location'];
        final coords = LocationHelper.parseCoordinates(locData);
        if (coords != null) {
          setState(() {
            _itemLatitude = coords.latitude;
            _itemLongitude = coords.longitude;
            if (_cityController.text.isEmpty) {
              _cityController.text = coords.name ??
                  '${coords.latitude.toStringAsFixed(2)}, ${coords.longitude.toStringAsFixed(2)}';
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _useProfileLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        final locData = data?['location'];
        final coords = LocationHelper.parseCoordinates(locData);
        if (coords != null) {
          setState(() {
            _itemLatitude = coords.latitude;
            _itemLongitude = coords.longitude;
            _cityController.text = coords.name ??
                '${coords.latitude.toStringAsFixed(2)}, ${coords.longitude.toStringAsFixed(2)}';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 Loaded location from profile: ${_cityController.text}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _pickLocationOnMap() async {
    final current = (_itemLatitude != null && _itemLongitude != null)
        ? GeoLocation(
            latitude: _itemLatitude!,
            longitude: _itemLongitude!,
            name: _cityController.text.isNotEmpty ? _cityController.text : null,
          )
        : LocationHelper.defaultLocation;

    final result = await LocationPickerMapDialog.show(
      context,
      initialLocation: current,
      initialRadiusKm: 5.0,
      title: 'Pin Item Location on Map',
    );

    if (result != null && mounted) {
      setState(() {
        _itemLatitude = result.location.latitude;
        _itemLongitude = result.location.longitude;
        if (result.location.name != null && result.location.name!.isNotEmpty) {
          _cityController.text = result.location.name!;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 Item location pinned: ${_cityController.text}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _addressController.dispose();
    _cityController.dispose();
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

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to add items.')),
        );
        return;
      }
      final now = DateTime.now();

      final address = _addressController.text.trim();
      final city = _cityController.text.trim();
      String fullLocation = '';
      if (address.isNotEmpty && city.isNotEmpty) {
        fullLocation = '$address, $city';
      } else if (address.isNotEmpty) {
        fullLocation = address;
      } else if (city.isNotEmpty) {
        fullLocation = city;
      }

      final parsedFromCity = LocationHelper.parseCoordinates(city);
      final parsedFromFull = LocationHelper.parseCoordinates(fullLocation);
      final finalLat = parsedFromCity?.latitude ?? parsedFromFull?.latitude ?? _itemLatitude;
      final finalLng = parsedFromCity?.longitude ?? parsedFromFull?.longitude ?? _itemLongitude;

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
        location: fullLocation.isNotEmpty ? fullLocation : (parsedFromCity?.name ?? 'Nearby'),
        address: address,
        city: city,
        latitude: finalLat,
        longitude: finalLng,
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
            const SnackBar(content: Text('🎉 Item listed successfully with camera verification & location!')),
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
    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight * 0.90;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Premium Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      size: 22,
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
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Live camera photo & pickup location required',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 2. Responsive Scrollable Form Body (No Overflow!)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 440;

                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // SECTION 1: Camera-Only Photo Capture Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _photoError ? Colors.red.shade50 : const Color(0xFFF9F5FE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _photoError ? Colors.redAccent : const Color(0xFF7B40B5).withValues(alpha: 0.35),
                                width: _photoError ? 2 : 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.camera_alt_rounded, color: Color(0xFF7B40B5), size: 18),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Item Photos (Camera Only)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF7B40B5),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'REQUIRED',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Snap live photos using camera to verify physical condition.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 10),

                                // Thumbnails list
                                if (_imagePaths.isNotEmpty) ...[
                                  SizedBox(
                                    height: 84,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _imagePaths.length,
                                      itemBuilder: (context, index) {
                                        final path = _imagePaths[index];
                                        final isNetwork = path.startsWith('http');
                                        return Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: isNetwork
                                                    ? Image.network(path, width: 76, height: 76, fit: BoxFit.cover)
                                                    : Image.file(File(path), width: 76, height: 76, fit: BoxFit.cover),
                                              ),
                                              Positioned(
                                                top: 2,
                                                right: 2,
                                                child: InkWell(
                                                  onTap: () => _removePhoto(index),
                                                  child: Container(
                                                    padding: const EdgeInsets.all(3),
                                                    decoration: const BoxDecoration(
                                                      color: Colors.black87,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 3,
                                                left: 3,
                                                child: Container(
                                                  padding: const EdgeInsets.all(2),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.black87,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.camera_alt, size: 10, color: Colors.amber),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // Snap Photo Button
                                ElevatedButton.icon(
                                  onPressed: _takeCameraPhoto,
                                  icon: const Icon(Icons.photo_camera_rounded, size: 16),
                                  label: Text(
                                    _imagePaths.isEmpty ? 'Take Photo with Camera' : 'Snap Another Photo',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7B40B5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),

                                if (_photoError) ...[
                                  const SizedBox(height: 6),
                                  const Text(
                                    '⚠️ At least 1 live camera photo is required to submit.',
                                    style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ],
                            ),

                          ),

                          const SizedBox(height: 16),

                          // SECTION 2: General Information
                          const Text(
                            'Item Details',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),

                          // Item Name Input
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Item Name',
                              hintText: 'e.g. Sony Alpha A7 III Camera',
                              prefixIcon: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF7B40B5), size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            validator: (value) => (value == null || value.trim().isEmpty) ? 'Item name is required' : null,
                          ),

                          const SizedBox(height: 12),

                          // Description Input
                          TextFormField(
                            controller: _descController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Description',
                              hintText: 'Describe item features, included accessories, usage guidelines...',
                              prefixIcon: const Icon(Icons.description_outlined, color: Color(0xFF7B40B5), size: 20),
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // SECTION 3: Category, Price, & Quantity (Adaptive Stacking!)
                          if (isCompact) ...[
                            // Compact Vertical Layout (Guarantees NO Row Overflow on small screens!)
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF7B40B5), size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: _categories.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _selectedCategory = value!),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: TextFormField(
                                    controller: _priceController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Price / Day',
                                      prefixText: '₱ ',
                                      prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF7B40B5), size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Price required' : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 4,
                                  child: TextFormField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Qty',
                                      prefixIcon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5), size: 18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.15)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.verified_outlined, size: 16, color: Color(0xFF7B40B5)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Official condition rating is evaluated and assigned by a certified appraiser.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF7B40B5), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Wide Screen Side-by-Side Rows
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedCategory,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Category',
                                      prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF7B40B5), size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 4,
                                  child: TextFormField(
                                    controller: _priceController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Price / Day',
                                      prefixText: '₱ ',
                                      prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF7B40B5), size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Price required' : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Qty',
                                      prefixIcon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5), size: 18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.15)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.verified_outlined, size: 16, color: Color(0xFF7B40B5)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Official condition rating is evaluated and assigned by a certified appraiser.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF7B40B5), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          // Available Dates Button
                          InkWell(
                            onTap: _selectDates,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month_outlined, color: Color(0xFF7B40B5), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _availability != null
                                          ? 'Availability: ${DateFormat('MMM d').format(_availability!.start)} - ${DateFormat('MMM d').format(_availability!.end)}'
                                          : 'Select Available Dates (Optional)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _availability != null ? Colors.black87 : Colors.grey[600],
                                        fontWeight: _availability != null ? FontWeight.bold : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // SECTION 4: Dedicated Item Location & Address Card (User Request Highlight!)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F5FE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.3),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7B40B5).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.location_on, color: Color(0xFF7B40B5), size: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Item Pickup Location & Address',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Color(0xFF7B40B5),
                                            ),
                                          ),
                                          Text(
                                            'Used for marketplace search & radius distance',
                                            style: TextStyle(fontSize: 10, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // Quick Autofill / Preset Buttons
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    InkWell(
                                      onTap: _pickLocationOnMap,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7B40B5),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.pin_drop, size: 13, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              'Pin on Map',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: _useProfileLocation,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.4)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_pin_circle_outlined, size: 13, color: Color(0xFF7B40B5)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Use Profile Address',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<GeoLocation>(
                                      tooltip: 'Choose Preset City',
                                      onSelected: (loc) {
                                        setState(() {
                                          _cityController.text = loc.name ?? '${loc.latitude}, ${loc.longitude}';
                                          _itemLatitude = loc.latitude;
                                          _itemLongitude = loc.longitude;
                                        });
                                      },
                                      itemBuilder: (context) {
                                        return LocationHelper.presetLocations.map((loc) {
                                          return PopupMenuItem<GeoLocation>(
                                            value: loc,
                                            child: Row(
                                              children: [
                                                const Icon(Icons.location_city, size: 14, color: Color(0xFF7B40B5)),
                                                const SizedBox(width: 6),
                                                Text(loc.name ?? '${loc.latitude}, ${loc.longitude}', style: const TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          );
                                        }).toList();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.map_outlined, size: 13, color: Colors.grey),
                                            SizedBox(width: 4),
                                            Text('Choose City', style: TextStyle(fontSize: 11, color: Colors.black87)),
                                            Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                // Street Address / Landmark Input
                                TextFormField(
                                  controller: _addressController,
                                  decoration: InputDecoration(
                                    labelText: 'Street Address / Pickup Landmark',
                                    hintText: 'e.g. Unit 4B, Sunset Blvd, Brgy. Mandalagan',
                                    prefixIcon: const Icon(Icons.home_outlined, color: Color(0xFF7B40B5), size: 18),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  ),
                                  validator: (val) {
                                    if ((val == null || val.trim().isEmpty) && _cityController.text.trim().isEmpty) {
                                      return 'Please provide street address or city for pickup';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 8),

                                // City / Province Input
                                TextFormField(
                                  controller: _cityController,
                                  decoration: InputDecoration(
                                    labelText: 'City / Municipality / Province',
                                    hintText: 'e.g. Bacolod City, Negros Occidental',
                                    prefixIcon: const Icon(Icons.location_city_outlined, color: Color(0xFF7B40B5), size: 18),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  ),
                                  onChanged: (val) {
                                    final coords = LocationHelper.parseCoordinates(val);
                                    if (coords != null) {
                                      setState(() {
                                        _itemLatitude = coords.latitude;
                                        _itemLongitude = coords.longitude;
                                      });
                                    }
                                  },
                                ),

                                // Live Geographical Coordinates Detection Badge
                                if (_itemLatitude != null && _itemLongitude != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'GPS Coordinates: ${_itemLatitude!.toStringAsFixed(3)}, ${_itemLongitude!.toStringAsFixed(3)} (Radius Search Ready)',
                                            style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. Pinned Action Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitForm,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(isEditing ? Icons.save_outlined : Icons.add_circle_outline, size: 16),
                    label: Text(
                      isEditing ? 'Update Item' : 'List Item',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B40B5),
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
