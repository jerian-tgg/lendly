import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/core/services/didit/didit_verification_service.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/features/appraisal/presentation/pages/appraisal_dashboard.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/profile/data/datasources/firebase_user_service.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';
import 'package:lendly/core/utils/image_utils.dart';

class UserProfilePage extends StatefulWidget {
  final String? userId; // If null, displays current logged-in user's profile

  const UserProfilePage({super.key, this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with WidgetsBindingObserver {
  final FirebaseUserService _userService = FirebaseUserService();
  final DiditVerificationService _diditService = DiditVerificationService();

  bool? _localIsVerified;
  bool _isVerifying = false;
  String? _pendingSessionId;
  Timer? _statusPollTimer;

  String get _targetUserId {
    return widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  bool get _isSelf {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return widget.userId == null || widget.userId == currentUid;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPendingVerification();
    }
  }

  DiditVerificationCallbacks _verificationCallbacks() {
    return DiditVerificationCallbacks(
      onOpened: (sessionId) async {
        if (!mounted) return;
        setState(() {
          _pendingSessionId = sessionId;
          _isVerifying = false;
        });
        _startStatusPolling();

        try {
          await _userService.updateUserVerificationStatus(
            isVerified: false,
            sessionId: sessionId,
            status: 'Not Started',
          );
        } catch (e) {
          debugPrint('Error recording Didit session: $e');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete ID and liveness verification on the Didit page, then return here.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      },
      onSuccess: (sessionId) async {
        if (!mounted) return;

        setState(() {
          _localIsVerified = true;
          _isVerifying = false;
          _pendingSessionId = null;
        });
        _statusPollTimer?.cancel();

        try {
          await _userService.updateUserVerificationStatus(
            isVerified: true,
            sessionId: sessionId,
            status: 'Approved',
          );
        } catch (e) {
          debugPrint('Error updating verification status in database: $e');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Identity verified successfully! Verified badge granted.',
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 4),
          ),
        );
      },
      onPending: (sessionId) async {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
        });

        try {
          await _userService.updateUserVerificationStatus(
            isVerified: false,
            sessionId: sessionId,
            status: 'In Review',
          );
        } catch (e) {
          debugPrint('Error recording pending verification: $e');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your verification has been submitted and is in review.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      },
      onDeclined: (sessionId) async {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _pendingSessionId = null;
        });
        _statusPollTimer?.cancel();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification was not approved. Please try again with a valid ID.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      },
      onCancelled: () {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification was cancelled.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      onFailure: (errorMessage) {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $errorMessage'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshPendingVerification();
    });
  }

  Future<void> _refreshPendingVerification() async {
    final sessionId = _pendingSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    await _diditService.refreshSessionStatus(
      sessionId: sessionId,
      callbacks: _verificationCallbacks(),
    );
  }

