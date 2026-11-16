import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/features/admin/presentation/widgets/admin_ledger_transaction_card.dart';

void main() {
  group('AdminLedgerTransactionCard', () {
    final sampleTx = <String, dynamic>{
      'id': 'fee_rental_abc123456789',
      'type': 'service_fee',
      'amount': 50.0,
      'grossAmount': 500.0,
      'payoutAmount': 450.0,
      'referenceId': 'rental_abc123456789',
      'rentalId': 'rental_abc123456789',
      'itemId': 'item_xyz987',
      'itemName': 'Sony A7 III Camera',
      'lenderId': 'lender_uid_1234567890',
      'borrowerId': 'borrower_uid_0987654321',
      'description':
          '10% Platform Commission from Sony A7 III Camera (₱50.00 ORC of ₱500.00 ORC)',
      'status': 'completed',
      'createdAt': DateTime(2026, 11, 16, 14, 30, 15),
    };

    final lenderInfo = <String, dynamic>{
      'firstName': 'Alice',
      'lastName': 'Santos',
      'email': 'alice@example.com',
    };

    final borrowerInfo = <String, dynamic>{
      'firstName': 'Bob',
      'lastName': 'Reyes',
      'email': 'bob@example.com',
    };

    final rentalInfo = <String, dynamic>{
      'startDate': DateTime(2026, 11, 12),
      'endDate': DateTime(2026, 11, 15),
      'totalDays': 3,
      'escrowStatus': 'settled',
      'approved': true,
      'isPaid': true,
      'isReceived': true,
      'isReturned': true,
      'isReturnConfirmed': true,
      'settledAt': DateTime(2026, 11, 16, 14, 30, 15),
    };

    testWidgets('expands on tap to reveal full transaction details and collapses on second tap',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return _TestHarness(
                  data: sampleTx,
                  lenderInfo: lenderInfo,
                  borrowerInfo: borrowerInfo,
                  rentalInfo: rentalInfo,
                );
              },
            ),
          ),
        ),
      );

      // Collapsed initially
      expect(find.text('Commission Collected (Sony A7 III Camera)'), findsOneWidget);
      expect(find.text('+₱50.00'), findsOneWidget);
      expect(find.text('FULL TRANSACTION DETAILS'), findsNothing);
      expect(find.text('fee_rental_abc123456789'), findsNothing);

      // Tap card to expand
      await tester.tap(find.byType(AdminLedgerTransactionCard));
      await tester.pumpAndSettle();

      expect(find.text('FULL TRANSACTION DETAILS'), findsOneWidget);
      expect(find.text('fee_rental_abc123456789'), findsOneWidget);
      expect(find.text('item_xyz987'), findsOneWidget);
      expect(find.text('Alice Santos (alice@example.com)'), findsOneWidget);
      expect(find.text('Bob Reyes (bob@example.com)'), findsOneWidget);
      expect(find.text('lender_uid_1234567890'), findsOneWidget);
      expect(find.text('borrower_uid_0987654321'), findsOneWidget);
      expect(find.text('₱450.00 ORC'), findsOneWidget);
      expect(find.text('₱50.00 ORC'), findsOneWidget);
      expect(find.text('₱500.00 ORC'), findsOneWidget);
      expect(
        find.text('Approved → Paid → Received → Returned → Confirmed'),
        findsOneWidget,
      );

      // Tap again to collapse
      await tester.tap(find.text('Commission Collected (Sony A7 III Camera)'));
      await tester.pumpAndSettle();

      expect(find.text('FULL TRANSACTION DETAILS'), findsNothing);
    });

    testWidgets('renders escrow refund details including refund reason when expanded',
        (tester) async {
      final refundTx = <String, dynamic>{
        'id': 'refund_convo_55',
        'type': 'escrow_refund',
        'amount': 300.0,
        'grossAmount': 300.0,
        'referenceId': 'convo_55',
        'itemName': 'Camping Tent',
        'lenderId': 'lender_1',
        'borrowerId': 'borrower_1',
        'description': 'Escrow Refund to borrower (Item unavailable)',
        'status': 'refunded',
        'refundReason': 'Item unavailable',
        'createdAt': DateTime(2026, 11, 15, 9, 0),
        'refundedAt': DateTime(2026, 11, 15, 9, 0),
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestHarness(data: refundTx),
          ),
        ),
      );

      await tester.tap(find.byType(AdminLedgerTransactionCard));
      await tester.pumpAndSettle();

      expect(find.text('FULL TRANSACTION DETAILS'), findsOneWidget);
      expect(find.text('Escrow Refund (escrow_refund)'), findsOneWidget);
      expect(find.text('Item unavailable'), findsOneWidget);
      expect(find.text('Camping Tent'), findsOneWidget);
    });
  });
}

class _TestHarness extends StatefulWidget {
  const _TestHarness({
    required this.data,
    this.lenderInfo,
    this.borrowerInfo,
    this.rentalInfo,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? lenderInfo;
  final Map<String, dynamic>? borrowerInfo;
  final Map<String, dynamic>? rentalInfo;

  @override
  State<_TestHarness> createState() => _TestHarnessState();
}

class _TestHarnessState extends State<_TestHarness> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AdminLedgerTransactionCard(
        data: widget.data,
        isExpanded: _expanded,
        onTap: () => setState(() => _expanded = !_expanded),
        lenderInfo: widget.lenderInfo,
        borrowerInfo: widget.borrowerInfo,
        rentalInfo: widget.rentalInfo,
      ),
    );
  }
}
