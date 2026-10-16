import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Submit a review for an item or a user.
  /// Automatically re-calculates the average rating and review count in Firestore.
  Future<void> submitReview({
    required String revieweeId,
    String? itemId,
    String? itemTitle,
    required double rating,
    required String comment,
    String? reviewType,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please sign in to submit a review.');
    }

    if (currentUser.uid == revieweeId) {
      throw Exception('You cannot review your own listing or profile.');
    }

    final double validRating = rating.clamp(1.0, 5.0);

    // Fetch reviewer's current display info
    String reviewerName = currentUser.displayName ?? 'Verified Borrower';
    String? reviewerPhoto = currentUser.photoURL;

    try {
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (userDoc.exists) {
        final uData = userDoc.data() ?? {};
        final username = (uData['username'] as String?)?.trim();
        final fullName = '${uData['firstName'] ?? ''} ${uData['lastName'] ?? ''}'.trim();

        if (username != null && username.isNotEmpty) {
          reviewerName = username;
        } else if (fullName.isNotEmpty) {
          reviewerName = fullName;
        }

        reviewerPhoto = uData['photoURL'] ?? uData['profilePictureUrl'] ?? reviewerPhoto;
      }
    } catch (_) {
      // Fallback to auth display name if user doc fetch fails
    }

    // Check if an existing review from this user on this item exists to update, or create a new one
    Query query = _firestore.collection('reviews')
        .where('reviewerId', isEqualTo: currentUser.uid);

    if (itemId != null && itemId.isNotEmpty) {
      query = query.where('itemId', isEqualTo: itemId);
    } else {
      query = query.where('revieweeId', isEqualTo: revieweeId).where('itemId', isNull: true);
    }

    final existingDocs = await query.limit(1).get();
    DocumentReference reviewRef;

    if (existingDocs.docs.isNotEmpty) {
      reviewRef = existingDocs.docs.first.reference;
    } else {
      reviewRef = _firestore.collection('reviews').doc();
    }

    final reviewData = {
      'reviewId': reviewRef.id,
      'revieweeId': revieweeId,
      'reviewerId': currentUser.uid,
      'reviewerName': reviewerName,
      'reviewerPhotoUrl': reviewerPhoto,
      'rating': validRating,
      'comment': comment.trim(),
      'itemId': itemId,
      'itemTitle': itemTitle,
      'type': reviewType ?? (itemId != null && itemId.isNotEmpty ? 'item' : 'user'),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existingDocs.docs.isEmpty) {
      reviewData['createdAt'] = FieldValue.serverTimestamp();
    }

    await reviewRef.set(reviewData, SetOptions(merge: true));

    // 1. Update item rating and count in Firestore
    if (itemId != null && itemId.isNotEmpty) {
      await recomputeItemRating(itemId);
    }

    // 2. Update user rating and count in Firestore
    if (revieweeId.isNotEmpty) {
      await recomputeUserRating(revieweeId);
    }
  }

  /// Delete a review and re-compute aggregates
  Future<void> deleteReview({
    required String reviewId,
    required String revieweeId,
    String? itemId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Please log in.');

    final doc = await _firestore.collection('reviews').doc(reviewId).get();
    if (!doc.exists) return;

    final data = doc.data() ?? {};
    if (data['reviewerId'] != currentUser.uid) {
      throw Exception('You can only delete your own reviews.');
    }

    await _firestore.collection('reviews').doc(reviewId).delete();

    if (itemId != null && itemId.isNotEmpty) {
      await recomputeItemRating(itemId);
    }
    if (revieweeId.isNotEmpty) {
      await recomputeUserRating(revieweeId);
    }
  }

  /// Re-computes and saves real average rating and reviewCount for an item in items/{itemId}
  Future<void> recomputeItemRating(String itemId) async {
    final snapshot = await _firestore
        .collection('reviews')
        .where('itemId', isEqualTo: itemId)
        .get();

    final docs = snapshot.docs;
    if (docs.isEmpty) {
      await _firestore.collection('items').doc(itemId).update({
        'rating': 0.0,
        'reviewCount': 0,
      });
      return;
    }

    final ratings = docs
        .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
        .where((r) => r > 0)
        .toList();

    final avg = calculateAverageRating(ratings);

    await _firestore.collection('items').doc(itemId).update({
      'rating': avg,
      'reviewCount': ratings.length,
    });
  }

  /// Re-computes and saves real average rating and reviewCount for a user in users/{userId}
  Future<void> recomputeUserRating(String userId) async {
    final snapshot = await _firestore
        .collection('reviews')
        .where('revieweeId', isEqualTo: userId)
        .get();

    final docs = snapshot.docs;
    if (docs.isEmpty) {
      await _firestore.collection('users').doc(userId).set({
        'rating': 0.0,
        'reviewCount': 0,
      }, SetOptions(merge: true));
      return;
    }

    final ratings = docs
        .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
        .where((r) => r > 0)
        .toList();

    final avg = calculateAverageRating(ratings);

    await _firestore.collection('users').doc(userId).set({
      'rating': avg,
      'reviewCount': ratings.length,
    }, SetOptions(merge: true));
  }

  /// Utility to calculate aggregate average rating rounded to 1 decimal place.
  static double calculateAverageRating(List<double> ratings) {
    if (ratings.isEmpty) return 0.0;
    final validRatings = ratings.where((r) => r > 0).toList();
    if (validRatings.isEmpty) return 0.0;
    final total = validRatings.reduce((a, b) => a + b);
    return double.parse((total / validRatings.length).toStringAsFixed(1));
  }

  /// Real-time stream of reviews for a specific item
  Stream<QuerySnapshot> getItemReviewsStream(String itemId) {
    return _firestore
        .collection('reviews')
        .where('itemId', isEqualTo: itemId)
        .snapshots();
  }

  /// Real-time stream of reviews received by a specific user
  Stream<QuerySnapshot> getUserReviewsStream(String userId) {
    return _firestore
        .collection('reviews')
        .where('revieweeId', isEqualTo: userId)
        .snapshots();
  }
}
