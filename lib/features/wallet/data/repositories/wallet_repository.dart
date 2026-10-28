import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/entities/wallet_transaction.dart';

class WalletRepository {
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

  /// Calls Cloud Function to accept rental and hold funds in escrow.
  Future<void> acceptRentalRequest(String convoId) async {
    await _functions.httpsCallable('acceptRentalRequest').call({
      'convoId': convoId,
    });
  }

  /// Calls Cloud Function to cancel rental and refund escrow if held.
  Future<void> cancelOrRefundRental(String convoId, [String? reason]) async {
    await _functions.httpsCallable('cancelOrRefundRental').call({
      'convoId': convoId,
      'reason': reason,
    });
  }

  /// Calls Cloud Function to complete rental and settle 90% lender / 10% admin.
  Future<void> completeRental(String convoId) async {
    await _functions.httpsCallable('completeRental').call({
      'convoId': convoId,
    });
  }
}
