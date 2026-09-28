import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppraisalFormDialog extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final String itemId;

  const AppraisalFormDialog({
    super.key,
    required this.itemData,
    required this.itemId,
  });

  @override
  State<AppraisalFormDialog> createState() => _AppraisalFormDialogState();
}

class _AppraisalFormDialogState extends State<AppraisalFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _replacementValController;
  late TextEditingController _dailyRentalValController;
  late TextEditingController _notesController;
  late TextEditingController _certIdController;

  String _conditionGrade = 'Excellent (Minor Wear)';
  bool _isSerialVerified = true;
  bool _isCleanWorking = true;
  bool _isOriginalParts = true;
  bool _isDepositRecommended = true;

  bool _isSubmitting = false;
  Map<String, dynamic>? _appraiserProfile;

  final List<String> _conditionGrades = [
    'Mint / Brand New',
    'Excellent (Minor Wear)',
    'Good (Fully Functional)',
    'Fair (Visible Wear)',
    'Requires Repair / Parts',
  ];

  @override
  void initState() {
    super.initState();
    final initialPrice = (widget.itemData['price'] as num?)?.toDouble() ?? 500.0;
    final initialAppraisal = (widget.itemData['appraisal'] as num?)?.toDouble() ?? (initialPrice * 25);

    _replacementValController = TextEditingController(text: initialAppraisal.toStringAsFixed(0));
    _dailyRentalValController = TextEditingController(text: initialPrice.toStringAsFixed(0));
    _notesController = TextEditingController(
      text: 'Inspected physical hardware, controls, and accessories. Item is in verified clean operating condition.',
    );

    final randomCode = Random().nextInt(899999) + 100000;
    _certIdController = TextEditingController(text: 'CERT-2026-APP$randomCode');

    _fetchAppraiserProfile();
  }

  Future<void> _fetchAppraiserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      setState(() {
        _appraiserProfile = doc.data();
      });
    }
  }

  @override
  void dispose() {
    _replacementValController.dispose();
    _dailyRentalValController.dispose();
    _notesController.dispose();
    _certIdController.dispose();
    super.dispose();
  }

  Future<void> _submitAppraisal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final businessName = _appraiserProfile?['businessName'] as String? ?? 'Licensed Appraisals Inc.';
      final licenseNo = _appraiserProfile?['licenseNumber'] as String? ?? 'APP-2026-REG';

      final replacementVal = double.tryParse(_replacementValController.text.replaceAll(',', '').trim()) ?? 5000.0;
      final dailyRentalVal = double.tryParse(_dailyRentalValController.text.replaceAll(',', '').trim()) ?? 500.0;

      await FirebaseFirestore.instance.collection('items').doc(widget.itemId).update({
        'appraisal': replacementVal,
        'appraisalValue': replacementVal,
        'price': dailyRentalVal,
        'appraisalStatus': 'certified',
        'appraisalRequested': false,
        'certifiedByAppraiserId': uid,
        'certifiedByBusinessName': businessName,
        'certifiedByLicense': licenseNo,
        'appraisalCertificateId': _certIdController.text.trim(),
        'appraisedDate': FieldValue.serverTimestamp(),
        'conditionGrade': _conditionGrade,
        'appraiserNotes': _notesController.text.trim(),
        'isSerialVerified': _isSerialVerified,
        'isCleanWorking': _isCleanWorking,
        'isDepositRecommended': _isDepositRecommended,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Appraisal Certificate ${_certIdController.text} issued successfully!'),
            backgroundColor: const Color(0xFF7B40B5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error issuing appraisal: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.itemData['name'] ?? widget.itemData['title'] ?? 'Item';
    final ownerName = widget.itemData['ownerName'] ?? 'Lender';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 750),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B40B5).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_outlined, color: Color(0xFF7B40B5), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Professional Valuation & Certification',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          Text(
                            'Issued by ${_appraiserProfile?['businessName'] ?? 'Licensed Professional Appraiser'}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Item Info Summary Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('Owner: $ownerName', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Valuation Inputs Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Replacement Value (₱)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _replacementValController,
                            keyboardType: TextInputType.number,
                            validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            decoration: InputDecoration(
                              prefixText: '₱ ',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Rental Rate (₱)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _dailyRentalValController,
                            keyboardType: TextInputType.number,
                            validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            decoration: InputDecoration(
                              prefixText: '₱ ',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Condition Grade Dropdown
                const Text('Inspection Condition Grade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _conditionGrade,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.stars, color: Color(0xFF7B40B5)),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  items: _conditionGrades.map((g) {
                    return DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _conditionGrade = val);
                  },
                ),

                const SizedBox(height: 14),

                // Verification Checkboxes
                const Text('Verification Standards', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7B40B5),
                  title: const Text('Serial Number & Hardware Authenticity Verified', style: TextStyle(fontSize: 12)),
                  value: _isSerialVerified,
                  onChanged: (val) => setState(() => _isSerialVerified = val ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7B40B5),
                  title: const Text('Clean Functional Testing (No Hidden Defect)', style: TextStyle(fontSize: 12)),
                  value: _isCleanWorking,
                  onChanged: (val) => setState(() => _isCleanWorking = val ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7B40B5),
                  title: const Text('Original OEM Parts & Accessories Confirmed', style: TextStyle(fontSize: 12)),
                  value: _isOriginalParts,
                  onChanged: (val) => setState(() => _isOriginalParts = val ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7B40B5),
                  title: const Text('Recommend Security Deposit Protection', style: TextStyle(fontSize: 12)),
                  value: _isDepositRecommended,
                  onChanged: (val) => setState(() => _isDepositRecommended = val ?? true),
                ),

                const SizedBox(height: 14),

                // Appraiser Notes
                const Text('Appraiser Inspection Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter technical inspection details...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),

                const SizedBox(height: 14),

                // Certificate ID
                const Text('Certificate ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _certIdController,
                  readOnly: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.shield_outlined, color: Colors.amber),
                    filled: true,
                    fillColor: Colors.amber.withValues(alpha: 0.1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),

                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitAppraisal,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.verified, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Issuing Certificate...' : 'Sign & Issue Official Certificate',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B40B5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
