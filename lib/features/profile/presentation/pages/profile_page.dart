import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/appraisal/presentation/pages/appraisal_dashboard.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/admin/presentation/pages/admin_dashboard_screen.dart';
import 'package:lendly/features/business/presentation/pages/register_business_screen.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/profile/presentation/pages/edit_profile.dart';
import 'package:lendly/features/profile/presentation/widgets/review_dialog.dart';
import 'package:lendly/core/services/review_service.dart';

class UserProfilePage extends StatefulWidget {
  final String? userId; // If null, displays current logged-in user's profile

  const UserProfilePage({super.key, this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String get _targetUserId {
    return widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  bool get _isSelf {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return widget.userId == null || widget.userId == currentUid;
  }

  Future<void> _handleDirectChat(BuildContext context, String targetName) async {
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: $e')),
        );
      }
    }
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

  Future<void> _toggleAdminMode(bool currentIsAdmin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newStatus = !currentIsAdmin;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isAdmin': newStatus,
      'isAppraiser': newStatus,
      'isBusiness': newStatus,
      'businessVerificationStatus': newStatus ? 'approved' : 'none',
      'businessName': newStatus ? 'Lendly Official Appraisal & Verification' : '',
      'licenseNumber': newStatus ? 'BIR-PRC-APPRAISER-001' : '',
      'specialization': newStatus ? 'General Equipment, Electronics, Cameras & Tools' : '',
      'accountType': newStatus ? 'appraiser' : 'standard',
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? '👑 Admin & Appraiser privileges enabled!' : 'Admin privileges disabled.'),
          backgroundColor: const Color(0xFF7B40B5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _isSelf ? 'My Profile' : 'User Profile',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_isSelf) ...[
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF7B40B5)),
              tooltip: 'Admin Verification Dashboard',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                );
              },
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_targetUserId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5))),
                  );
                }

                Map<String, dynamic> userData = {};
                if (snapshot.hasData && snapshot.data!.exists) {
                  userData = snapshot.data!.data() as Map<String, dynamic>;
                }

                final displayName = userData['username'] ??
                    '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
                final nameStr = displayName.isNotEmpty ? displayName : 'Lendly User';
                final location = LocationHelper.formatLocationDisplay(userData['location']);
                final phone = userData['phone'] ?? '';
                final profilePictureUrl = userData['photoURL'] ?? userData['profilePictureUrl'];
                final imageUrl = profilePictureUrl is String ? profilePictureUrl : '';

                return Column(
                  children: [
                    // Profile Header Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 52,
                                backgroundColor: const Color(0xFFEFE8FA),
                                backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                                child: imageUrl.isEmpty
                                    ? const Icon(Icons.person, size: 55, color: Color(0xFF7B40B5))
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
                                  child: const Icon(Icons.check, size: 14, color: Colors.white),
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
                              const Icon(Icons.location_on, size: 14, color: Color(0xFF7B40B5)),
                              const SizedBox(width: 4),
                              Text(
                                location,
                                style: TextStyle(color: Colors.grey[700], fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (userData['isAdmin'] == true) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  margin: const EdgeInsets.only(right: 8),
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
                              ],
                              if (userData['isAppraiser'] == true ||
                                  userData['businessVerificationStatus'] == 'approved' ||
                                  userData['isAdmin'] == true) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  margin: const EdgeInsets.only(right: 8),
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
                              ],
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
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _handleDirectChat(context, nameStr),
                                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                                  label: const Text('Send Message'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7B40B5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                                      side: const BorderSide(color: Color(0xFF7B40B5)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Appraiser Portal / Business Registration Section
                    if (_isSelf) ...[
                      // Admin quick-access card if user has admin privileges
                      if (userData['isAdmin'] == true) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2D1457), Color(0xFF4A154B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withValues(alpha: 0.2),
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
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.admin_panel_settings, color: Colors.amber, size: 22),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Administrator Controls',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        Text(
                                          'Review & manually verify submitted BIR permits & documents',
                                          style: TextStyle(color: Colors.white70, fontSize: 11),
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
                                      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                                    );
                                  },
                                  icon: const Icon(Icons.verified_user, color: Color(0xFF2D1457), size: 18),
                                  label: const Text(
                                    'Open Admin Verification Dashboard',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D1457)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 1. Approved / Verified Appraiser (Admins are also certified appraisers)
                      if (userData['isAppraiser'] == true ||
                          userData['businessVerificationStatus'] == 'approved' ||
                          userData['isAdmin'] == true) ...[
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
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.3),
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
                                  const Icon(Icons.verified, color: Colors.amber, size: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userData['businessName'] is String && (userData['businessName'] as String).isNotEmpty
                                              ? userData['businessName']
                                              : 'Professional Appraisal Business',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                                      MaterialPageRoute(builder: (_) => const AppraisalDashboard()),
                                    );
                                  },
                                  icon: const Icon(Icons.assessment_rounded, color: Color(0xFF7B40B5)),
                                  label: const Text(
                                    'Open Professional Appraisal Portal',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                            color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
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
                                      'Register as Business / Appraiser',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF7B40B5)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Submit BIR permits & registration papers for verified badge',
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Test helper toggle for developer/tester
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _toggleAdminMode(userData['isAdmin'] == true),
                          icon: Icon(
                            userData['isAdmin'] == true ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          label: Text(
                            userData['isAdmin'] == true ? 'Admin Mode (Active)' : 'Enable Admin Mode',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ),
                      ),
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
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
            if (item['imageUrls'] is List && (item['imageUrls'] as List).isNotEmpty) {
              imgs = List<String>.from(item['imageUrls']);
            } else if (item['imageUrl'] is String && (item['imageUrl'] as String).isNotEmpty) {
              imgs = [item['imageUrl']];
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                title: Text(itemTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(itemDesc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  itemPrice,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(itemData: item, itemId: doc.id),
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
          return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEFE8FA),
                  backgroundImage: (reviewerPhoto != null && reviewerPhoto.isNotEmpty)
                      ? NetworkImage(reviewerPhoto)
                      : null,
                  child: (reviewerPhoto == null || reviewerPhoto.isEmpty)
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
