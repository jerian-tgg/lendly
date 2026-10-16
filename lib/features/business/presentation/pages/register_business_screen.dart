import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lendly/core/services/document_upload_service.dart';
import 'package:lendly/features/business/data/repositories/business_application_repository.dart';
import 'package:lendly/features/admin/presentation/widgets/document_viewer_dialog.dart';

class RegisterBusinessScreen extends StatefulWidget {
  final Map<String, dynamic>? existingData;

  const RegisterBusinessScreen({super.key, this.existingData});

  @override
  State<RegisterBusinessScreen> createState() => _RegisterBusinessScreenState();
}

class _RegisterBusinessScreenState extends State<RegisterBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final BusinessApplicationRepository _repository = BusinessApplicationRepository();

  late TextEditingController _businessNameController;
  late TextEditingController _licenseController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;

  String _selectedPermitType = 'BIR Certificate of Registration (Form 2303)';
  String _selectedSpecialization = 'Electronics & Technology';

  final List<String> _permitTypes = [
    'BIR Certificate of Registration (Form 2303)',
    'DTI Business Name Registration',
    'SEC Certificate of Incorporation',
    'Mayor\'s / Business Permit',
    'PRC Appraiser Accreditation / License',
    'Other Business Registration Papers',
  ];

  final List<String> _specializations = [
    'Electronics & Technology',
    'Industrial Tools & Equipment',
    'Jewelry & Luxury Goods',
    'Vehicles & Transport',
    'Musical Instruments',
    'Home & Office Appliances',
    'General Merchandise',
  ];

  // Local pending photos picked via camera/gallery
  final List<XFile> _pickedFiles = [];
  // Existing uploaded URLs (if re-applying)
  final List<String> _existingUrls = [];

  bool _isLoading = false;
  String _loadingMessage = '';
  String? _photoError;

  @override
  void initState() {
    super.initState();
    final init = widget.existingData;

    _businessNameController = TextEditingController(text: init?['businessName'] ?? '');
    _licenseController = TextEditingController(text: init?['licenseNumber'] ?? '');
    _phoneController = TextEditingController(text: init?['phone'] ?? '');
    _addressController = TextEditingController(text: init?['address'] ?? '');
    _notesController = TextEditingController(text: init?['notes'] ?? '');

    if (init?['permitType'] != null && _permitTypes.contains(init!['permitType'])) {
      _selectedPermitType = init['permitType'];
    }
    if (init?['specialization'] != null && _specializations.contains(init!['specialization'])) {
      _selectedSpecialization = init['specialization'];
    }

    if (init?['documentUrls'] is List) {
      _existingUrls.addAll(List<String>.from(init!['documentUrls']));
    } else if (init?['businessPermitUrls'] is List) {
      _existingUrls.addAll(List<String>.from(init!['businessPermitUrls']));
    }

    _loadUserDefaultData();
  }

  Future<void> _loadUserDefaultData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data() ?? {};
        if (_phoneController.text.isEmpty && data['phone'] != null) {
          setState(() {
            _phoneController.text = data['phone'];
          });
        }
        if (_addressController.text.isEmpty && data['location'] != null) {
          final loc = data['location'];
          if (loc is String) {
            setState(() => _addressController.text = loc);
          } else if (loc is Map && loc['name'] != null) {
            setState(() => _addressController.text = loc['name'].toString());
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _licenseController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFromCamera() async {
    final file = await DocumentUploadService.pickImageFromCamera();
    if (file != null && mounted) {
      setState(() {
        _pickedFiles.add(file);
        _photoError = null;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final files = await DocumentUploadService.pickMultipleImages();
    if (files.isNotEmpty && mounted) {
      setState(() {
        _pickedFiles.addAll(files);
        _photoError = null;
      });
    } else {
      // Fallback to single picker if multi-picker not supported
      final single = await DocumentUploadService.pickImageFromGallery();
      if (single != null && mounted) {
        setState(() {
          _pickedFiles.add(single);
          _photoError = null;
        });
      }
    }
  }

  void _removePickedFile(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
    });
  }

  void _removeExistingUrl(int index) {
    setState(() {
      _existingUrls.removeAt(index);
    });
  }

  Future<void> _submitApplication() async {
    final totalPhotos = _pickedFiles.length + _existingUrls.length;
    if (totalPhotos == 0) {
      setState(() {
        _photoError = 'Please submit at least one clear photo of your BIR permit or registration papers.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Photo of BIR permit or business papers is required!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit your registration.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Uploading BIR permits & registration documents...';
    });

    try {
      final List<String> finalUrls = [..._existingUrls];

      // Upload newly picked photos to Cloudinary
      for (int i = 0; i < _pickedFiles.length; i++) {
        if (mounted) {
          setState(() {
            _loadingMessage = 'Uploading document ${i + 1} of ${_pickedFiles.length}...';
          });
        }
        final url = await DocumentUploadService.uploadXFile(_pickedFiles[i]);
        finalUrls.add(url);
      }

      if (mounted) {
        setState(() {
          _loadingMessage = 'Submitting verification request to Admin Dashboard...';
        });
      }

      // Fetch user profile for full name
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final firstName = userData['firstName'] ?? '';
      final lastName = userData['lastName'] ?? '';
      final applicantName = ('$firstName $lastName').trim().isNotEmpty
          ? ('$firstName $lastName').trim()
          : (userData['username'] ?? user.email ?? 'Applicant');

      await _repository.submitApplication(
        userId: user.uid,
        userEmail: user.email ?? '',
        applicantName: applicantName,
        businessName: _businessNameController.text.trim(),
        licenseNumber: _licenseController.text.trim(),
        permitType: _selectedPermitType,
        specialization: _selectedSpecialization,
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        documentUrls: finalUrls,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF7B40B5), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Application Submitted',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your business registration and BIR permits have been successfully sent to the Admin Verification Dashboard.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF7B40B5), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Our administrators will manually verify your BIR permits. You can monitor the review status on your profile.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF5A2A94)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B40B5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Return to Profile', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit application: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Register as Business / Appraiser',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Informational Header Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5A2A94), Color(0xFF7B40B5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B40B5).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user, color: Colors.amber, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manual Verification Required',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'To protect lenders and borrowers, all commercial businesses and professional appraisers must submit valid BIR permits or business registration papers for manual review by our admin team.',
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Section 1: Business Details
                  _buildSectionCard(
                    title: '1. Business Information',
                    icon: Icons.store_mall_directory_outlined,
                    children: [
                      TextFormField(
                        controller: _businessNameController,
                        decoration: InputDecoration(
                          labelText: 'Business / Agency Name *',
                          hintText: 'e.g. Apex Valuations & Lending Services',
                          prefixIcon: const Icon(Icons.business, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            val == null || val.trim().isEmpty ? 'Business name is required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _licenseController,
                        decoration: InputDecoration(
                          labelText: 'BIR TIN / Business Registration No. *',
                          hintText: 'e.g. TIN: 009-876-543-000 or APP-2026-XXXX',
                          prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            val == null || val.trim().isEmpty ? 'Registration or TIN number is required' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedSpecialization,
                        decoration: InputDecoration(
                          labelText: 'Primary Specialization *',
                          prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _specializations
                            .map((spec) => DropdownMenuItem(value: spec, child: Text(spec, style: const TextStyle(fontSize: 14))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedSpecialization = val);
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Business Phone / Mobile *',
                          hintText: 'e.g. +63 917 123 4567',
                          prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            val == null || val.trim().isEmpty ? 'Contact phone number is required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'Business Address / City *',
                          hintText: 'e.g. 45 Rizal Avenue, Cebu City',
                          prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            val == null || val.trim().isEmpty ? 'Business address is required' : null,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Section 2: BIR Permits & Document Uploads
                  _buildSectionCard(
                    title: '2. BIR Permit & Business Papers',
                    icon: Icons.document_scanner_outlined,
                    children: [
                      const Text(
                        'Select the primary document you are uploading:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPermitType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Document Type',
                          prefixIcon: const Icon(Icons.description_outlined, color: Color(0xFF7B40B5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _permitTypes
                            .map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedPermitType = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Document upload guide box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.camera_alt_outlined, color: Color(0xFF7B40B5), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Take a sharp, well-lit photo of your BIR Form 2303, DTI Certificate, Mayor\'s Permit, or accreditation. Make sure the TIN, business name, and official stamps are legible.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF4A154B), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Pick Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickFromCamera,
                              icon: const Icon(Icons.photo_camera, color: Color(0xFF7B40B5)),
                              label: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF7B40B5), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _pickFromGallery,
                              icon: const Icon(Icons.photo_library, color: Colors.white),
                              label: const Text('From Gallery', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B40B5),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_photoError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _photoError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Attached Photos Previews
                      if (_pickedFiles.isEmpty && _existingUrls.isEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text(
                                'No document photos attached yet',
                                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                'Submit at least 1 photo of your BIR permit',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Attached Documents (${_existingUrls.length + _pickedFiles.length}):',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            // Existing URLs
                            ..._existingUrls.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final url = entry.value;
                              return _buildExistingImageThumbnail(url, idx);
                            }),
                            // Newly Picked Files
                            ..._pickedFiles.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final file = entry.value;
                              return _buildPickedFileThumbnail(file, idx);
                            }),
                          ],
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Section 3: Optional Notes
                  _buildSectionCard(
                    title: '3. Additional Notes (Optional)',
                    icon: Icons.note_alt_outlined,
                    children: [
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Include any remarks, branches, or notes for the admin reviewer...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitApplication,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      label: const Text(
                        'Submit for Admin Verification',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B40B5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF7B40B5)),
                      const SizedBox(height: 18),
                      Text(
                        _loadingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF7B40B5), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildExistingImageThumbnail(String url, int index) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            DocumentViewerDialog.show(
              context,
              imageUrls: _existingUrls,
              initialIndex: index,
              title: _businessNameController.text.isNotEmpty
                  ? _businessNameController.text
                  : 'Document Preview',
              subtitle: _selectedPermitType,
            );
          },
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7B40B5), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeExistingUrl(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Saved', style: TextStyle(color: Colors.white, fontSize: 9)),
          ),
        ),
      ],
    );
  }

  Widget _buildPickedFileThumbnail(XFile file, int index) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.shade300, width: 1.5),
            color: Colors.grey[200],
          ),
          child: FutureBuilder<Widget>(
            future: _buildImageFromFile(file),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: snapshot.data!,
                );
              }
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            },
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removePickedFile(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 9)),
          ),
        ),
      ],
    );
  }

  Future<Widget> _buildImageFromFile(XFile file) async {
    final bytes = await file.readAsBytes();
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
