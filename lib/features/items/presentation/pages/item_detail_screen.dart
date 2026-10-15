import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lendly/core/utils/convo_utils.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/profile/presentation/pages/profile_page.dart';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final String itemId;

  const ItemDetailScreen({
    super.key,
    required this.itemData,
    required this.itemId,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  int _currentImageIndex = 0;

  Future<void> _pickDates(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF7B40B5),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _handleMessageOwner(BuildContext context, String ownerId, String ownerName) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to contact the owner.')),
      );
      return;
    }

    try {
      final convoId = await createOrGetConversation(
        currentUserId: currentUserId,
        otherUserId: ownerId,
        itemId: widget.itemId,
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              convoId: convoId,
              currentUserId: currentUserId,
              otherUserId: ownerId,
              otherUserName: ownerName,
              itemId: widget.itemId,
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

  void _openOwnerProfile(BuildContext context, String ownerId) {
    if (ownerId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(userId: ownerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: widget.itemId.isNotEmpty
          ? FirebaseFirestore.instance.collection('items').doc(widget.itemId).snapshots()
          : null,
      builder: (context, snapshot) {
        final itemData = Map<String, dynamic>.from(widget.itemData);
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final liveData = snapshot.data!.data() as Map<String, dynamic>?;
          if (liveData != null) {
            itemData.addAll(liveData);
          }
        }

        final title = itemData['name'] ?? itemData['title'] ?? 'Item Details';
        final description = itemData['description'] ?? 'No description provided.';
        final category = itemData['category'] ?? 'General';
        final condition = itemData['condition'] ?? 'Like New';
        final priceNum = (itemData['price'] as num?)?.toDouble() ?? 0.0;
        final priceStr = '₱${priceNum.toStringAsFixed(0)}';

        // Appraisal Status and Appraiser-Rated Condition (monetary appraisal value intentionally omitted)
        final rawStatus = (itemData['appraisalStatus'] as String?)?.toLowerCase();
        final isCertified = rawStatus == 'certified' || rawStatus == 'approved' || itemData['isAppraised'] == true;
        final isUnderReview = !isCertified && (rawStatus == 'in_review' || rawStatus == 'pending' || itemData['appraisalRequested'] == true);
        final isRejected = !isCertified && rawStatus == 'rejected';
        final appraiserCondition = (itemData['conditionGrade'] as String?) ??
            (itemData['appraisedCondition'] as String?);

        final rating = (itemData['rating'] as num?)?.toDouble() ?? 4.8;
        final isAvailable = itemData['isAvailable'] ?? true;
        final ownerId = itemData['ownerId'] as String? ?? '';
        final ownerName = itemData['ownerName'] ?? 'Lender';
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
        final isOwner = ownerId == currentUserId;

        // Image list extraction
        List<String> imageUrls = [];
        if (itemData['imageUrls'] is List && (itemData['imageUrls'] as List).isNotEmpty) {
          imageUrls = List<String>.from(itemData['imageUrls']);
        } else if (itemData['imageUrl'] is String && (itemData['imageUrl'] as String).isNotEmpty) {
          imageUrls = [itemData['imageUrl']];
        }

        final totalDays = (_startDate != null && _endDate != null)
            ? _endDate!.difference(_startDate!).inDays + 1
            : 0;
        final totalPrice = totalDays * priceNum;

        return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Item Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item link copied to clipboard!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved to favorites!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Carousel Gallery
            Stack(
              children: [
                SizedBox(
                  height: 280,
                  width: double.infinity,
                  child: imageUrls.isNotEmpty
                      ? PageView.builder(
                          itemCount: imageUrls.length,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemBuilder: (context, index) {
                            return Image.network(
                              imageUrls[index],
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_outlined, size: 60, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('No Images Provided', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                ),

                // Availability Badge
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isAvailable ? Colors.green.withValues(alpha: 0.9) : Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isAvailable ? 'AVAILABLE FOR BORROW' : 'CURRENTLY BORROWED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Page Indicator Dots
                if (imageUrls.length > 1)
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentImageIndex + 1} / ${imageUrls.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Category Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF90E0F3).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007A9B),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Rating Row & Location
                  Row(
                    children: [
                      ...List.generate(5, (index) {
                        return Icon(
                          index < rating.floor() ? Icons.star : Icons.star_half,
                          size: 18,
                          color: Colors.amber[700],
                        );
                      }),
                      const SizedBox(width: 6),
                      Text(
                        '$rating',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        ' (12 reviews)',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Color(0xFF7B40B5)),
                          const SizedBox(width: 2),
                          Text(
                            LocationHelper.formatLocationWithDistance(
                              locationData: itemData['location'],
                              distanceKm: (itemData['distanceKm'] as num?)?.toDouble(),
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // PRICE & APPRAISAL STATUS CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Price Section
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.sell_outlined, size: 15, color: Color(0xFF7B40B5)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Rental Price:',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    priceStr,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF7B40B5),
                                    ),
                                  ),
                                  Text(
                                    ' / day',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        Container(width: 1, height: 48, color: Colors.grey[200]),
                        const SizedBox(width: 14),

                        // Appraisal Status Section (Displaying status & rated condition, no appraisal value)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isCertified
                                        ? Icons.verified
                                        : isUnderReview
                                            ? Icons.hourglass_top_rounded
                                            : isRejected
                                                ? Icons.error_outline_rounded
                                                : Icons.shield_outlined,
                                    size: 15,
                                    color: isCertified
                                        ? const Color(0xFF059669)
                                        : isUnderReview
                                            ? const Color(0xFFD97706)
                                            : isRejected
                                                ? Colors.red[700]
                                                : const Color(0xFF6B7280),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Appraisal Status:',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCertified
                                      ? const Color(0xFFECFDF5)
                                      : isUnderReview
                                          ? const Color(0xFFFFFBEB)
                                          : isRejected
                                              ? const Color(0xFFFEF2F2)
                                              : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isCertified
                                        ? const Color(0xFFA7F3D0)
                                        : isUnderReview
                                            ? const Color(0xFFFDE68A)
                                            : isRejected
                                                ? const Color(0xFFFECACA)
                                                : const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Text(
                                  isCertified
                                      ? 'Certified Appraised'
                                      : isUnderReview
                                          ? 'Being Checked'
                                          : isRejected
                                              ? 'Appraisal Rejected'
                                              : 'Self-Reported',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCertified
                                        ? const Color(0xFF047857)
                                        : isUnderReview
                                            ? const Color(0xFFB45309)
                                            : isRejected
                                                ? const Color(0xFFB91C1C)
                                                : const Color(0xFF4B5563),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isCertified
                                    ? 'Rated: ${appraiserCondition ?? condition}'
                                    : isUnderReview
                                        ? 'Review in progress'
                                        : isRejected
                                            ? 'Needs revision'
                                            : 'Lender: $condition',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // APPRAISAL & CONDITION DETAILS SECTION
                  if (isCertified) ...[
                    // State 1: Officially Certified by Appraiser
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFFFBEB),
                            Colors.amber.shade50,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade400, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
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
                                decoration: const BoxDecoration(
                                  color: Colors.amber,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.verified, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Certified Professional Appraisal',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Cert ID: ${itemData['appraisalCertificateId'] ?? 'CERT-APPRAISED'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'VERIFIED',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              const Icon(Icons.business, size: 14, color: Color(0xFF7B40B5)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Appraiser: ${itemData['certifiedByBusinessName'] ?? 'Licensed Professional Appraiser'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Lic: ${itemData['certifiedByLicense'] ?? 'APP-REG'}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Prominent Appraiser-Rated Condition Badge
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.stars_rounded, size: 20, color: Colors.amber),
                                const SizedBox(width: 8),
                                const Text(
                                  'Appraiser Rated Condition:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    appraiserCondition ?? condition,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (itemData['isSerialVerified'] == true || itemData['isCleanWorking'] == true) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (itemData['isSerialVerified'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text('Serial # Verified', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                if (itemData['isCleanWorking'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text('Clean & Fully Functional', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (itemData['appraiserNotes'] != null &&
                              (itemData['appraiserNotes'] as String).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '"${itemData['appraiserNotes']}"',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else if (isUnderReview) ...[
                    // State 2: Currently Being Checked by Appraiser
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade300, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
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
                                  color: Colors.amber.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.manage_search_rounded, color: Color(0xFFD97706), size: 22),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Being Checked by Appraiser',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Professional inspection in progress',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFCD34D)),
                                ),
                                child: const Text(
                                  'UNDER REVIEW',
                                  style: TextStyle(
                                    color: Color(0xFF92400E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Text(
                            'An accredited Lendly appraiser is currently inspecting this item to verify its specifications and rate its physical condition.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFFD97706)),
                                SizedBox(width: 6),
                                Text(
                                  'Appraiser Rated Condition: ',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                ),
                                Expanded(
                                  child: Text(
                                    'Assessment in Progress',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 13, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                'Lender declared condition: "$condition"',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          if (isOwner) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF7B40B5)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your appraisal request is queued. An appraiser will rate your item shortly.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF7B40B5), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    // State 3: Standard Listing (Not Appraised / Self-Reported)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFE8FA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.stars_rounded, color: Color(0xFF7B40B5), size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Item Condition: ',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7B40B5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            condition,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Self-reported condition by lender (Unappraised)',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (isOwner) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  if (widget.itemId.isNotEmpty) {
                                    await FirebaseFirestore.instance
                                        .collection('items')
                                        .doc(widget.itemId)
                                        .update({
                                          'appraisalRequested': true,
                                          'appraisalStatus': 'pending',
                                        });
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Appraisal requested! Professional appraisers will review your item.'),
                                        backgroundColor: Color(0xFF7B40B5),
                                      ),
                                    );
                                    setState(() {
                                      widget.itemData['appraisalRequested'] = true;
                                      widget.itemData['appraisalStatus'] = 'pending';
                                    });
                                  }
                                },
                                icon: const Icon(Icons.verified_outlined, size: 16),
                                label: const Text(
                                  'Request Official Professional Appraisal',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF7B40B5),
                                  side: const BorderSide(color: Color(0xFF7B40B5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // DESCRIPTION SECTION
                  const Row(
                    children: [
                      Icon(Icons.notes_rounded, color: Color(0xFF7B40B5), size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Description',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Owner Information Card (Tapping opens Lender Profile!)
                  InkWell(
                    onTap: () => _openOwnerProfile(context, ownerId),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          FutureBuilder<DocumentSnapshot>(
                            future: ownerId.isNotEmpty
                                ? FirebaseFirestore.instance.collection('users').doc(ownerId).get()
                                : null,
                            builder: (context, snapshot) {
                              String? photoUrl;
                              if (snapshot.hasData && snapshot.data!.exists) {
                                final uData = snapshot.data!.data() as Map<String, dynamic>?;
                                photoUrl = uData?['photoURL'] ?? uData?['profilePictureUrl'];
                              }
                              return CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFFEFE8FA),
                                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl == null || photoUrl.isEmpty)
                                    ? const Icon(Icons.person, color: Color(0xFF7B40B5))
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      ownerName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.verified, size: 12, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'View Lender Profile • 100% Response',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!isOwner)
                            OutlinedButton.icon(
                              onPressed: () => _handleMessageOwner(context, ownerId, ownerName),
                              icon: const Icon(Icons.chat_bubble_outline, size: 16),
                              label: const Text('Chat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF7B40B5),
                                side: const BorderSide(color: Color(0xFF7B40B5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // BORROW DATE PICKER & ACTION
                  if (!isOwner) ...[
                    const Text(
                      'Select Borrow Duration',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _pickDates(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (_startDate != null && _endDate != null)
                                ? const Color(0xFF7B40B5)
                                : Colors.grey.shade300,
                            width: (_startDate != null && _endDate != null) ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month, color: Color(0xFF7B40B5)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _startDate != null && _endDate != null
                                        ? '${DateFormat('MMM d, yyyy').format(_startDate!)} — ${DateFormat('MMM d, yyyy').format(_endDate!)}'
                                        : 'Select Borrow Dates',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _startDate != null ? Colors.black87 : Colors.grey[700],
                                    ),
                                  ),
                                  if (totalDays > 0)
                                    Text(
                                      '$totalDays day(s) × $priceStr = ₱${totalPrice.toStringAsFixed(0)} total',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF7B40B5),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _handleMessageOwner(context, ownerId, ownerName),
                        icon: const Icon(Icons.message_rounded),
                        label: Text(
                          _startDate != null && _endDate != null
                              ? 'Request to Borrow (₱${totalPrice.toStringAsFixed(0)})'
                              : 'Message Owner',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B40B5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // SIMILAR ITEMS IN THIS CATEGORY
                  const Text(
                    'Similar items in this category',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('items')
                        .where('category', isEqualTo: itemData['category'])
                        .where(FieldPath.documentId, isNotEqualTo: widget.itemId)
                        .limit(4)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
                          ),
                        );
                      }

                      final items = snapshot.data?.docs ?? [];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No other items currently listed under $category.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        );
                      }

                      return Column(
                        children: items.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final itemTitle = data['name'] ?? data['title'] ?? 'Unnamed Item';
                          final itemDesc = data['description'] ?? '';
                          final itemPrice = '₱${data['price'] ?? 0}/day';

                          List<String> imgs = [];
                          if (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty) {
                            imgs = List<String>.from(data['imageUrls']);
                          } else if (data['imageUrl'] is String && (data['imageUrl'] as String).isNotEmpty) {
                            imgs = [data['imageUrl']];
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imgs.isNotEmpty
                                    ? Image.network(
                                        imgs[0],
                                        width: 54,
                                        height: 54,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 54,
                                          height: 54,
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.image_not_supported, size: 24),
                                        ),
                                      )
                                    : Container(
                                        width: 54,
                                        height: 54,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.image_not_supported, size: 24),
                                      ),
                              ),
                              title: Text(
                                itemTitle,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Text(
                                itemDesc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              trailing: Text(
                                itemPrice,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF7B40B5),
                                  fontSize: 13,
                                ),
                              ),
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ItemDetailScreen(itemData: data, itemId: doc.id),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        );
      },
    );
  }
}
