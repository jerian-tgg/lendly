import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/core/services/trust_score_service.dart';

void main() {
  group('Bayesian Adjusted Rating Tests (Factor A - 60%)', () {
    test('Zero reviews defaults to prior mean (4.0 / 5.0 = 80%)', () {
      final bayesian = TrustScoreService.bayesianRating(
        totalRatings: 0,
        averageRating: 0.0,
      );
      expect(bayesian, closeTo(4.0, 0.001));
    });

    test('Single 5.0 review pulls score gently above prior mean without artificial spike', () {
      // (5 * 4.0 + 1 * 5.0) / 6 = 25 / 6 ≈ 4.167
      final bayesian = TrustScoreService.bayesianRating(
        totalRatings: 1,
        averageRating: 5.0,
      );
      expect(bayesian, closeTo(4.167, 0.01));
    });

    test('Single 1.0 review does not destroy score completely due to prior weight', () {
      // (5 * 4.0 + 1 * 1.0) / 6 = 21 / 6 = 3.5
      final bayesian = TrustScoreService.bayesianRating(
        totalRatings: 1,
        averageRating: 1.0,
      );
      expect(bayesian, closeTo(3.5, 0.01));
    });

    test('Large number of ratings converges on actual user average', () {
      // (5 * 4.0 + 50 * 4.9) / 55 = (20 + 245) / 55 = 265 / 55 ≈ 4.818
      final bayesian = TrustScoreService.bayesianRating(
        totalRatings: 50,
        averageRating: 4.9,
      );
      expect(bayesian, closeTo(4.818, 0.01));
    });
  });

  group('Full Trust Score Computation Tests', () {
    test('New user with 0 ratings and 0 transactions gets fair starting score (78)', () {
      // Bayesian: 4.0 / 5.0 = 80% * 0.60 = 48.0
      // Reliability: 100% * 0.30 = 30.0
      // Experience: 0% * 0.10 = 0.0
      // Total: 78
      final score = TrustScoreService.computeTrustScore(
        totalRatings: 0,
        averageRating: 0.0,
        completedTransactions: 0,
        eligibleTransactions: 0,
      );
      expect(score, 78);
    });

    test('High-reputation seasoned member reaches top tier (>= 90)', () {
      // 20 completed of 20 eligible (100% reliability, 100% experience)
      // 20 ratings averaging 4.9 -> Bayesian ≈ 4.72 -> 94.4%
      // 94.4% * 0.60 (56.64) + 100% * 0.30 (30.0) + 100% * 0.10 (10.0) = 96.64 -> 97
      final score = TrustScoreService.computeTrustScore(
        totalRatings: 20,
        averageRating: 4.9,
        completedTransactions: 20,
        eligibleTransactions: 20,
      );
      expect(score, greaterThanOrEqualTo(95));
      expect(score, lessThanOrEqualTo(100));
      expect(TrustScoreService.scoreLabel(score), 'Excellent');
    });

    test('Frequent cancellations or denied transactions reduce score', () {
      // 5 completed out of 15 eligible = 33.33% reliability
      // 5 ratings averaging 3.0 -> Bayesian: (20 + 15)/10 = 3.5 -> 70% * 0.60 = 42.0
      // Reliability: 33.33% * 0.30 = 10.0
      // Experience: (5/20) * 10 = 2.5
      // Total: 42.0 + 10.0 + 2.5 = 54.5 -> 55 (Fair)
      final score = TrustScoreService.computeTrustScore(
        totalRatings: 5,
        averageRating: 3.0,
        completedTransactions: 5,
        eligibleTransactions: 15,
      );
      expect(score, closeTo(55, 1));
      expect(TrustScoreService.scoreLabel(score), 'Fair');
    });

    test('Experience score caps at 20 transactions and does not exceed 100', () {
      final scoreWith20 = TrustScoreService.computeTrustScore(
        totalRatings: 30,
        averageRating: 5.0,
        completedTransactions: 20,
        eligibleTransactions: 20,
      );
      final scoreWith100 = TrustScoreService.computeTrustScore(
        totalRatings: 30,
        averageRating: 5.0,
        completedTransactions: 100,
        eligibleTransactions: 100,
      );
      // Both should have identical 100% experience bonus
      expect(scoreWith20, scoreWith100);
      expect(scoreWith100, lessThanOrEqualTo(100));
    });

    test('Score stays clamped within [0, 100] bounds under extreme inputs', () {
      final minScore = TrustScoreService.computeTrustScore(
        totalRatings: 100,
        averageRating: 1.0,
        completedTransactions: 0,
        eligibleTransactions: 100,
      );
      expect(minScore, greaterThanOrEqualTo(0));

      final maxScore = TrustScoreService.computeTrustScore(
        totalRatings: 100,
        averageRating: 5.0,
        completedTransactions: 100,
        eligibleTransactions: 100,
      );
      expect(maxScore, lessThanOrEqualTo(100));
    });
  });

  group('Trust Score Tier Labels Tests', () {
    test('Correctly maps score boundaries to tiers', () {
      expect(TrustScoreService.scoreLabel(null), 'New User');
      expect(TrustScoreService.scoreLabel(95), 'Excellent');
      expect(TrustScoreService.scoreLabel(90), 'Excellent');
      expect(TrustScoreService.scoreLabel(89), 'Very Good');
      expect(TrustScoreService.scoreLabel(75), 'Very Good');
      expect(TrustScoreService.scoreLabel(74), 'Good');
      expect(TrustScoreService.scoreLabel(60), 'Good');
      expect(TrustScoreService.scoreLabel(59), 'Fair');
      expect(TrustScoreService.scoreLabel(40), 'Fair');
      expect(TrustScoreService.scoreLabel(39), 'Developing');
      expect(TrustScoreService.scoreLabel(0), 'Developing');
    });
  });
}
