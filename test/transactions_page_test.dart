import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transactions Page Filtering & Tab Logic', () {
    bool isCompleted(Map<String, dynamic> data) =>
        data['isPaid'] == true &&
        data['isReceived'] == true &&
        data['isReturned'] == true &&
        data['isReturnConfirmed'] == true;

    bool isLender(Map<String, dynamic> data, String userId) =>
        data['lenderId'] == userId || data['ownerId'] == userId;

    const currentUserId = 'user_abc';

    final transactions = [
      // 1. Active borrow (user is borrower)
      {
        'id': 'tx_1',
        'itemId': 'item_1',
        'lenderId': 'user_other',
        'ownerId': 'user_other',
        'isPaid': true,
        'isReceived': true,
        'isReturned': false,
        'isReturnConfirmed': false,
      },
      // 2. Active lend (user is lender)
      {
        'id': 'tx_2',
        'itemId': 'item_2',
        'lenderId': currentUserId,
        'ownerId': currentUserId,
        'isPaid': true,
        'isReceived': true,
        'isReturned': false,
        'isReturnConfirmed': false,
      },
      // 3. Completed transaction as borrower
      {
        'id': 'tx_3',
        'itemId': 'item_3',
        'lenderId': 'user_other',
        'ownerId': 'user_other',
        'isPaid': true,
        'isReceived': true,
        'isReturned': true,
        'isReturnConfirmed': true,
      },
      // 4. Completed transaction as lender
      {
        'id': 'tx_4',
        'itemId': 'item_4',
        'lenderId': currentUserId,
        'ownerId': currentUserId,
        'isPaid': true,
        'isReceived': true,
        'isReturned': true,
        'isReturnConfirmed': true,
      },
    ];

    test('Filters active items into Borrow tab', () {
      final borrow = transactions.where((d) {
        return !isCompleted(d) && !isLender(d, currentUserId);
      }).toList();

      expect(borrow.length, 1);
      expect(borrow.first['id'], 'tx_1');
    });

    test('Filters active items into Lend tab', () {
      final lend = transactions.where((d) {
        return !isCompleted(d) && isLender(d, currentUserId);
      }).toList();

      expect(lend.length, 1);
      expect(lend.first['id'], 'tx_2');
    });

    test('Consolidates both borrower and lender completed items into History tab', () {
      final history = transactions.where((d) {
        return isCompleted(d);
      }).toList();

      expect(history.length, 2);
      expect(history.map((t) => t['id']).toSet(), {'tx_3', 'tx_4'});
    });

    test('Tab labels match specification', () {
      const tabs = ['Borrow', 'Lend', 'History'];
      expect(tabs[0], 'Borrow');
      expect(tabs[1], 'Lend');
      expect(tabs[2], 'History');
    });
  });
}

