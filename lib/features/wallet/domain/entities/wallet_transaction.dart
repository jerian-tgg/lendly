import 'package:cloud_firestore/cloud_firestore.dart';

class WalletTransaction {
  final String id;
  final String type; // 'cash_in' | 'rental_escrow' | 'rental_payment' | 'rental_earning' | 'rental_refund'
  final double amount;
  final String? referenceId;
  final String? description;
  final String status;
  final DateTime? createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.referenceId,
    this.description,
    this.status = 'completed',
    this.createdAt,
  });

  bool get isCredit => amount > 0;

  factory WalletTransaction.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? created;
    if (data['createdAt'] is Timestamp) {
      created = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is DateTime) {
      created = data['createdAt'] as DateTime;
    }

    return WalletTransaction(
      id: id,
      type: data['type'] as String? ?? 'unknown',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      referenceId: data['referenceId'] as String?,
      description: data['description'] as String?,
      status: data['status'] as String? ?? 'completed',
      createdAt: created,
    );
  }
}
