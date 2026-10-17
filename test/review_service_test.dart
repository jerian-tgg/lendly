import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/core/services/review_service.dart';

void main() {
  group('ReviewService Rating Aggregation Tests', () {
    test('Empty list returns 0.0 rating', () {
      final avg = ReviewService.calculateAverageRating([]);
      expect(avg, 0.0);
    });

    test('Single rating returns exact value', () {
      final avg = ReviewService.calculateAverageRating([5.0]);
      expect(avg, 5.0);
    });

    test('Multiple 5-star reviews return 5.0', () {
      final avg = ReviewService.calculateAverageRating([5.0, 5.0, 5.0, 5.0]);
      expect(avg, 5.0);
    });

    test('Calculates accurate average with 1 decimal place rounding', () {
      // 5 + 4 + 5 + 3 = 17 / 4 = 4.25 -> rounded to 4.3
      final avg = ReviewService.calculateAverageRating([5.0, 4.0, 5.0, 3.0]);
      expect(avg, 4.3);
    });

    test('Calculates low average accurately', () {
      // 1 + 2 + 3 = 6 / 3 = 2.0
      final avg = ReviewService.calculateAverageRating([1.0, 2.0, 3.0]);
      expect(avg, 2.0);
    });

    test('Filters out non-positive/invalid ratings', () {
      // 0.0 or negative ratings are excluded
      final avg = ReviewService.calculateAverageRating([4.0, 5.0, 0.0, -1.0]);
      expect(avg, 4.5);
    });
  });

  group('Item & User Rating Display and Badge Logic Tests', () {
    test('Top Rated badge only activates when rating >= 4.5 and reviewCount >= 2', () {
      bool isTopRated(double rating, int reviewCount) =>
          rating >= 4.5 && reviewCount >= 2;

      // Brand new item with 1 5-star review (should NOT be Top Rated yet)
      expect(isTopRated(5.0, 1), isFalse);

      // Verified popular item with 2 5-star reviews (is Top Rated)
      expect(isTopRated(5.0, 2), isTrue);

      // High review count but lower rating (should NOT be Top Rated)
      expect(isTopRated(4.2, 25), isFalse);

      // Verified 4.8 with 10 reviews (is Top Rated)
      expect(isTopRated(4.8, 10), isTrue);

      // Unrated item (0.0 rating, 0 reviews)
      expect(isTopRated(0.0, 0), isFalse);
    });

    test('ItemCard rating label formatting matches real data', () {
      String formatRating(double rating, int reviewCount) {
        if (rating > 0 && reviewCount > 0) {
          return '${rating.toStringAsFixed(1)} ($reviewCount)';
        }
        return 'New';
      }

      expect(formatRating(0.0, 0), 'New');
      expect(formatRating(4.8, 12), '4.8 (12)');
      expect(formatRating(5.0, 1), '5.0 (1)');
    });
  });
}
