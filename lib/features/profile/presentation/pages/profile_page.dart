import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/services/didit/didit_verification_service.dart';
import 'package:lendly/features/profile/data/datasources/firebase_user_service.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> with WidgetsBindingObserver {
  final FirebaseUserService _userService = FirebaseUserService();
  final DiditVerificationService _diditService = DiditVerificationService();

  bool? _localIsVerified;
  bool _isVerifying = false;
  String? _pendingSessionId;
  Timer? _statusPollTimer;

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
                  child: Text('Identity verified successfully! Verified badge granted.'),
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
            content: Text('Your verification has been submitted and is in review.'),
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
            content: Text('Verification was not approved. Please try again with a valid ID.'),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF81C784),
          width: 1.2,
        ),
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
          Icon(
            Icons.verified,
            color: Color(0xFF2E7D32),
            size: 16,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _userService.getUserProfileStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No user data found.'));
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>;
                final displayName = userData['username'] ?? 'User';
                final location = userData['location'] is String
                    ? userData['location']
                    : 'Location not available';
                final profilePictureUrl = userData['photoURL'] ?? userData['profilePictureUrl'];
                final imageUrl = profilePictureUrl is String ? profilePictureUrl : '';

                final bool firestoreIsVerified = userData['isVerified'] == true;
                final bool isVerified = _localIsVerified ?? firestoreIsVerified;

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      // Header Row with Title and Upper-Right Corner action/badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'User Profile',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Upper-Right Corner: Verify Button or Verified Badge
                          isVerified
                              ? _buildVerifiedBadge()
                              : _buildVerifyButton(),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty
                                ? const Icon(Icons.person, size: 50)
                                : null,
                          ),
                          if (isVerified)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified,
                                color: Color(0xFF0077B6),
                                size: 24,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: Color(0xFF0077B6),
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        location,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EditProfilePage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 144, 224, 243),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Items Listed'),
                      _buildItemsList(),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Reviews Received'),
                      _buildReviews(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _userService.getUserItems(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final items = snapshot.data!.docs;
          if (items.isEmpty) {
            return const Text('No items listed.');
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text(item['title'] ?? ''),
                subtitle: Text(item['description'] ?? ''),
              );
            },
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }

  Widget _buildReviews() {
    return StreamBuilder<QuerySnapshot>(
      stream: _userService.getUserReviews(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final reviews = snapshot.data!.docs;
          if (reviews.isEmpty) {
            return const Text('No reviews received.');
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text('⭐ ${review['rating'] ?? '0'}'),
                subtitle: const Text('Review'),
                trailing: Text(review['reviewerName'] ?? ''),
              );
            },
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }
}
