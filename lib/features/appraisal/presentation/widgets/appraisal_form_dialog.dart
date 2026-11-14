import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lendly/features/appraisal/domain/models/appraisal_model.dart';
import 'package:lendly/features/appraisal/presentation/widgets/owner_meetup_scanner_dialog.dart';
import 'package:lendly/features/items/data/repositories/item_repository_impl.dart';

class AppraisalFormDialog extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final String itemId;
  final String? convoId;
  final bool isMeetupPreVerified;

  const AppraisalFormDialog({
    super.key,
    required this.itemData,
    required this.itemId,
    this.convoId,
    this.isMeetupPreVerified = false,
  });

  @override
  State<AppraisalFormDialog> createState() => _AppraisalFormDialogState();
}

class _AppraisalFormDialogState extends State<AppraisalFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _estimatedValController;
  late TextEditingController _notesController;
  late TextEditingController _certIdController;

  // Function: 1 - 10 and Cosmetic: 1 - 10
  int _functionScore = 8;
  int _cosmeticScore = 8;
  late String _conditionGrade;

  bool _isSerialVerified = true;
  bool _isCleanWorking = true;
  bool _isDepositRecommended = true;

  // Owner Meetup Verification
  bool _isOwnerMeetupVerified = false;
  String _meetupMethod = 'qr_scan'; // Enforce strict QR scan verification
  DateTime? _meetupVerifiedAt;

  // Documented Defects
  bool _hasDefects = false;
  final List<DocumentedDefect> _defects = [];
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingDefectPhoto = false;

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
    
    // Appraisal comments left empty by default!
    _notesController = TextEditingController(
      text: widget.itemData['appraiserNotes'] ?? '',
    );

    final existingCert = widget.itemData['appraisalCertificateId'];
    if (existingCert is String && existingCert.isNotEmpty) {
      _certIdController = TextEditingController(text: existingCert);
    } else {
      final randomCode = Random().nextInt(899999) + 100000;
      _certIdController = TextEditingController(text: 'CERT-2026-APP$randomCode');
    }

    // Existing meetup verification state or pre-verified from chat QR scan
    if (widget.isMeetupPreVerified || widget.itemData['isOwnerMeetupVerified'] == true) {
      _isOwnerMeetupVerified = true;
      _meetupMethod = 'qr_scan';
      if (widget.itemData['meetupVerifiedAt'] is Timestamp) {
        _meetupVerifiedAt = (widget.itemData['meetupVerifiedAt'] as Timestamp).toDate();
      } else {
        _meetupVerifiedAt = DateTime.now();
      }
    }

    // Existing documented defects
    if (widget.itemData['documentedDefects'] is List) {
      final rawList = widget.itemData['documentedDefects'] as List;
      for (var item in rawList) {
        if (item is Map) {
          _defects.add(DocumentedDefect.fromMap(Map<String, dynamic>.from(item)));
        }
      }
      _hasDefects = _defects.isNotEmpty || (widget.itemData['hasDefects'] == true);
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
    _notesController.dispose();
    _certIdController.dispose();
    super.dispose();
  }

  Future<void> _scanOwnerQr() async {
    final ownerId = (widget.itemData['ownerId'] ?? '').toString();
    final ownerName = (widget.itemData['ownerName'] ?? 'Owner').toString();

    if (ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item owner information is missing.')),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => OwnerMeetupScannerDialog(
        expectedOwnerId: ownerId,
        ownerName: ownerName,
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _isOwnerMeetupVerified = true;
        _meetupMethod = 'qr_scan';
        _meetupVerifiedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.verified, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text('Meetup with $ownerName successfully verified!'),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    }
  }

  Future<void> _showAddDefectDialog() async {
    String category = 'Cosmetic / Surface';
    String severity = 'Minor';
    final descController = TextEditingController();
    String? localPhotoPath;

    final categories = [
      'Cosmetic / Surface',
      'Functional / Mechanical',
      'Electrical / Battery',
      'Screen / Optics',
      'Missing Accessory',
      'Other',
    ];

    final severities = ['Minor', 'Moderate', 'Major'];

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.report_problem_outlined, color: Color(0xFFD97706), size: 22),
                SizedBox(width: 8),
                Text('Add Documented Defect', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Defect Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) {
                      if (val != null) setDlgState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Severity Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: severities.map((s) {
                      final isSel = severity == s;
                      final col = DocumentedDefect.getSeverityColor(s);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : col, fontWeight: FontWeight.bold)),
                          selected: isSel,
                          selectedColor: col,
                          backgroundColor: col.withValues(alpha: 0.1),
                          onSelected: (sel) {
                            if (sel) setDlgState(() => severity = s);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Defect Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'e.g. 2cm scratch on bottom base plate, lens cap missing...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Defect Evidence Photo (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (localPhotoPath != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(localPhotoPath!), width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setDlgState(() => localPhotoPath = null),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ] else
                    OutlinedButton.icon(
                      onPressed: () async {
                        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                        if (photo != null) {
                          setDlgState(() => localPhotoPath = photo.path);
                        }
                      },
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Capture Defect Photo', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF98259A),
                        side: const BorderSide(color: Color(0xFF98259A)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF98259A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final desc = descController.text.trim();
                  if (desc.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a description for the defect.')),
                    );
                    return;
                  }

                  String? uploadedUrl;
                  if (localPhotoPath != null) {
                    setState(() => _isUploadingDefectPhoto = true);
                    Navigator.pop(dlgCtx);
                    try {
                      final urls = await ItemRepositoryImpl().uploadImages([localPhotoPath!]);
                      if (urls.isNotEmpty) uploadedUrl = urls.first;
                    } catch (e) {
                      debugPrint('Error uploading defect photo: $e');
                    } finally {
                      setState(() => _isUploadingDefectPhoto = false);
                    }
                  } else {
                    Navigator.pop(dlgCtx);
                  }

                  setState(() {
                    _defects.add(
                      DocumentedDefect(
                        category: category,
                        severity: severity,
                        description: desc,
                        photoUrl: uploadedUrl,
                      ),
                    );
                    _hasDefects = true;
                    // If a major/moderate defect is added, clean working status automatically reflects defects
                    if (severity == 'Major' || category.contains('Functional')) {
                      _isCleanWorking = false;
                    }
                  });
                },
                child: const Text('Add Defect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitAppraisal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ownerId = (widget.itemData['ownerId'] ?? '').toString();

    // Prevent fraudulent self-appraisal
    if (uid.isNotEmpty && uid == ownerId) {
      _showAppraisalError('Self-Appraisal Prohibited: You cannot certify or appraise your own item listing.');
      return;
    }

    // 1. Enforce Owner Meetup Requirement via QR scan
    if (!_isOwnerMeetupVerified) {
      _showAppraisalError('Owner Meetup Required: You must verify your in-person physical meeting with the owner via QR scan before certifying this appraisal.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final businessName = _appraiserProfile?['businessName'] as String? ?? 'Licensed Professional Appraiser';
      final licenseNo = _appraiserProfile?['licenseNumber'] as String? ?? 'APP-2026-VERIFIED';

      final estimatedVal = double.tryParse(_estimatedValController.text.replaceAll(',', '').trim()) ?? 5000.0;
      final overallScore = AppraisalModel.calculateOverallScore(_functionScore, _cosmeticScore);

      final appraisalModel = AppraisalModel(
        functionScore: _functionScore,
        cosmeticScore: _cosmeticScore,
        overallScore: overallScore,
        conditionGrade: _conditionGrade,
        estimatedValue: estimatedVal,
        certificateId: _certIdController.text.trim(),
        appraiserId: uid,
        appraiserBusinessName: businessName,
        appraiserLicense: licenseNo,
        notes: _notesController.text.trim(),
        appraisedAt: DateTime.now(),
        isSerialVerified: _isSerialVerified,
        isCleanWorking: _isCleanWorking,
        isDepositRecommended: _isDepositRecommended,
        isOwnerMeetupVerified: _isOwnerMeetupVerified,
        meetupVerificationMethod: _meetupMethod,
        meetupVerifiedAt: _meetupVerifiedAt ?? DateTime.now(),
        hasDefects: _hasDefects && _defects.isNotEmpty,
        documentedDefects: _hasDefects ? _defects : [],
      );

      final updateMap = appraisalModel.toMap();
      updateMap['appraisedDate'] = FieldValue.serverTimestamp();
      // NOTE: Intentionally DO NOT overwrite 'price' so only the owner controls daily rate!

      await FirebaseFirestore.instance.collection('items').doc(widget.itemId).update(updateMap);

      // Update appraisal conversation if opened from chat
      if (widget.convoId != null && widget.convoId!.isNotEmpty) {
        final convoRef = FirebaseFirestore.instance.collection('conversations').doc(widget.convoId!);
        await convoRef.update({
          'isAppraisalCompleted': true,
          'appraisalCompletedAt': FieldValue.serverTimestamp(),
          'certifiedCondition': _conditionGrade,
          'conditionGrade': _conditionGrade,
          'appraisalCertificateId': _certIdController.text.trim(),
          'appraisalValue': estimatedVal,
          'lastMessageText': 'Official appraisal certified: Grade $_conditionGrade',
          'lastUpdated': FieldValue.serverTimestamp(),
        }).catchError((_) {});

        await convoRef.collection('messages').add({
          'senderId': uid,
          'type': 'appraisal_completed',
          'conditionGrade': _conditionGrade,
          'functionScore': _functionScore,
          'cosmeticScore': _cosmeticScore,
          'estimatedValue': estimatedVal,
          'certificateId': _certIdController.text.trim(),
          'hasDefects': _hasDefects && _defects.isNotEmpty,
          'defectCount': _defects.length,
          'notes': _notesController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }

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
            backgroundColor: const Color(0xFF98259A),
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

  void _showAppraisalError(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.handshake_outlined, color: Color(0xFF98259A), size: 24),
            SizedBox(width: 8),
            Text('Meetup Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(msg, style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF98259A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.itemData['name'] ?? widget.itemData['title'] ?? 'Item';
    final ownerName = widget.itemData['ownerName'] ?? 'Lender';
    final currentPrice = (widget.itemData['price'] as num?)?.toDouble() ?? 0.0;
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
                        color: const Color(0xFF98259A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_outlined, color: Color(0xFF98259A), size: 28),
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

                // Item Summary Card (Shows read-only daily rate set by owner)
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
                          color: const Color(0xFF98259A).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF98259A), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Category: $category • Owner: $ownerName',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₱${currentPrice.toStringAsFixed(0)}/day',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF98259A), fontSize: 14),
                          ),
                          const Text('Owner Rate (Locked)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // 0. OWNER MEETUP VERIFICATION (REQUIRED PROCESS)
                // ----------------------------------------------------
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isOwnerMeetupVerified ? const Color(0xFFF0FDF4) : const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isOwnerMeetupVerified ? const Color(0xFF86EFAC) : const Color(0xFF98259A).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isOwnerMeetupVerified ? Icons.check_circle_rounded : Icons.handshake_outlined,
                            color: _isOwnerMeetupVerified ? const Color(0xFF16A34A) : const Color(0xFF98259A),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'In-Person Owner Meetup Verification',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _isOwnerMeetupVerified ? const Color(0xFF15803D) : const Color(0xFF4A1A7E),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isOwnerMeetupVerified ? const Color(0xFFDCFCE7) : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isOwnerMeetupVerified ? const Color(0xFF86EFAC) : Colors.red.shade200,
                              ),
                            ),
                            child: Text(
                              _isOwnerMeetupVerified ? 'VERIFIED' : 'REQUIRED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _isOwnerMeetupVerified ? const Color(0xFF15803D) : Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isOwnerMeetupVerified
                            ? 'Physical meetup with $ownerName verified via in-person QR code scan.'
                            : 'Appraisals require an in-person meeting with the item owner ($ownerName) to inspect the physical hardware. QR scan is required to prevent fraud.',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      if (!_isOwnerMeetupVerified) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _scanOwnerQr,
                            icon: const Icon(Icons.qr_code_scanner, size: 16),
                            label: const Text('Scan Owner QR to Verify Meetup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF98259A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                            const SizedBox(width: 4),
                            Text(
                              'Verified in-person at ${_meetupVerifiedAt != null ? "${_meetupVerifiedAt!.hour.toString().padLeft(2, '0')}:${_meetupVerifiedAt!.minute.toString().padLeft(2, '0')}" : "Today"}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // 1. QUESTION: FUNCTION (1 - 10)
                // ----------------------------------------------------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF98259A).withValues(alpha: 0.25)),
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
                              Icon(Icons.build_circle_outlined, color: Color(0xFF98259A), size: 18),
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
                              color: const Color(0xFF98259A),
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
                          activeTrackColor: const Color(0xFF98259A),
                          inactiveTrackColor: Colors.grey.shade200,
                          thumbColor: const Color(0xFF98259A),
                          overlayColor: const Color(0xFF98259A).withValues(alpha: 0.2),
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
                                    color: isSelected ? const Color(0xFF98259A) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF98259A) : Colors.grey.shade300,
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
                          const Expanded(
                            child: Text(
                              'Basis for Appraised Condition',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 6),
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
                // 4. DOCUMENTED DEFECTS (NEW FEATURE)
                // ----------------------------------------------------
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _defects.isNotEmpty ? const Color(0xFFD97706) : Colors.grey.shade300,
                      width: _defects.isNotEmpty ? 1.5 : 1,
                    ),
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
                          Row(
                            children: [
                              Icon(
                                Icons.report_problem_outlined,
                                color: _defects.isNotEmpty ? const Color(0xFFD97706) : Colors.grey.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Documented Defects',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _showAddDefectDialog,
                            icon: const Icon(Icons.add_circle_outline, size: 15, color: Color(0xFF98259A)),
                            label: const Text('Add Defect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF98259A))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Record pre-existing scratches, wear, or imperfections found during inspection. These protect the borrower and owner on the lending contract.',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3),
                      ),
                      if (_isUploadingDefectPhoto) ...[
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF98259A))),
                            SizedBox(width: 8),
                            Text('Uploading defect photo...', style: TextStyle(fontSize: 11, color: Color(0xFF98259A))),
                          ],
                        ),
                      ],
                      if (_defects.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Column(
                          children: _defects.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final defect = entry.value;
                            final sevColor = DocumentedDefect.getSeverityColor(defect.severity);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (defect.photoUrl != null && defect.photoUrl!.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        defect.photoUrl!,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(width: 44, height: 44, color: Colors.grey[200]),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: sevColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(Icons.broken_image_outlined, size: 20, color: sevColor),
                                    ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: sevColor,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                defect.severity.toUpperCase(),
                                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              defect.category,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          defect.description,
                                          style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        _defects.removeAt(idx);
                                        if (_defects.isEmpty) _hasDefects = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF059669)),
                              const SizedBox(width: 6),
                              Text('No defects documented yet (Clean hardware)', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // 5. ESTIMATED VALUE (OWNER PRIVATE) - NO DAILY RATE INPUT!
                // ----------------------------------------------------
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Estimated Replacement Value (₱)',
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
                          'Private to Owner: This estimated value is saved in the system and visible only to the item owner and appraisers (hidden from public borrowers). Only the owner sets the daily rental rate.',
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
                  activeColor: const Color(0xFF98259A),
                  title: const Text('Serial Number & Hardware Authenticity Verified', style: TextStyle(fontSize: 12)),
                  value: _isSerialVerified,
                  onChanged: (val) => setState(() => _isSerialVerified = val ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF98259A),
                  title: const Text('Clean Functional Testing (No Hidden Defect)', style: TextStyle(fontSize: 12)),
                  value: _isCleanWorking,
                  onChanged: (val) => setState(() => _isCleanWorking = val ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF98259A),
                  title: const Text('Recommend Security Deposit Protection for Owner', style: TextStyle(fontSize: 12)),
                  value: _isDepositRecommended,
                  onChanged: (val) => setState(() => _isDepositRecommended = val ?? true),
                ),

                const SizedBox(height: 12),

                // Appraiser Inspection Notes (Empty by default)
                const Text('Appraiser Inspection Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Enter technical inspection details (optional)...',
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
                      backgroundColor: const Color(0xFF98259A),
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
