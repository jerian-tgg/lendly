import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/features/wallet/domain/entities/wallet.dart';
import 'package:lendly/features/wallet/domain/entities/wallet_transaction.dart';

void main() {
  group('ORC Wallet Entity Tests', () {
    test('Default Wallet initializes with zero balances', () {
      const wallet = Wallet(userId: 'user_123');
      expect(wallet.userId, 'user_123');
      expect(wallet.availableBalance, 0.0);
      expect(wallet.escrowBalance, 0.0);
      expect(wallet.totalBalance, 0.0);
      expect(wallet.totalCashedIn, 0.0);
      expect(wallet.totalEarned, 0.0);
    });

    test('Wallet.fromFirestore parses valid data and computes totalBalance', () {
      final data = {
        'availableBalance': 1500.50,
        'escrowBalance': 500.00,
        'totalCashedIn': 2500.00,
        'totalEarned': 450.00,
      };

      final wallet = Wallet.fromFirestore('user_456', data);
      expect(wallet.userId, 'user_456');
      expect(wallet.availableBalance, 1500.50);
      expect(wallet.escrowBalance, 500.00);
      expect(wallet.totalBalance, 2000.50);
      expect(wallet.totalCashedIn, 2500.00);
      expect(wallet.totalEarned, 450.00);
    });

    test('Wallet.fromFirestore handles null and missing fields gracefully', () {
      final wallet = Wallet.fromFirestore('user_empty', null);
      expect(wallet.userId, 'user_empty');
      expect(wallet.availableBalance, 0.0);
      expect(wallet.escrowBalance, 0.0);
      expect(wallet.totalBalance, 0.0);
    });
  });

  group('ORC WalletTransaction Tests', () {
    test('WalletTransaction correctly identifies credits vs debits', () {
      const cashIn = WalletTransaction(
        id: 'tx_1',
        type: 'cash_in',
        amount: 500.0,
      );
      expect(cashIn.isCredit, true);

      const escrowHold = WalletTransaction(
        id: 'tx_2',
        type: 'rental_escrow',
        amount: -300.0,
      );
      expect(escrowHold.isCredit, false);
    });

    test('WalletTransaction parses from Firestore map accurately', () {
      final data = {
        'type': 'rental_earning',
        'amount': 270.0,
        'referenceId': 'convo_789',
        'description': 'Rental earnings (90% of ₱300 ORC)',
        'status': 'completed',
      };

      final tx = WalletTransaction.fromFirestore('tx_3', data);
      expect(tx.id, 'tx_3');
      expect(tx.type, 'rental_earning');
      expect(tx.amount, 270.0);
      expect(tx.referenceId, 'convo_789');
      expect(tx.status, 'completed');
      expect(tx.isCredit, true);
    });
  });

  group('Escrow Settlement & Conversion Math', () {
    test('10% platform commission and 90% lender earning split is precise', () {
      const double totalRentalPrice = 500.0;
      final double adminCommission = (totalRentalPrice * 0.10 * 100).round() / 100;
      final double lenderEarnings = ((totalRentalPrice - adminCommission) * 100).round() / 100;

      expect(adminCommission, 50.0);
      expect(lenderEarnings, 450.0);
      expect(adminCommission + lenderEarnings, totalRentalPrice);
    });

    test('₱1 PHP = 1 ORC conversion rate', () {
      const double phpAmount = 1250.0;
      const double orcConversionRate = 1.0;
      final double orcReceived = phpAmount * orcConversionRate;

      expect(orcReceived, 1250.0);
    });
  });
}
