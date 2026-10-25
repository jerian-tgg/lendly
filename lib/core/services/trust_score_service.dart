import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Client-side service for reading trust score data from Firestore
/// and optionally triggering a server-side recalculation via Cloud Functions.
///
/// Trust scores are computed entirely server-side. This service only
/// reads pre-computed values and provides helper methods for display.
class TrustScoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Returns a real-time stream of the user's trust score data.
  /// The stream emits the full user document, from which callers
  /// can extract `trustScore` and `trustScoreStats`.
  Stream<DocumentSnapshot> getUserTrustScoreStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  /// Fetches the current trust score for a user as a one-shot read.
  /// Returns null if the score has not yet been calculated.
  Future<int?> getTrustScore(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    return (data['trustScore'] as num?)?.toInt();
  }

  /// Fetches the trust score statistics map for a user.
  Future<Map<String, dynamic>?> getTrustScoreStats(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    return data['trustScoreStats'] as Map<String, dynamic>?;
  }

  /// Triggers a server-side recalculation of the current user's trust score.
  /// Returns the newly computed score and stats.
  Future<Map<String, dynamic>?> recalculateTrustScore({String? userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    try {
      final callable = _functions.httpsCallable('recalculateTrustScore');
      final result = await callable.call(<String, dynamic>{
        'userId': ?userId,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      // If the Cloud Function is not yet deployed, fail gracefully
      return null;
    }
  }

  // ── Pure computation helpers (mirrors server logic for display/testing) ──

  /// Computes the Bayesian adjusted rating.
  /// C = 5 (prior weight), M = 4.0 (prior mean).
  static double bayesianRating({
    required int totalRatings,
    required double averageRating,
    int priorWeight = 5,
    double priorMean = 4.0,
  }) {
    return (priorWeight * priorMean + totalRatings * averageRating) /
        (priorWeight + totalRatings);
  }

  /// Computes the full trust score from component values.
  /// Returns a value between 0 and 100 (inclusive), rounded.
  static int computeTrustScore({
    required int totalRatings,
    required double averageRating,
    required int completedTransactions,
    required int eligibleTransactions,
  }) {
    // A. Bayesian Rating (60%)
    final bayesian = bayesianRating(
      totalRatings: totalRatings,
      averageRating: averageRating,
    );
    final bayesianPct = (bayesian / 5.0) * 100.0;

    // B. Reliability (30%)
    final reliabilityPct = eligibleTransactions > 0
        ? (completedTransactions / eligibleTransactions) * 100.0
        : 100.0;

    // C. Experience (10%)
    final experienceScore =
        (completedTransactions / 20.0).clamp(0.0, 1.0) * 100.0;

    // Weighted sum
    final raw = (bayesianPct * 0.60) +
        (reliabilityPct * 0.30) +
        (experienceScore * 0.10);

    return raw.round().clamp(0, 100);
  }

  /// Returns a human-readable label for the trust score.
  static String scoreLabel(int? score) {
    if (score == null) return 'New User';
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Very Good';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Developing';
  }
}
