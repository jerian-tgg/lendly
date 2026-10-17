import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/appraisal/domain/models/appraisal_model.dart';

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
  late TextEditingController _estimatedValController;
  late TextEditingController _dailyRentalValController;
  late TextEditingController _notesController;
  late TextEditingController _certIdController;

  // Function: 1 - 10 and Cosmetic: 1 - 10
  int _functionScore = 8;
  int _cosmeticScore = 8;
  late String _conditionGrade;

  bool _isSerialVerified = true;
  bool _isCleanWorking = true;
  bool _isDepositRecommended = true;

  bool _isSubmitting = false;
  Map<String, dynamic>? _appraiserProfile;

  @override
  void initState() {
    super.initState();

    // Initialize scores from existing item data if previously appraised
    if (widget.itemData['functionScore'] is num) {
      _functionScore = (widget.itemData['functionScore'] as num).toInt().clamp(1, 10);
    }
    if (widget.itemData['cosmeticScore'] is num) {
      _cosmeticScore = (widget.itemData['cosmeticScore'] as num).toInt().clamp(1, 10);
    }

    _updateCalculatedGrade();

    final initialPrice = (widget.itemData['price'] as num?)?.toDouble() ?? 500.0;
    final initialAppraisal = (widget.itemData['appraisalValue'] as num?)?.toDouble() ??
        (widget.itemData['appraisal'] as num?)?.toDouble() ??
        (initialPrice * 25);

    _estimatedValController = TextEditingController(text: initialAppraisal.toStringAsFixed(0));
    _dailyRentalValController = TextEditingController(text: initialPrice.toStringAsFixed(0));
    _notesController = TextEditingController(
      text: widget.itemData['appraiserNotes'] ??
          'Inspected physical hardware, buttons, and ports. Function test passed. Overall condition verified.',
    );

    final existingCert = widget.itemData['appraisalCertificateId'];
    if (existingCert is String && existingCert.isNotEmpty) {
      _certIdController = TextEditingController(text: existingCert);
    } else {
      final randomCode = Random().nextInt(899999) + 100000;
      _certIdController = TextEditingController(text: 'CERT-2026-APP$randomCode');
    }

    _fetchAppraiserProfile();
  }

  void _updateCalculatedGrade() {
    _conditionGrade = AppraisalModel.calculateConditionGrade(_functionScore, _cosmeticScore);
  }

  Future<void> _fetchAppraiserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _appraiserProfile = doc.data();
      });
    }
  }

  @override
  void dispose() {
    _estimatedValController.dispose();
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
      final businessName = _appraiserProfile?['businessName'] as String? ?? 'Licensed Professional Appraiser';
      final licenseNo = _appraiserProfile?['licenseNumber'] as String? ?? 'APP-2026-VERIFIED';

      final estimatedVal = double.tryParse(_estimatedValController.text.replaceAll(',', '').trim()) ?? 5000.0;
      final dailyRentalVal = double.tryParse(_dailyRentalValController.text.replaceAll(',', '').trim()) ?? 500.0;
      final overallScore = AppraisalModel.calculateOverallScore(_functionScore, _cosmeticScore);

      final appraisalModel = AppraisalModel(
        functionScore: _functionScore,
        cosmeticScore: _cosmeticScore,
        overallScore: overallScore,
        conditionGrade: _conditionGrade,
        estimatedValue: estimatedVal,
        suggestedDailyRate: dailyRentalVal,
        certificateId: _certIdController.text.trim(),
        appraiserId: uid,
        appraiserBusinessName: businessName,
        appraiserLicense: licenseNo,
        notes: _notesController.text.trim(),
        appraisedAt: DateTime.now(),
        isSerialVerified: _isSerialVerified,
        isCleanWorking: _isCleanWorking,
        isDepositRecommended: _isDepositRecommended,
      );

      final updateMap = appraisalModel.toMap();
      updateMap['appraisedDate'] = FieldValue.serverTimestamp();
      updateMap['price'] = dailyRentalVal; // Suggested or current rate

      await FirebaseFirestore.instance.collection('items').doc(widget.itemId).update(updateMap);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.verified, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Appraisal Certified: Grade "$_conditionGrade" • Estimated ₱${estimatedVal.toStringAsFixed(0)} (Private)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF7B40B5),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving appraisal: $e')),
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
    final category = widget.itemData['category'] ?? 'General';
    final overallScore = AppraisalModel.calculateOverallScore(_functionScore, _cosmeticScore);
    final conditionColor = AppraisalModel.getConditionColor(_conditionGrade);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 820),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modal Header
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
                            'Professional Appraisal Rating',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          Text(
                            'Inspector: ${_appraiserProfile?['businessName'] ?? 'Certified Appraiser'}',
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

                // Item Summary Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('Category: $category • Owner: $ownerName', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ----------------------------------------------------
                // 1. QUESTION: FUNCTION (1 - 10)
                // ----------------------------------------------------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.build_circle_outlined, color: Color(0xFF7B40B5), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Function: 1-10',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B40B5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$_functionScore / 10',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Rubric Guide
                      Text(
                        AppraisalModel.getFunctionRubric(_functionScore),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _functionScore >= 8
                              ? const Color(0xFF059669)
                              : _functionScore >= 5
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFFDC2626),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF7B40B5),
                          inactiveTrackColor: Colors.grey.shade200,
                          thumbColor: const Color(0xFF7B40B5),
                          overlayColor: const Color(0xFF7B40B5).withValues(alpha: 0.2),
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: _functionScore.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          onChanged: (val) {
                            setState(() {
                              _functionScore = val.round();
                              _updateCalculatedGrade();
                            });
                          },
                        ),
                      ),

                      // Quick Step Buttons (1 - 10)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(10, (idx) {
                            final score = idx + 1;
                            final isSelected = score == _functionScore;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _functionScore = score;
                                    _updateCalculatedGrade();
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF7B40B5) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF7B40B5) : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '$score',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ----------------------------------------------------
                // 2. QUESTION: COSMETIC (1 - 10)
                // ----------------------------------------------------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Color(0xFF0284C7), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Cosmetic: 1-10',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$_cosmeticScore / 10',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Rubric Guide
                      Text(
                        AppraisalModel.getCosmeticRubric(_cosmeticScore),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _cosmeticScore >= 8
                              ? const Color(0xFF059669)
                              : _cosmeticScore >= 5
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFFDC2626),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF0284C7),
                          inactiveTrackColor: Colors.grey.shade200,
                          thumbColor: const Color(0xFF0284C7),
                          overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: _cosmeticScore.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          onChanged: (val) {
                            setState(() {
                              _cosmeticScore = val.round();
                              _updateCalculatedGrade();
                            });
                          },
                        ),
                      ),

                      // Quick Step Buttons (1 - 10)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(10, (idx) {
                            final score = idx + 1;
                            final isSelected = score == _cosmeticScore;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _cosmeticScore = score;
                                    _updateCalculatedGrade();
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF0284C7) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF0284C7) : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '$score',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ----------------------------------------------------
                // 3. BASIS FOR APPRAISED CONDITION (DYNAMIC RESULT)
                // ----------------------------------------------------
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        conditionColor.withValues(alpha: 0.08),
                        conditionColor.withValues(alpha: 0.03),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: conditionColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.workspace_premium, color: conditionColor, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Basis for Appraised Condition',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: conditionColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'Score: ${overallScore.toStringAsFixed(1)} / 10',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: conditionColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Official Condition Grade:',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: conditionColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _conditionGrade,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Automatically calculated: Function ($_functionScore) + Cosmetic ($_cosmeticScore) → $_conditionGrade',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // 4. ESTIMATED VALUE & RENTAL PRICING
                // ----------------------------------------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Estimated Value (₱)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Market/replacement value. Private to the item owner & certified appraisers.',
                                child: Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _estimatedValController,
                            keyboardType: TextInputType.number,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Required';
                              final n = double.tryParse(val.replaceAll(',', '').trim());
                              if (n == null || n <= 0) return 'Invalid value';
                              return null;
                            },
                            decoration: InputDecoration(
                              prefixText: '₱ ',
                              hintText: 'e.g. 25000',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Daily Rate (₱)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _dailyRentalValController,
                            keyboardType: TextInputType.number,
                            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                            decoration: InputDecoration(
                              prefixText: '₱ ',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Confidential Privacy Note
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: Color(0xFF16A34A)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Private to Owner: This estimated value is saved in the system and visible only to the item owner and appraisers (hidden from public borrowers).',
                          style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Verification Standards
                const Text('Inspection Standards', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                  title: const Text('Recommend Security Deposit Protection for Owner', style: TextStyle(fontSize: 12)),
                  value: _isDepositRecommended,
                  onChanged: (val) => setState(() => _isDepositRecommended = val ?? true),
                ),

                const SizedBox(height: 12),

                // Appraiser Inspection Notes
                const Text('Appraiser Inspection Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Enter technical inspection details...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),

                const SizedBox(height: 12),

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

                const SizedBox(height: 22),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitAppraisal,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.verified, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Saving Appraisal...' : 'Sign & Certify Official Appraisal',
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
