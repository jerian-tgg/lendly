// items/presentation/widgets/add_item_dialog.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/items/domain/item_model.dart';
import 'package:lendly/features/items/data/item_repository.dart';

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({super.key});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(text: '1');
  final ImagePicker _picker = ImagePicker();
  DateTimeRange? _availability;
  String _condition = 'Like New';
  List<String> _imagePaths = [];

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    if (images != null) {
      setState(() => _imagePaths = images.map((e) => e.path).toList());
    }
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _availability = picked);
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      try {
        final imageUrls = await ItemRepository().uploadImages(_imagePaths);

        final user = FirebaseAuth.instance.currentUser!;

        final newItem = Item(
          id: '',
          name: _nameController.text,
          description: _descController.text,
          category: _categoryController.text,
          quantity: int.parse(_quantityController.text),
          price: double.parse(_priceController.text),
          availableFrom: _availability?.start ?? DateTime.now(),
          availableTo: _availability?.end ?? DateTime.now().add(const Duration(days: 30)),
          condition: _condition,
          imageUrls: imageUrls,
          ownerId: user.uid,
          ownerName: user.displayName ?? 'Anonymous',
          createdAt: DateTime.now(),
          isAvailable: true,
        );

        await ItemRepository().addItem(newItem);
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding item: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Item'),
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
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
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
                Text('${DateFormat('MMM d').format(_availability!.start)} - ${DateFormat('MMM d').format(_availability!.end)}'),
              DropdownButtonFormField<String>(
                value: _condition,
                items: ['Like New', 'Good', 'Fair', 'Poor'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _condition = value!),
                decoration: const InputDecoration(labelText: 'Condition'),
              ),
              ElevatedButton(
                onPressed: _pickImages,
                child: const Text('Add Photos'),
              ),
              if (_imagePaths.isNotEmpty)
                Text('${_imagePaths.length} photos selected'),
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
          child: const Text('Add Item'),
        ),
      ],
    );
  }
}