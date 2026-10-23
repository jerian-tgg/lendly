import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/core/services/didit/didit_verification_service.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/appraisal/presentation/pages/appraisal_dashboard.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/business/presentation/pages/register_business_screen.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/items/presentation/pages/report_screen.dart';
import 'package:lendly/features/profile/data/datasources/firebase_user_service.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';
import 'package:lendly/features/profile/presentation/widgets/personal_qr_code_card.dart';
import 'package:lendly/core/utils/image_utils.dart';
import 'package:lendly/features/profile/presentation/widgets/review_dialog.dart';
import 'package:lendly/core/services/review_service.dart';

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

  Future<void> _handleDirectChat(String targetName) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to send a message.')),
        );
      }
      return;
    }

    try {
      final convoId = await createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: _targetUserId,
        itemId: '',
      );

      if (context.mounted) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: $e')),
        );
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

  void _openBusinessRegistration(BuildContext context, [Map<String, dynamic>? data]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterBusinessScreen(existingData: data),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _openReviewDialog(BuildContext context, String targetName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ReviewDialog(
        revieweeId: _targetUserId,
        targetName: targetName,
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
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
        actions: [
          if (!_isSelf)
            IconButton(
              icon: const Icon(Icons.flag_outlined, color: Color(0xFFE74C3C)),
              tooltip: 'Report this user',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportScreen(
                    targetId: _targetUserId,
                    targetType: 'user',
                    targetName: 'User',
                  ),
                ),
              ),
            ),
        ],
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

                final displayName = userData['username'] ??
                    '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
                final nameStr = displayName.isNotEmpty ? displayName : 'Lendly User';
                // Show city from address (human-readable); or formatted location via LocationHelper
                final location = () {
                  final addr = userData['address'];
                  if (addr is Map) {
                    final city = addr['city']?.toString() ?? '';
                    final province = addr['province']?.toString() ?? '';
                    if (city.isNotEmpty) return '$city${province.isNotEmpty ? ', $province' : ''}';
                  }
                  return LocationHelper.formatLocationDisplay(userData['location']);
                }();
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
                        if (isVerified)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            nameStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF2E7D32),
                            size: 20,
                          ),
                        ],
                      ],
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
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (isVerified)
                          _buildVerifiedBadge()
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_outlined, size: 14, color: Colors.grey),
                                SizedBox(width: 4),
                                Text(
                                  'Unverified User',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (userData['isAdmin'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D1457),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield, size: 13, color: Colors.amber),
                                SizedBox(width: 4),
                                Text(
                                  'Administrator',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (userData['isAppraiser'] == true ||
                            userData['businessVerificationStatus'] == 'approved' ||
                            userData['isAdmin'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B40B5).withValues(alpha: 0.15),
                              border: Border.all(color: const Color(0xFF7B40B5)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified, size: 13, color: Color(0xFF7B40B5)),
                                SizedBox(width: 4),
                                Text(
                                  'Certified Appraiser',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7B40B5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Builder(
                          builder: (context) {
                            final userRating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
                            final userReviewCount = (userData['reviewCount'] as num?)?.toInt() ?? 0;
                            final hasReviews = userRating > 0 && userReviewCount > 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    hasReviews ? Icons.star_rounded : Icons.verified_user_outlined,
                                    size: 14,
                                    color: hasReviews ? Colors.amber[700] : const Color(0xFF7B40B5),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    hasReviews
                                        ? '${userRating.toStringAsFixed(1)} ($userReviewCount ${userReviewCount == 1 ? 'review' : 'reviews'})'
                                        : 'Verified Member',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF7B40B5),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Action Buttons (Edit Profile if Self, Message/Contact if Viewing Another User)
                    if (_isSelf) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
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
                          ),
                          if (!isVerified) _buildVerifyButton(),
                        ],
                      ),
                      if (!isVerified) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0077B6).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF0077B6).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0077B6).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.verified_user_outlined,
                                  color: Color(0xFF0077B6),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Verify Your Identity',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF0077B6),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Complete instant ID & liveness verification via Didit to unlock your Verified badge.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isVerifying ? null : _handleStartVerification,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0077B6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                child: _isVerifying
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Verify',
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
                    ] else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _handleDirectChat(nameStr),
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

                    // Personal QR Code Section
                    PersonalQrCodeCard(
                      userId: _targetUserId,
                      userName: nameStr,
                      userEmail: (userData['email'] as String?) ?? '',
                      isSelf: _isSelf,
                    ),

                    const SizedBox(height: 16),

                    // Appraiser Portal / Application Section
                    if (_isSelf) ...[
                      // 1. Approved / Verified Appraiser
                      if (userData['isAppraiser'] == true &&
                          userData['businessVerificationStatus'] == 'approved') ...[
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
                                          'Lic / TIN #: ${userData['licenseNumber'] ?? 'APP-2026-REG'} • Verified',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                      ]
                      // 2. Pending Verification
                      else if (userData['businessVerificationStatus'] == 'pending') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber.shade400, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade900, size: 26),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Verification Under Review',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber.shade900),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${userData['businessName'] ?? 'Business'} • TIN: ${userData['licenseNumber'] ?? 'Pending'}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade200,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Pending Admin',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Your BIR permits and registration papers are currently being manually reviewed by our admin team. You will be notified once verified.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openBusinessRegistration(context, userData),
                                  icon: const Icon(Icons.edit_document, size: 16),
                                  label: const Text('View / Update Submitted Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.amber.shade900,
                                    side: BorderSide(color: Colors.amber.shade700),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                      // 3. Rejected Verification
                      else if (userData['businessVerificationStatus'] == 'rejected') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.shade300, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 26),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Application Rejected',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.redAccent),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Action required to verify your business credentials',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade100),
                                ),
                                child: Text(
                                  'Reason from Admin: "${userData['businessRejectionReason'] ?? 'Document requirements not met.'}"',
                                  style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontStyle: FontStyle.italic),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _openBusinessRegistration(context, userData),
                                  icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                                  label: const Text('Resubmit BIR Permits & Update Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                      // 4. Not Registered Yet
                      else ...[
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
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B40B5).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.business_center, color: Color(0xFF7B40B5), size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Apply as an Appraiser',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF7B40B5)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Submit credentials & documents to become a verified appraiser',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _openBusinessRegistration(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7B40B5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Apply as an Appraiser',
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader(
                          'Reviews & Ratings',
                          Icons.rate_review_outlined,
                        ),
                        if (!_isSelf)
                          ElevatedButton.icon(
                            onPressed: () => _openReviewDialog(context, nameStr),
                            icon: const Icon(Icons.star_rounded, size: 16),
                            label: const Text('Leave Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B40B5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                      ],
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
            final docId = docs[index].id;
            final review = docs[index].data() as Map<String, dynamic>;
            final ratingVal = (review['rating'] as num?)?.toDouble() ?? 5.0;
            final comment = review['comment'] ?? review['reviewText'] ?? 'Great experience!';
            final reviewerName = review['reviewerName'] ?? 'Verified Borrower';
            final reviewerPhoto = review['reviewerPhotoUrl'] as String?;
            final itemTitle = review['itemTitle'] as String?;
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            final isMyReview = currentUid != null && review['reviewerId'] == currentUid;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEFE8FA),
                  backgroundImage: isValidImageUrl(reviewerPhoto)
                      ? NetworkImage(reviewerPhoto!)
                      : null,
                  child: !isValidImageUrl(reviewerPhoto)
                      ? Text(
                          reviewerName.isNotEmpty ? reviewerName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Color(0xFF7B40B5), fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    ...List.generate(5, (starIdx) {
                      return Icon(
                        starIdx < ratingVal.floor() ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 16,
                        color: Colors.amber[700],
                      );
                    }),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reviewerName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (itemTitle != null && itemTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Item: "$itemTitle"',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7B40B5), fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(comment, style: const TextStyle(fontSize: 12)),
                  ],
                ),
                trailing: isMyReview
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        tooltip: 'Delete your review',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Review'),
                              content: const Text('Are you sure you want to delete your review? The ratings will automatically update.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await ReviewService().deleteReview(
                              reviewId: docId,
                              revieweeId: uid,
                              itemId: review['itemId'],
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Review deleted and ratings recalculated.')),
                              );
                            }
                          }
                        },
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
