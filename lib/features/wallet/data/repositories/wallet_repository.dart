import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/entities/wallet_transaction.dart';

class WalletRepository {
  static const String adminEmail = 'palenciajerjer28@gmail.com';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Stream<Wallet> getWalletStream(String userId) {
    return _firestore.collection('wallets').doc(userId).snapshots().map((doc) {
      return Wallet.fromFirestore(userId, doc.data());
    });
  }

  Stream<List<WalletTransaction>> getTransactionsStream(String userId) {
    return _firestore
        .collection('wallets')
        .doc(userId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => WalletTransaction.fromFirestore(doc.id, doc.data()))
          .toList();
    });
  }

  /// Initiates a Stripe Cash-In session via Cloud Functions.
  Future<Map<String, dynamic>> createCashInSession(double amount) async {
    final result = await _functions.httpsCallable('createStripeCashInSession').call({
      'amount': amount,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Accepts a rental request and holds funds in escrow atomically.
  /// Logs the escrow hold to both the borrower's wallet and the Admin Ledger.
  Future<void> acceptRentalRequest(String convoId) async {
    bool settledByFunction = false;
    try {
      await _functions.httpsCallable('acceptRentalRequest').call({
        'convoId': convoId,
      });
      settledByFunction = true;
    } catch (e) {
      // If Cloud Function threw a business precondition error (e.g., insufficient balance),
      // only fall back to local transaction if it wasn't already handled.
      if (e is FirebaseFunctionsException &&
          (e.code == 'failed-precondition' || e.code == 'permission-denied')) {
        rethrow;
      }
    }

    if (!settledByFunction) {
      await _acceptRentalInFirestore(convoId);
    } else {
      // Ensure the Admin Ledger has the escrow_hold entry even if deployed Cloud Function is older
      await _ensureEscrowHoldLedgerEntry(convoId);
    }
  }

  /// Cancels a rental and refunds any held escrow to the borrower atomically.
  Future<void> cancelOrRefundRental(String convoId, [String? reason]) async {
    bool handledByFunction = false;
    try {
      await _functions.httpsCallable('cancelOrRefundRental').call({
        'convoId': convoId,
        'reason': reason,
      });
      handledByFunction = true;
    } catch (_) {}

    if (!handledByFunction) {
      await _refundRentalInFirestore(convoId, reason ?? 'Rental cancelled');
    } else {
      await _ensureRefundLedgerEntry(convoId, reason ?? 'Rental cancelled');
    }
  }

  /// Completes a rental and atomically settles 90% lender payout / 10% admin commission.
  /// Uses idempotent Firestore transaction verification so settlement succeeds even if
  /// the deployed Cloud Function had a read-after-write failure or was not triggered.
  Future<void> completeRental(String convoId) async {
    try {
      await _functions.httpsCallable('completeRental').call({
        'convoId': convoId,
      });
    } catch (_) {
      // Proceed to idempotent client-side atomic transaction check below
    }

    // Verify & atomically settle if not yet marked settled
    await settleEscrowInFirestore(convoId, markCompleted: true);
  }

  /// Atomically settles a completed rental in Firestore (all reads before writes).
  /// Safe and idempotent: checks `isSettled == true` and `escrowStatus == 'settled'` inside the transaction.
  Future<bool> settleEscrowInFirestore(
    String convoId, {
    bool markCompleted = false,
  }) async {
    final convoRef = _firestore.collection('conversations').doc(convoId);

    return _firestore.runTransaction<bool>((t) async {
      // ── PHASE 1: ALL READS FIRST (Firestore Transaction Requirement) ──────
      final convoDoc = await t.get(convoRef);
      if (!convoDoc.exists) return false;

      final convoData = convoDoc.data() ?? {};
      if (convoData['conversationType'] == 'appraisal') return false;

      final alreadySettled =
          convoData['isSettled'] == true || convoData['escrowStatus'] == 'settled';
      if (alreadySettled || convoData['escrowStatus'] == 'refunded') {
        if (markCompleted &&
            (convoData['isReturned'] != true || convoData['isReturnConfirmed'] != true)) {
          t.update(convoRef, {
            'isPaid': true,
            'isReceived': true,
            'isReturned': true,
            'isReturnConfirmed': true,
            'returnConfirmedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
        return false;
      }

      final itemId = (convoData['itemId'] as String?) ?? '';
      Map<String, dynamic>? itemData;
      if (itemId.isNotEmpty) {
        final itemDoc = await t.get(_firestore.collection('items').doc(itemId));
        if (itemDoc.exists) {
          itemData = itemDoc.data();
        }
      }

      final lenderId = (convoData['itemOwnerId'] as String?) ??
          (convoData['ownerId'] as String?) ??
          (itemData?['ownerId'] as String?) ??
          '';
      final participants = List<String>.from(convoData['participants'] ?? const []);
      final borrowerId = (convoData['borrowerId'] as String?) ??
          participants.firstWhere((p) => p.isNotEmpty && p != lenderId, orElse: () => '');

      double total = (convoData['escrowAmount'] as num?)?.toDouble() ?? 0.0;
      if (total <= 0) {
        final totalPrice = (convoData['totalPrice'] as num?)?.toDouble() ?? 0.0;
        if (totalPrice > 0) {
          total = totalPrice;
        } else {
          final days = (convoData['totalDays'] as num?)?.toInt() ?? 1;
          final price = (convoData['price'] as num?)?.toDouble() ??
              (itemData?['price'] as num?)?.toDouble() ??
              0.0;
          total = price * days;
        }
      }

      if (total <= 0 || borrowerId.isEmpty || lenderId.isEmpty) {
        t.update(convoRef, {
          if (markCompleted) ...{
            'isPaid': true,
            'isReceived': true,
            'isReturned': true,
            'isReturnConfirmed': true,
            'returnConfirmedAt': FieldValue.serverTimestamp(),
          },
          'escrowStatus': 'settled',
          'isSettled': true,
          'settledAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        return false;
      }

      final borrowerWalletRef = _firestore.collection('wallets').doc(borrowerId);
      final lenderWalletRef = _firestore.collection('wallets').doc(lenderId);
      final adminDedicatedWalletRef = _firestore.collection('wallets').doc(adminEmail);
      final adminWalletRef = _firestore.collection('admin_wallet').doc('main');

      final borrowerWalletDoc = await t.get(borrowerWalletRef);
      final lenderWalletDoc = await t.get(lenderWalletRef);
      final adminDedicatedWalletDoc = await t.get(adminDedicatedWalletRef);
      final adminWalletDoc = await t.get(adminWalletRef);

      // ── PHASE 2: COMPUTE 10% COMMISSION & 90% LENDER PAYOUT ────────────────
      final adminCommission = ((total * 0.10) * 100).round() / 100.0;
      final lenderEarnings = (((total - adminCommission)) * 100).round() / 100.0;
      final itemName = (convoData['itemName'] as String?) ??
          (itemData?['name'] as String?) ??
          (itemData?['title'] as String?) ??
          'Rental Item';
      final nowTs = FieldValue.serverTimestamp();

      final bData = borrowerWalletDoc.data() ?? {};
      final borrowerEscrow = (bData['escrowBalance'] as num?)?.toDouble() ?? 0.0;
      final newBorrowerEscrow = convoData['escrowStatus'] == 'held'
          ? (borrowerEscrow - total).clamp(0.0, double.infinity)
          : borrowerEscrow;

      final lData = lenderWalletDoc.data() ?? {};
      final lenderAvailable = (lData['availableBalance'] as num?)?.toDouble() ?? 0.0;
      final lenderTotalEarned = (lData['totalEarned'] as num?)?.toDouble() ?? 0.0;
      final newLenderAvailable = ((lenderAvailable + lenderEarnings) * 100).round() / 100.0;
      final newLenderTotalEarned = ((lenderTotalEarned + lenderEarnings) * 100).round() / 100.0;

      final adData = adminDedicatedWalletDoc.data() ?? {};
      final currentAdminBalance = (adData['balance'] as num?)?.toDouble() ??
          (adData['availableBalance'] as num?)?.toDouble() ??
          0.0;
      final currentAdminFees = (adData['totalFeesCollected'] as num?)?.toDouble() ??
          (adData['totalCommission'] as num?)?.toDouble() ??
          0.0;
      final currentAdminPayouts = (adData['totalPayoutsProcessed'] as num?)?.toDouble() ?? 0.0;

      final newAdminBalance = ((currentAdminBalance + adminCommission) * 100).round() / 100.0;
      final newAdminFees = ((currentAdminFees + adminCommission) * 100).round() / 100.0;
      final newAdminPayouts = ((currentAdminPayouts + lenderEarnings) * 100).round() / 100.0;

      final legData = adminWalletDoc.data() ?? {};
      final legacyBalance = (legData['balance'] as num?)?.toDouble() ?? 0.0;
      final legacyCommission = (legData['totalCommission'] as num?)?.toDouble() ?? 0.0;
      final legacyPayouts = (legData['totalPayoutsProcessed'] as num?)?.toDouble() ?? 0.0;

      final newLegacyBalance = ((legacyBalance + adminCommission) * 100).round() / 100.0;
      final newLegacyCommission = ((legacyCommission + adminCommission) * 100).round() / 100.0;
      final newLegacyPayouts = ((legacyPayouts + lenderEarnings) * 100).round() / 100.0;

      // ── PHASE 3: ALL WRITES ────────────────────────────────────────────────
      // 1. Borrower Wallet: release escrow & write settlement record
      t.set(
        borrowerWalletRef,
        {
          'escrowBalance': newBorrowerEscrow,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      final borrowerTxRef = borrowerWalletRef.collection('transactions').doc('settle_$convoId');
      t.set(
        borrowerTxRef,
        {
          'id': borrowerTxRef.id,
          'type': 'rental_payment',
          'amount': -total,
          'referenceId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'description': 'Rental completed — escrow released for $itemName (₱${total.toStringAsFixed(2)} ORC)',
          'status': 'completed',
          'createdAt': nowTs,
        },
        SetOptions(merge: true),
      );

      // 2. Lender Wallet: credit 90% payout
      t.set(
        lenderWalletRef,
        {
          'availableBalance': newLenderAvailable,
          'totalEarned': newLenderTotalEarned,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      t.set(
        _firestore.collection('users').doc(lenderId),
        {
          'balance': newLenderAvailable,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      final lenderTxRef = lenderWalletRef.collection('transactions').doc('earn_$convoId');
      t.set(
        lenderTxRef,
        {
          'id': lenderTxRef.id,
          'type': 'rental_earning',
          'amount': lenderEarnings,
          'grossAmount': total,
          'commissionDeducted': adminCommission,
          'referenceId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'description':
              'Rental earnings for $itemName (90% of ₱${total.toStringAsFixed(2)} ORC = ₱${lenderEarnings.toStringAsFixed(2)} ORC)',
          'status': 'completed',
          'createdAt': nowTs,
        },
        SetOptions(merge: true),
      );

      // 3. Admin Wallet: credit 10% commission to both dedicated & legacy admin wallets
      t.set(
        adminDedicatedWalletRef,
        {
          'balance': newAdminBalance,
          'availableBalance': newAdminBalance,
          'totalFeesCollected': newAdminFees,
          'totalCommission': newAdminFees,
          'totalPayoutsProcessed': newAdminPayouts,
          'role': 'admin',
          'email': adminEmail,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      t.set(
        _firestore.collection('users').doc(adminEmail),
        {
          'email': adminEmail,
          'role': 'admin',
          'isAdmin': true,
          'balance': newAdminBalance,
          'totalFeesCollected': newAdminFees,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      t.set(
        adminWalletRef,
        {
          'balance': newLegacyBalance,
          'totalCommission': newLegacyCommission,
          'totalFeesCollected': newLegacyCommission,
          'totalPayoutsProcessed': newLegacyPayouts,
          'updatedAt': nowTs,
        },
        SetOptions(merge: true),
      );

      // 4. Write Complete Admin Ledger Records (Escrow Hold -> Settled, 90% Payout, 10% Commission)
      final holdId = 'hold_$convoId';
      final holdRecord = <String, dynamic>{
        'id': holdId,
        'type': 'escrow_hold',
        'amount': total,
        'grossAmount': total,
        'referenceId': convoId,
        'rentalId': convoId,
        'itemId': itemId,
        'itemName': itemName,
        'borrowerId': borrowerId,
        'lenderId': lenderId,
        'description': 'Escrow Hold settled for $itemName (₱${total.toStringAsFixed(2)} ORC)',
        'status': 'settled',
        'settledAt': nowTs,
      };
      t.set(
        adminDedicatedWalletRef.collection('transactions').doc(holdId),
        holdRecord,
        SetOptions(merge: true),
      );
      t.set(
        adminWalletRef.collection('ledger').doc(holdId),
        holdRecord,
        SetOptions(merge: true),
      );

      final payoutId = 'payout_$convoId';
      final payoutRecord = <String, dynamic>{
        'id': payoutId,
        'type': 'lender_payout',
        'amount': lenderEarnings,
        'grossAmount': total,
        'commissionAmount': adminCommission,
        'referenceId': convoId,
        'rentalId': convoId,
        'itemId': itemId,
        'itemName': itemName,
        'borrowerId': borrowerId,
        'lenderId': lenderId,
        'description':
            '90% Lender Payout for $itemName (₱${lenderEarnings.toStringAsFixed(2)} ORC transferred to lender)',
        'status': 'completed',
        'createdAt': nowTs,
        'timestamp': nowTs,
      };
      t.set(
        adminDedicatedWalletRef.collection('transactions').doc(payoutId),
        payoutRecord,
        SetOptions(merge: true),
      );
      t.set(
        adminDedicatedWalletRef.collection('wallet_logs').doc(payoutId),
        payoutRecord,
        SetOptions(merge: true),
      );
      t.set(
        adminWalletRef.collection('ledger').doc(payoutId),
        payoutRecord,
        SetOptions(merge: true),
      );

      final feeId = 'fee_$convoId';
      final feeRecord = <String, dynamic>{
        'id': feeId,
        'type': 'service_fee',
        'amount': adminCommission,
        'grossAmount': total,
        'payoutAmount': lenderEarnings,
        'referenceId': convoId,
        'rentalId': convoId,
        'itemId': itemId,
        'itemName': itemName,
        'borrowerId': borrowerId,
        'lenderId': lenderId,
        'description':
            '10% Platform Commission from $itemName (₱${adminCommission.toStringAsFixed(2)} ORC of ₱${total.toStringAsFixed(2)} ORC)',
        'status': 'completed',
        'createdAt': nowTs,
        'timestamp': nowTs,
      };
      t.set(
        adminDedicatedWalletRef.collection('transactions').doc(feeId),
        feeRecord,
        SetOptions(merge: true),
      );
      t.set(
        adminDedicatedWalletRef.collection('wallet_logs').doc(feeId),
        feeRecord,
        SetOptions(merge: true),
      );
      t.set(
        adminWalletRef.collection('ledger').doc(feeId),
        feeRecord,
        SetOptions(merge: true),
      );

      t.set(
        adminWalletRef.collection('commissions').doc(convoId),
        {
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'amount': adminCommission,
          'payoutAmount': lenderEarnings,
          'grossAmount': total,
          'lenderId': lenderId,
          'borrowerId': borrowerId,
          'status': 'completed',
          'timestamp': nowTs,
        },
        SetOptions(merge: true),
      );

      // 5. Update conversation as settled
      t.update(convoRef, {
        if (markCompleted) ...{
          'isPaid': true,
          'isReceived': true,
          'isReturned': true,
          'isReturnConfirmed': true,
          'returnConfirmedAt': nowTs,
        },
        'escrowAmount': total,
        'escrowStatus': 'settled',
        'settledAt': nowTs,
        'adminCommission': adminCommission,
        'lenderEarnings': lenderEarnings,
        'isSettled': true,
        'lastUpdated': nowTs,
      });

      return true;
    });
  }

  /// Client fallback to accept rental request and hold escrow atomically.
  Future<void> _acceptRentalInFirestore(String convoId) async {
    final convoRef = _firestore.collection('conversations').doc(convoId);

    await _firestore.runTransaction((t) async {
      final convoDoc = await t.get(convoRef);
      if (!convoDoc.exists) throw Exception('Conversation does not exist.');

      final convoData = convoDoc.data() ?? {};
      if (convoData['approved'] == true) return;

      final itemId = (convoData['itemId'] as String?) ?? '';
      Map<String, dynamic>? itemData;
      if (itemId.isNotEmpty) {
        final itemDoc = await t.get(_firestore.collection('items').doc(itemId));
        if (itemDoc.exists) itemData = itemDoc.data();
      }

      final lenderId = (convoData['itemOwnerId'] as String?) ??
          (convoData['ownerId'] as String?) ??
          (itemData?['ownerId'] as String?) ??
          '';
      final participants = List<String>.from(convoData['participants'] ?? const []);
      final borrowerId = (convoData['borrowerId'] as String?) ??
          participants.firstWhere((p) => p.isNotEmpty && p != lenderId, orElse: () => '');

      double total = (convoData['totalPrice'] as num?)?.toDouble() ?? 0.0;
      if (total <= 0) {
        final days = (convoData['totalDays'] as num?)?.toInt() ?? 1;
        final price = (convoData['price'] as num?)?.toDouble() ??
            (itemData?['price'] as num?)?.toDouble() ??
            0.0;
        total = price * days;
      }

      final borrowerWalletRef = _firestore.collection('wallets').doc(borrowerId);
      final borrowerWalletDoc = await t.get(borrowerWalletRef);
      final bData = borrowerWalletDoc.data() ?? {};
      final currentAvailable = (bData['availableBalance'] as num?)?.toDouble() ?? 0.0;
      final currentEscrow = (bData['escrowBalance'] as num?)?.toDouble() ?? 0.0;

      if (currentAvailable < total) {
        throw Exception(
          'Borrower has insufficient ORC balance (Available: ₱${currentAvailable.toStringAsFixed(0)}, Required: ₱${total.toStringAsFixed(0)}).',
        );
      }

      final nowTs = FieldValue.serverTimestamp();
      final itemName = (convoData['itemName'] as String?) ??
          (itemData?['name'] as String?) ??
          (itemData?['title'] as String?) ??
          'Rental Item';

      if (total > 0) {
        final newAvailable = ((currentAvailable - total) * 100).round() / 100.0;
        final newEscrow = ((currentEscrow + total) * 100).round() / 100.0;

        t.set(
          borrowerWalletRef,
          {
            'availableBalance': newAvailable,
            'escrowBalance': newEscrow,
            'updatedAt': nowTs,
          },
          SetOptions(merge: true),
        );

        t.set(
          _firestore.collection('users').doc(borrowerId),
          {
            'balance': newAvailable,
            'updatedAt': nowTs,
          },
          SetOptions(merge: true),
        );

        final txRef = borrowerWalletRef.collection('transactions').doc('escrow_$convoId');
        t.set(
          txRef,
          {
            'id': txRef.id,
            'type': 'rental_escrow',
            'amount': -total,
            'referenceId': convoId,
            'itemId': itemId,
            'itemName': itemName,
            'description': 'Escrow hold for rental ($itemName)',
            'status': 'held',
            'createdAt': nowTs,
          },
          SetOptions(merge: true),
        );

        final adminDedicatedWalletRef = _firestore.collection('wallets').doc(adminEmail);
        final adminWalletRef = _firestore.collection('admin_wallet').doc('main');
        final holdId = 'hold_$convoId';
        final holdRecord = {
          'id': holdId,
          'type': 'escrow_hold',
          'amount': total,
          'grossAmount': total,
          'referenceId': convoId,
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'borrowerId': borrowerId,
          'lenderId': lenderId,
          'description': 'Escrow Hold locked for $itemName (₱${total.toStringAsFixed(2)} ORC)',
          'status': 'held',
          'createdAt': nowTs,
          'timestamp': nowTs,
        };
        t.set(
          adminDedicatedWalletRef.collection('transactions').doc(holdId),
          holdRecord,
          SetOptions(merge: true),
        );
        t.set(
          adminDedicatedWalletRef.collection('wallet_logs').doc(holdId),
          holdRecord,
          SetOptions(merge: true),
        );
        t.set(
          adminWalletRef.collection('ledger').doc(holdId),
          holdRecord,
          SetOptions(merge: true),
        );
      }

      t.update(convoRef, {
        'approved': true,
        'denied': false,
        'isSettled': false,
        'borrowerId': borrowerId,
        'itemOwnerId': lenderId,
        'ownerId': lenderId,
        'escrowAmount': total,
        'escrowStatus': total > 0 ? 'held' : 'none',
        'acceptedAt': nowTs,
        'lastUpdated': nowTs,
      });
    });
  }

  /// Ensures `hold_$convoId` exists in the Admin Ledger after Cloud Function acceptance.
  Future<void> _ensureEscrowHoldLedgerEntry(String convoId) async {
    try {
      final convoDoc = await _firestore.collection('conversations').doc(convoId).get();
      if (!convoDoc.exists) return;
      final d = convoDoc.data() ?? {};
      final total = (d['escrowAmount'] as num?)?.toDouble() ??
          (d['totalPrice'] as num?)?.toDouble() ??
          0.0;
      if (total <= 0) return;

      final itemId = (d['itemId'] as String?) ?? '';
      String itemName = (d['itemName'] as String?) ?? '';
      if (itemName.isEmpty && itemId.isNotEmpty) {
        final itemDoc = await _firestore.collection('items').doc(itemId).get();
        if (itemDoc.exists) {
          itemName = (itemDoc.data()?['name'] as String?) ??
              (itemDoc.data()?['title'] as String?) ??
              'Rental Item';
        }
      }
      if (itemName.isEmpty) itemName = 'Rental Item';

      final lenderId = (d['itemOwnerId'] as String?) ?? (d['ownerId'] as String?) ?? '';
      final borrowerId = (d['borrowerId'] as String?) ?? '';
      final holdId = 'hold_$convoId';
      final nowTs = FieldValue.serverTimestamp();
      final status = (d['escrowStatus'] as String?) ?? 'held';

      final holdRecord = <String, dynamic>{
        'id': holdId,
        'type': 'escrow_hold',
        'amount': total,
        'grossAmount': total,
        'referenceId': convoId,
        'rentalId': convoId,
        'itemId': itemId,
        'itemName': itemName,
        'borrowerId': borrowerId,
        'lenderId': lenderId,
        'description': 'Escrow Hold locked for $itemName (₱${total.toStringAsFixed(2)} ORC)',
        'status': status,
        'createdAt': d['acceptedAt'] ?? d['lastUpdated'] ?? nowTs,
        'timestamp': d['acceptedAt'] ?? d['lastUpdated'] ?? nowTs,
      };

      final adminDedicatedRef = _firestore.collection('wallets').doc(adminEmail);
      final adminLegacyRef = _firestore.collection('admin_wallet').doc('main');
      await adminDedicatedRef
          .collection('transactions')
          .doc(holdId)
          .set(holdRecord, SetOptions(merge: true));
      await adminLegacyRef
          .collection('ledger')
          .doc(holdId)
          .set(holdRecord, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Client fallback to cancel rental and refund held escrow.
  Future<void> _refundRentalInFirestore(String convoId, String reason) async {
    final convoRef = _firestore.collection('conversations').doc(convoId);

    await _firestore.runTransaction((t) async {
      final convoDoc = await t.get(convoRef);
      if (!convoDoc.exists) return;
      final convoData = convoDoc.data() ?? {};

      final total = (convoData['escrowAmount'] as num?)?.toDouble() ?? 0.0;
      final borrowerId = (convoData['borrowerId'] as String?) ?? '';
      final lenderId =
          (convoData['itemOwnerId'] as String?) ?? (convoData['ownerId'] as String?) ?? '';
      final itemId = (convoData['itemId'] as String?) ?? '';
      final itemName = (convoData['itemName'] as String?) ?? 'Rental Item';
      final isHeld = convoData['escrowStatus'] == 'held';

      DocumentSnapshot<Map<String, dynamic>>? borrowerWalletDoc;
      final borrowerWalletRef =
          borrowerId.isNotEmpty ? _firestore.collection('wallets').doc(borrowerId) : null;
      if (isHeld && total > 0 && borrowerWalletRef != null) {
        borrowerWalletDoc = await t.get(borrowerWalletRef);
      }

      final nowTs = FieldValue.serverTimestamp();

      if (isHeld && total > 0 && borrowerWalletRef != null) {
        final bData = borrowerWalletDoc?.data() ?? {};
        final currentAvailable = (bData['availableBalance'] as num?)?.toDouble() ?? 0.0;
        final currentEscrow = (bData['escrowBalance'] as num?)?.toDouble() ?? 0.0;
        final newAvailable = ((currentAvailable + total) * 100).round() / 100.0;
        final newEscrow = (currentEscrow - total).clamp(0.0, double.infinity);

        t.set(
          borrowerWalletRef,
          {
            'availableBalance': newAvailable,
            'escrowBalance': newEscrow,
            'updatedAt': nowTs,
          },
          SetOptions(merge: true),
        );

        t.set(
          _firestore.collection('users').doc(borrowerId),
          {
            'balance': newAvailable,
            'updatedAt': nowTs,
          },
          SetOptions(merge: true),
        );

        final txRef = borrowerWalletRef.collection('transactions').doc('refund_$convoId');
        t.set(
          txRef,
          {
            'id': txRef.id,
            'type': 'rental_refund',
            'amount': total,
            'referenceId': convoId,
            'description': 'Refund for rental ($reason)',
            'status': 'completed',
            'createdAt': nowTs,
          },
          SetOptions(merge: true),
        );

        final adminDedicatedRef = _firestore.collection('wallets').doc(adminEmail);
        final adminLegacyRef = _firestore.collection('admin_wallet').doc('main');
        final holdId = 'hold_$convoId';
        final refundId = 'refund_$convoId';

        t.set(
          adminDedicatedRef.collection('transactions').doc(holdId),
          {'id': holdId, 'type': 'escrow_hold', 'status': 'refunded', 'refundedAt': nowTs},
          SetOptions(merge: true),
        );
        t.set(
          adminLegacyRef.collection('ledger').doc(holdId),
          {'id': holdId, 'type': 'escrow_hold', 'status': 'refunded', 'refundedAt': nowTs},
          SetOptions(merge: true),
        );

        final refundRecord = {
          'id': refundId,
          'type': 'escrow_refund',
          'amount': total,
          'grossAmount': total,
          'referenceId': convoId,
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'borrowerId': borrowerId,
          'lenderId': lenderId,
          'description': 'Escrow Refund to borrower ($reason) — ₱${total.toStringAsFixed(2)} ORC',
          'status': 'refunded',
          'createdAt': nowTs,
          'timestamp': nowTs,
        };
        t.set(
          adminDedicatedRef.collection('transactions').doc(refundId),
          refundRecord,
          SetOptions(merge: true),
        );
        t.set(
          adminLegacyRef.collection('ledger').doc(refundId),
          refundRecord,
          SetOptions(merge: true),
        );
      }

      t.update(convoRef, {
        'denied': true,
        'approved': false,
        'cancelled': true,
        'cancelReason': reason,
        if (isHeld) ...{
          'escrowStatus': 'refunded',
          'refundedAt': nowTs,
          'refundReason': reason,
        },
        'lastUpdated': nowTs,
      });
    });
  }

  Future<void> _ensureRefundLedgerEntry(String convoId, String reason) async {
    try {
      final convoDoc = await _firestore.collection('conversations').doc(convoId).get();
      if (!convoDoc.exists) return;
      final d = convoDoc.data() ?? {};
      if (d['escrowStatus'] != 'refunded') return;
      final total = (d['escrowAmount'] as num?)?.toDouble() ?? 0.0;
      if (total <= 0) return;

      final adminDedicatedRef = _firestore.collection('wallets').doc(adminEmail);
      final adminLegacyRef = _firestore.collection('admin_wallet').doc('main');
      final holdId = 'hold_$convoId';
      final refundId = 'refund_$convoId';
      final nowTs = FieldValue.serverTimestamp();

      await adminDedicatedRef
          .collection('transactions')
          .doc(holdId)
          .set({'status': 'refunded'}, SetOptions(merge: true));
      await adminLegacyRef
          .collection('ledger')
          .doc(holdId)
          .set({'status': 'refunded'}, SetOptions(merge: true));

      final refundRecord = {
        'id': refundId,
        'type': 'escrow_refund',
        'amount': total,
        'grossAmount': total,
        'referenceId': convoId,
        'rentalId': convoId,
        'itemId': (d['itemId'] as String?) ?? '',
        'itemName': (d['itemName'] as String?) ?? 'Rental Item',
        'borrowerId': (d['borrowerId'] as String?) ?? '',
        'lenderId': (d['itemOwnerId'] as String?) ?? (d['ownerId'] as String?) ?? '',
        'description': 'Escrow Refund to borrower ($reason) — ₱${total.toStringAsFixed(2)} ORC',
        'status': 'refunded',
        'createdAt': d['refundedAt'] ?? nowTs,
        'timestamp': d['refundedAt'] ?? nowTs,
      };
      await adminDedicatedRef
          .collection('transactions')
          .doc(refundId)
          .set(refundRecord, SetOptions(merge: true));
      await adminLegacyRef
          .collection('ledger')
          .doc(refundId)
          .set(refundRecord, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Initializes/seeds the admin wallet and reconciles any completed rentals
  /// whose 10% commission or ledger entries had not yet been recorded.
  Future<void> seedAdminWallet() async {
    try {
      await _functions.httpsCallable('seedAdminWallet').call();
    } catch (_) {
      // Best-effort remote seeding
    }
    await reconcileRentalsAndAdminLedger();
  }

  /// Scans rentals to:
  /// 1. Atomically settle any completed rental (`isReturned && isReturnConfirmed`) that wasn't settled yet.
  /// 2. Backfill deterministic Admin Ledger records (`hold_`, `payout_`, `fee_`) for all held/settled rentals.
  /// 3. Synchronize Admin Wallet totals (`wallets/palenciajerjer28@gmail.com` and `admin_wallet/main`).
  Future<void> reconcileRentalsAndAdminLedger() async {
    try {
      final convosSnap = await _firestore.collection('conversations').get();

      double computedTotalCommission = 0.0;
      double computedTotalPayouts = 0.0;

      for (final doc in convosSnap.docs) {
        final d = doc.data();
        if (d['conversationType'] == 'appraisal') continue;

        final convoId = doc.id;
        final isCompleted = d['isReturned'] == true && d['isReturnConfirmed'] == true;
        final isSettled = d['isSettled'] == true || d['escrowStatus'] == 'settled';
        final isRefunded = d['escrowStatus'] == 'refunded';
        final isHeld = d['escrowStatus'] == 'held';

        // 1. If rental is completed but not settled, run atomic settlement now!
        if (isCompleted && !isSettled && !isRefunded) {
          await settleEscrowInFirestore(convoId);
        } else if (isHeld) {
          await _ensureEscrowHoldLedgerEntry(convoId);
        }
      }

      // 2. Re-read settled conversations to ensure ledger entries and admin totals are 100% synced
      final refreshedSnap = await _firestore.collection('conversations').get();
      final adminDedicatedRef = _firestore.collection('wallets').doc(adminEmail);
      final adminLegacyRef = _firestore.collection('admin_wallet').doc('main');

      for (final doc in refreshedSnap.docs) {
        final d = doc.data();
        if (d['conversationType'] == 'appraisal') continue;

        final isSettled = d['isSettled'] == true || d['escrowStatus'] == 'settled';
        if (!isSettled) continue;

        final convoId = doc.id;
        final total = (d['escrowAmount'] as num?)?.toDouble() ??
            (d['totalPrice'] as num?)?.toDouble() ??
            0.0;
        if (total <= 0) continue;

        final fee = (d['adminCommission'] as num?)?.toDouble() ??
            (((total * 0.10) * 100).round() / 100.0);
        final payout = (d['lenderEarnings'] as num?)?.toDouble() ??
            (((total - fee) * 100).round() / 100.0);

        computedTotalCommission = ((computedTotalCommission + fee) * 100).round() / 100.0;
        computedTotalPayouts = ((computedTotalPayouts + payout) * 100).round() / 100.0;

        final itemId = (d['itemId'] as String?) ?? '';
        final itemName = (d['itemName'] as String?) ?? 'Rental Item';
        final lenderId = (d['itemOwnerId'] as String?) ?? (d['ownerId'] as String?) ?? '';
        final borrowerId = (d['borrowerId'] as String?) ?? '';
        final settledTs = d['settledAt'] ?? d['returnConfirmedAt'] ?? d['lastUpdated'] ?? FieldValue.serverTimestamp();

        final holdId = 'hold_$convoId';
        final payoutId = 'payout_$convoId';
        final feeId = 'fee_$convoId';

        final holdRecord = {
          'id': holdId,
          'type': 'escrow_hold',
          'amount': total,
          'grossAmount': total,
          'referenceId': convoId,
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'borrowerId': borrowerId,
          'lenderId': lenderId,
          'description': 'Escrow Hold settled for $itemName (₱${total.toStringAsFixed(2)} ORC)',
          'status': 'settled',
          'createdAt': d['acceptedAt'] ?? settledTs,
          'timestamp': d['acceptedAt'] ?? settledTs,
          'settledAt': settledTs,
        };

        final payoutRecord = {
          'id': payoutId,
          'type': 'lender_payout',
          'amount': payout,
          'grossAmount': total,
          'commissionAmount': fee,
          'referenceId': convoId,
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'borrowerId': borrowerId,
          'lenderId': lenderId,
          'description':
              '90% Lender Payout for $itemName (₱${payout.toStringAsFixed(2)} ORC transferred to lender)',
          'status': 'completed',
          'createdAt': settledTs,
          'timestamp': settledTs,
        };

        final feeRecord = {
          'id': feeId,
          'type': 'service_fee',
          'amount': fee,
          'grossAmount': total,
          'payoutAmount': payout,
          'referenceId': convoId,
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'borrowerId': borrowerId,
          'lenderId': lenderId,
          'description':
              '10% Platform Commission from $itemName (₱${fee.toStringAsFixed(2)} ORC of ₱${total.toStringAsFixed(2)} ORC)',
          'status': 'completed',
          'createdAt': settledTs,
          'timestamp': settledTs,
        };

        await adminDedicatedRef.collection('transactions').doc(holdId).set(holdRecord, SetOptions(merge: true));
        await adminDedicatedRef.collection('transactions').doc(payoutId).set(payoutRecord, SetOptions(merge: true));
        await adminDedicatedRef.collection('transactions').doc(feeId).set(feeRecord, SetOptions(merge: true));

        await adminLegacyRef.collection('ledger').doc(holdId).set(holdRecord, SetOptions(merge: true));
        await adminLegacyRef.collection('ledger').doc(payoutId).set(payoutRecord, SetOptions(merge: true));
        await adminLegacyRef.collection('ledger').doc(feeId).set(feeRecord, SetOptions(merge: true));
        await adminLegacyRef.collection('commissions').doc(convoId).set({
          'rentalId': convoId,
          'itemId': itemId,
          'itemName': itemName,
          'amount': fee,
          'payoutAmount': payout,
          'grossAmount': total,
          'lenderId': lenderId,
          'borrowerId': borrowerId,
          'status': 'completed',
          'timestamp': settledTs,
        }, SetOptions(merge: true));
      }

      // 3. Ensure admin wallet documents reflect at least the computed settled commissions
      final adminSnap = await adminDedicatedRef.get();
      final currentBal = (adminSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final targetBal = computedTotalCommission > currentBal ? computedTotalCommission : currentBal;

      await adminDedicatedRef.set({
        'balance': targetBal,
        'availableBalance': targetBal,
        'totalFeesCollected': targetBal,
        'totalCommission': targetBal,
        'totalPayoutsProcessed': computedTotalPayouts,
        'role': 'admin',
        'email': adminEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await adminLegacyRef.set({
        'balance': targetBal,
        'totalCommission': targetBal,
        'totalFeesCollected': targetBal,
        'totalPayoutsProcessed': computedTotalPayouts,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(adminEmail).set({
        'email': adminEmail,
        'role': 'admin',
        'isAdmin': true,
        'balance': targetBal,
        'totalFeesCollected': targetBal,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

