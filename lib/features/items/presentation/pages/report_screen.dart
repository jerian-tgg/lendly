import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// ──────────────────────────────────────────────────────────────────
// ReportScreen
//
// Usage — report an item:
//   ReportScreen(targetId: itemId, targetType: 'item', targetName: itemName)
//
// Usage — report a user:
//   ReportScreen(targetId: userId, targetType: 'user', targetName: userName)
// ──────────────────────────────────────────────────────────────────

class ReportScreen extends StatefulWidget {
  final String targetId;
  final String targetType; // 'item' | 'user'
  final String targetName;

  const ReportScreen({
    super.key,
    required this.targetId,
    required this.targetType,
    required this.targetName,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _explanationController = TextEditingController();

  String? _selectedReason;
  final List<XFile> _mediaFiles = [];
  bool _submitting = false;

  static const List<String> _reasons = [
    'Fraudulent listing',
    'Inappropriate content',
    'Harassment or abuse',
    'Damaged/misrepresented item',
    'No-show / failed transaction',
    'Counterfeit item',
    'Other',
  ];

  final ImagePicker _picker = ImagePicker();

  // ── Media Picking ──────────────────────────────────────────────

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (file != null) setState(() => _mediaFiles.add(file));
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) setState(() => _mediaFiles.add(file));
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 80);
    if (file != null) setState(() => _mediaFiles.add(file));
  }

  void _removeMedia(int index) =>
      setState(() => _mediaFiles.removeAt(index));

  // ── Upload & Submit ────────────────────────────────────────────

  Future<List<String>> _uploadMedia() async {
    final urls = <String>[];
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    for (final f in _mediaFiles) {
      final ext = f.path.split('.').last;
      final ref = FirebaseStorage.instance
          .ref('reports/${DateTime.now().millisecondsSinceEpoch}_$uid.$ext');
      await ref.putFile(File(f.path));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      _snack('Please select a reason.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final mediaUrls = await _uploadMedia();
      final reporter = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('reports').add({
        'targetId': widget.targetId,
        'targetType': widget.targetType,
        'targetName': widget.targetName,
        'reporterId': reporter?.uid ?? '',
        'reporterName': reporter?.displayName ?? 'Anonymous',
        'reporterEmail': reporter?.email ?? '',
        'reason': _selectedReason,
        'explanation': _explanationController.text.trim(),
        'mediaUrls': mediaUrls,
        'status': 'pending', // pending | reviewed | dismissed
        'createdAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'adminNote': null,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Report submitted. Our team will review it shortly.'),
            ]),
            backgroundColor: const Color(0xFF2ECC71),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      _snack('Failed to submit report. Please try again.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.targetType == 'user';
    final accent = const Color(0xFFE74C3C);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Submit Report',
                style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(
              'Reporting ${isUser ? 'user' : 'item'}: ${widget.targetName}',
              style: const TextStyle(color: Colors.black45, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header notice
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_rounded, color: accent, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Reports are reviewed by our admin team. False reports may result in account suspension.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF333333)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section: Reason
            _SectionLabel(label: '1. Select a reason'),
            const SizedBox(height: 10),
            ..._reasons.map((r) => _ReasonTile(
                  label: r,
                  selected: _selectedReason == r,
                  accent: accent,
                  onTap: () => setState(() => _selectedReason = r),
                )),

            const SizedBox(height: 24),

            // Section: Media
            _SectionLabel(label: '2. Attach evidence (optional)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._mediaFiles.asMap().entries.map((e) => _MediaThumb(
                      file: e.value,
                      onRemove: () => _removeMedia(e.key),
                    )),
                if (_mediaFiles.length < 5) ...[
                  _AddMediaButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: _pickImage,
                    accent: accent,
                  ),
                  _AddMediaButton(
                    icon: Icons.videocam_outlined,
                    label: 'Video',
                    onTap: _pickVideo,
                    accent: accent,
                  ),
                  _AddMediaButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: _takePhoto,
                    accent: accent,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text('Max 5 files (photos or videos)',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),

            const SizedBox(height: 24),

            // Section: Explanation
            _SectionLabel(label: '3. Describe the issue'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _explanationController,
              maxLines: 6,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText:
                    'Provide as much detail as possible about the violation...',
                hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.grey.shade300),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().length < 20)
                      ? 'Please provide at least 20 characters of explanation.'
                      : null,
            ),

            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  disabledBackgroundColor: accent.withValues(alpha: 0.5),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Submit Report',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
            letterSpacing: 0.3),
      );
}

class _ReasonTile extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? accent : Colors.grey.shade300,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? accent : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color:
                        selected ? accent : const Color(0xFF333333))),
          ],
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;
  const _MediaThumb({required this.file, required this.onRemove});

  bool get _isVideo =>
      file.path.toLowerCase().endsWith('.mp4') ||
      file.path.toLowerCase().endsWith('.mov') ||
      file.path.toLowerCase().endsWith('.avi');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _isVideo
              ? Container(
                  width: 80,
                  height: 80,
                  color: Colors.black12,
                  child: const Center(
                      child: Icon(Icons.videocam, size: 32, color: Colors.grey)),
                )
              : Image.file(File(file.path),
                  width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close,
                  color: Colors.white, size: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddMediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  const _AddMediaButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: accent.withValues(alpha: 0.4), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style:
                    TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