  Future<void> _handleStartVerification() async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
    });

    try {
      await _diditService.startVerificationFlow(
        callbacks: _verificationCallbacks(),
      );
    } finally {
      if (mounted && _isVerifying) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _handleDirectChat(
    BuildContext context,
    String targetName,
  ) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to send a message.')),
      );
      return;
    }

    try {
      final convoId = await createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: _targetUserId,
        itemId: '',
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              convoId: convoId,
              currentUserId: currentUserId,
              otherUserId: _targetUserId,
              otherUserName: targetName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
      }
    }
  }

  Widget _buildVerifyButton() {
    if (_isVerifying) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF0077B6)),
        ),

        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF0077B6),
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Verifying...',
              style: TextStyle(
                color: Color(0xFF0077B6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _handleStartVerification,
      icon: const Icon(Icons.verified_user_outlined, size: 16),
      label: const Text(
        'Verify',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0077B6),
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF81C784), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Color(0xFF2E7D32), size: 16),
          SizedBox(width: 6),
          Text(
            'Verified',
            style: TextStyle(
              color: Color(0xFF2E7D32),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showRegisterAppraiserDialog(BuildContext context) {
    final bNameController = TextEditingController();
    final licController = TextEditingController();
    String spec = 'Electronics & Technology';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Color(0xFF7B40B5)),
              SizedBox(width: 8),
              Text(
                'Appraiser Registration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upgrade your account to issue certified appraisals.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bNameController,
                  decoration: InputDecoration(
                    labelText: 'Business / Agency Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: licController,
                  decoration: InputDecoration(
                    labelText: 'License / Accreditation No.',
                    hintText: 'e.g. APP-2026-8891',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Primary Specialization',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: spec,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Electronics & Technology',
                      child: Text(
                        'Electronics & Tech',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Industrial Tools & Equipment',
                      child: Text(
                        'Tools & Equipment',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Jewelry & Luxury Goods',
                      child: Text(
                        'Jewelry & Luxury',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Vehicles & Transport',
                      child: Text(
                        'Vehicles & Transport',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'General Merchandise',
                      child: Text(
                        'General Merchandise',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) spec = val;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final bName = bNameController.text.trim();
                final lic = licController.text.trim();
                if (bName.isEmpty || lic.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                    ),
                  );
                  return;
                }

                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .set({
                        'isAppraiser': true,
                        'isBusiness': true,
                        'accountType': 'appraiser',
                        'businessName': bName,
                        'licenseNumber': lic,
                        'specialization': spec,
                      }, SetOptions(merge: true));

                  if (context.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Registration successful! You are now a Professional Appraiser.',
                        ),
                        backgroundColor: Color(0xFF7B40B5),
                      ),
                    );
                    setState(() {});
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B40B5),
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit & Register'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _isSelf ? 'My Profile' : 'User Profile',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_targetUserId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF7B40B5),
                      ),
                    ),
                  );
                }

                Map<String, dynamic> userData = {};
                if (snapshot.hasData && snapshot.data!.exists) {
                  userData = snapshot.data!.data() as Map<String, dynamic>;
                }

                final displayName =
                    userData['username'] ??
                    '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                        .trim();
                final nameStr = displayName.isNotEmpty
                    ? displayName
                    : 'Lendly User';
                final location =
                    userData['location'] is String &&
                        (userData['location'] as String).isNotEmpty
                    ? userData['location']
                    : 'Location not specified';
                final phone = userData['phone'] ?? '';
                final profilePictureUrl =
                    userData['photoURL'] ?? userData['profilePictureUrl'];
                final imageUrl = profilePictureUrl is String
                    ? profilePictureUrl
                    : '';

                final bool firestoreIsVerified = userData['isVerified'] == true;
                final bool isVerified = _localIsVerified ?? firestoreIsVerified;

                return Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFFEFE8FA),
                          backgroundImage: isValidImageUrl(imageUrl)
                              ? NetworkImage(imageUrl)
                              : null,
                          child: !isValidImageUrl(imageUrl)
                              ? const Icon(
                                  Icons.person,
                                  size: 55,
                                  color: Color(0xFF7B40B5),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      nameStr,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Color(0xFF7B40B5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7B40B5,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                '4.9 Verified Lender',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF7B40B5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Action Buttons (Edit Profile if Self, Message/Contact if Viewing Another User)
                    if (_isSelf)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EditProfilePage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B40B5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _handleDirectChat(context, nameStr),
                            icon: const Icon(
                              Icons.chat_bubble_rounded,
                              size: 18,
                            ),
                            label: const Text('Send Message'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B40B5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                          ),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Contact: $phone')),
                                );
                              },
                              icon: const Icon(Icons.phone, size: 18),
                              label: const Text('Call'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF7B40B5),
                                side: const BorderSide(
                                  color: Color(0xFF7B40B5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                    const SizedBox(height: 16),

                    // Appraiser Portal / Registration Section
                    if (_isSelf) ...[
                      if (userData['isAppraiser'] == true) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5A2A94), Color(0xFF7B40B5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF7B40B5,
                                ).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.verified,
                                    color: Colors.amber,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userData['businessName'] is String &&
                                                  (userData['businessName']
                                                          as String)
                                                      .isNotEmpty
                                              ? userData['businessName']
                                              : 'Professional Appraisal Business',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'Lic #: ${userData['licenseNumber'] ?? 'APP-2026-REG'}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AppraisalDashboard(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.assessment_rounded,
                                    color: Color(0xFF7B40B5),
                                  ),
                                  label: const Text(
                                    'Open Professional Appraisal Portal',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF7B40B5),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7B40B5,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFF7B40B5,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.business_center,
                                color: Color(0xFF7B40B5),
                                size: 30,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Register as Appraiser',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF7B40B5),
                                      ),
                                    ),
                                    Text(
                                      'Issue official valuation certificates & build lender trust',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    _showRegisterAppraiserDialog(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7B40B5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Apply',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 20),

                    // Section 1: Items Listed by this User
                    _buildSectionHeader(
                      _isSelf ? 'My Listed Items' : 'Items Listed by $nameStr',
                      Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildUserItemsList(_targetUserId),

                    const SizedBox(height: 24),

                    // Section 2: Reviews Received
                    _buildSectionHeader(
                      'Reviews & Ratings',
                      Icons.rate_review_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildUserReviewsList(_targetUserId),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7B40B5), size: 20),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildUserItemsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('ownerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'No items listed yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final item = doc.data() as Map<String, dynamic>;
            final itemTitle = item['name'] ?? item['title'] ?? 'Unnamed Item';
            final itemDesc = item['description'] ?? '';
            final itemPrice = '₱${item['price'] ?? 0}/day';

            List<String> imgs = [];
            if (item['imageUrls'] is List &&
                (item['imageUrls'] as List).isNotEmpty) {
              imgs = List<String>.from(item['imageUrls']);
            } else if (item['imageUrl'] is String &&
                (item['imageUrl'] as String).isNotEmpty) {
              imgs = [item['imageUrl']];
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imgs.isNotEmpty
                      ? Image.network(
                          imgs[0],
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey[200],
                            child: const Icon(Icons.shopping_bag_outlined),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[200],
                          child: const Icon(Icons.shopping_bag_outlined),
                        ),
                ),
                title: Text(
                  itemTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  itemDesc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  itemPrice,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7B40B5),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ItemDetailScreen(itemData: item, itemId: doc.id),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserReviewsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('revieweeId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'No reviews received yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final review = docs[index].data() as Map<String, dynamic>;
            final ratingVal = (review['rating'] as num?)?.toDouble() ?? 5.0;
            final comment =
                review['comment'] ?? review['reviewText'] ?? 'Great lender!';
            final reviewerName = review['reviewerName'] ?? 'Verified Borrower';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEFE8FA),
                  child: Text(
                    reviewerName.isNotEmpty
                        ? reviewerName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Color(0xFF7B40B5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    ...List.generate(5, (starIdx) {
                      return Icon(
                        starIdx < ratingVal.floor()
                            ? Icons.star
                            : Icons.star_border,
                        size: 14,
                        color: Colors.amber[700],
                      );
                    }),
                    const SizedBox(width: 6),
                    Text(
                      reviewerName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(comment, style: const TextStyle(fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
