import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/core/services/review_service.dart';

void main() {
  group('Chat Item Review Eligibility & Flow Tests', () {
    test('Borrower can review item when transaction is complete', () {
      const currentUserId = 'borrower_123';
      const ownerId = 'lender_456';
      const itemId = 'item_789';

      bool isOwner(String uid, String itemOwnerId) => uid == itemOwnerId;
      bool isEligibleToReviewItem({
        required String uid,
        required String itemOwnerId,
        required String targetItemId,
        required bool isTransactionComplete,
      }) {
        if (targetItemId.isEmpty) return false;
        if (isOwner(uid, itemOwnerId)) return false;
        return isTransactionComplete;
      }

      // Completed transaction: borrower can review
      expect(
        isEligibleToReviewItem(
          uid: currentUserId,
          itemOwnerId: ownerId,
          targetItemId: itemId,
          isTransactionComplete: true,
        ),
        isTrue,
      );

      // Owner cannot review their own item
      expect(
        isEligibleToReviewItem(
          uid: ownerId,
          itemOwnerId: ownerId,
          targetItemId: itemId,
          isTransactionComplete: true,
        ),
        isFalse,
      );

      // Incomplete transaction cannot trigger post-completion review banner
      expect(
        isEligibleToReviewItem(
          uid: currentUserId,
          itemOwnerId: ownerId,
          targetItemId: itemId,
          isTransactionComplete: false,
        ),
        isFalse,
      );

      // Conversation without item cannot review item
      expect(
        isEligibleToReviewItem(
          uid: currentUserId,
          itemOwnerId: ownerId,
          targetItemId: '',
          isTransactionComplete: true,
        ),
        isFalse,
      );
    });

    test('Post-return review prompt triggers only on return action for borrower', () {
      bool shouldPromptReview({
        required String action,
        required bool isConfirmed,
        required bool isOwner,
        required String itemId,
      }) {
        return action == 'return' && isConfirmed && !isOwner && itemId.isNotEmpty;
      }

      // Handoff does not trigger review prompt
      expect(
        shouldPromptReview(action: 'handoff', isConfirmed: true, isOwner: false, itemId: 'item_1'),
        isFalse,
      );

      // Unconfirmed return does not trigger review prompt
      expect(
        shouldPromptReview(action: 'return', isConfirmed: false, isOwner: false, itemId: 'item_1'),
        isFalse,
      );

      // Lender return does not trigger item review prompt
      expect(
        shouldPromptReview(action: 'return', isConfirmed: true, isOwner: true, itemId: 'item_1'),
        isFalse,
      );

      // Borrower return triggers item review prompt!
      expect(
        shouldPromptReview(action: 'return', isConfirmed: true, isOwner: false, itemId: 'item_1'),
        isTrue,
      );
    });

    test('Transaction completeness correctly resolves all 4 stages', () {
      bool isFullyComplete({
        required bool isPaid,
        required bool isReceived,
        required bool isReturned,
        required bool isReturnConfirmed,
      }) {
        return isPaid && isReceived && isReturned && isReturnConfirmed;
      }

      expect(isFullyComplete(isPaid: true, isReceived: true, isReturned: true, isReturnConfirmed: true), isTrue);
      expect(isFullyComplete(isPaid: true, isReceived: true, isReturned: true, isReturnConfirmed: false), isFalse);
      expect(isFullyComplete(isPaid: true, isReceived: false, isReturned: false, isReturnConfirmed: false), isFalse);
    });

    test('Review label reflects rating score accurately', () {
      String getRatingLabel(double rating) {
        if (rating >= 5.0) return '⭐⭐⭐⭐⭐ Outstanding (5/5)';
        if (rating >= 4.0) return '⭐⭐⭐⭐ Very Good (4/5)';
        if (rating >= 3.0) return '⭐⭐⭐ Good / Average (3/5)';
        if (rating >= 2.0) return '⭐⭐ Fair / Minor Issues (2/5)';
        return '⭐ Poor / Disappointed (1/5)';
      }

      expect(getRatingLabel(5.0), contains('Outstanding'));
      expect(getRatingLabel(4.0), contains('Very Good'));
      expect(getRatingLabel(3.0), contains('Average'));
      expect(getRatingLabel(2.0), contains('Fair'));
      expect(getRatingLabel(1.0), contains('Poor'));
    });

    test('Recomputing item average rating with newly submitted review', () {
      // Existing reviews: [5.0, 4.0] -> avg 4.5
      final initialAvg = ReviewService.calculateAverageRating([5.0, 4.0]);
      expect(initialAvg, 4.5);

      // New review from chat borrower: 5.0 -> [5.0, 4.0, 5.0] = 14 / 3 = 4.666... -> 4.7
      final updatedAvg = ReviewService.calculateAverageRating([5.0, 4.0, 5.0]);
      expect(updatedAvg, 4.7);
    });
  });
}

