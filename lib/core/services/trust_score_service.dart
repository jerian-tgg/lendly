import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Severity tiers for confirmed violation reports, mapping each tier
/// to its automatic trust score deduction.
enum ReportSeverity {
  low('Low', 10),
  moderate('Moderate', 15),
  high('High', 20),
  critical('Critical', 25);

  final String label;
  final int penaltyPoints;

  const ReportSeverity(this.label, this.penaltyPoints);
}

/// Client-side service for reading trust score data from Firestore
/// and optionally triggering a server-side recalculation via Cloud Functions.
///
/// Trust scores are computed entirely server-side. This service only
/// reads pre-computed values and provides helper methods for display.
class TrustScoreService {
  /// Default fallback trust score deduction when a report reason is unmapped.
  static const int confirmedReportPenalty = 15;

  /// Severity mapping for standard report reasons submitted via ReportScreen.
  static const Map<String, ReportSeverity> reportReasonSeverities = {
    'fraudulent listing': ReportSeverity.critical,
    'counterfeit item': ReportSeverity.critical,
    'harassment or abuse': ReportSeverity.high,
    'damaged/misrepresented item': ReportSeverity.moderate,
    'no-show / failed transaction': ReportSeverity.moderate,
    'inappropriate content': ReportSeverity.low,
    'other': ReportSeverity.low,
  };

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

  /// Computes the full trust score from component values, subtracting any
  /// confirmed moderation [penaltyPoints].
  /// Returns a value between 0 and 100 (inclusive), rounded.
  static int computeTrustScore({
    required int totalRatings,
    required double averageRating,
    required int completedTransactions,
    required int eligibleTransactions,
    int penaltyPoints = 0,
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

    // Weighted sum minus any confirmed moderation penalty
    final sanitizedPenalty = penaltyPoints < 0 ? 0 : penaltyPoints;
    final raw = (bayesianPct * 0.60) +
        (reliabilityPct * 0.30) +
        (experienceScore * 0.10) -
        sanitizedPenalty;

    return raw.round().clamp(0, 100);
  }

  /// Resolves a user's current trust score from their Firestore user data,
  /// falling back to [computeTrustScore] if `trustScore` is not yet stored.
  static int resolveEffectiveTrustScore(Map<String, dynamic>? userData) {
    if (userData == null) {
      return computeTrustScore(
        totalRatings: 0,
        averageRating: 0.0,
        completedTransactions: 0,
        eligibleTransactions: 0,
      );
    }

    final stored = userData['trustScore'];
    if (stored is num) {
      return stored.toInt().clamp(0, 100);
    }

    final stats =
        (userData['trustScoreStats'] as Map?)?.cast<String, dynamic>();
    final totalRatings = (userData['reviewCount'] as num?)?.toInt() ?? 0;
    final averageRating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
    final completed =
        (stats?['completedTransactions'] as num?)?.toInt() ?? 0;
    final eligible =
        (stats?['totalEligibleTransactions'] as num?)?.toInt() ?? 0;
    final penalty = (userData['trustScorePenalty'] as num?)?.toInt() ?? 0;

    return computeTrustScore(
      totalRatings: totalRatings,
      averageRating: averageRating,
      completedTransactions: completed,
      eligibleTransactions: eligible,
      penaltyPoints: penalty,
    );
  }

  /// Computes the penalized trust score after subtracting [penaltyPoints],
  /// clamped between 0 and 100.
  static int applyPenalty(
    int currentScore, {
    int penaltyPoints = confirmedReportPenalty,
  }) {
    final sanitizedPenalty = penaltyPoints < 0 ? 0 : penaltyPoints;
    return (currentScore - sanitizedPenalty).clamp(0, 100);
  }

  /// Resolves the [ReportSeverity] tier for a given report [reason].
  /// Falls back to [ReportSeverity.moderate] when the reason is null or unmapped.
  static ReportSeverity severityForReason(String? reason) {
    final normalized = reason?.trim().toLowerCase() ?? '';
    return reportReasonSeverities[normalized] ?? ReportSeverity.moderate;
  }

  /// Returns the automatic trust score penalty (in points) for a report [reason].
  static int penaltyForReason(String? reason) {
    return severityForReason(reason).penaltyPoints;
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
