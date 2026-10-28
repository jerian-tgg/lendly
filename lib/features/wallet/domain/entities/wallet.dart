class Wallet {
  final String userId;
  final double availableBalance;
  final double escrowBalance;
  final double totalCashedIn;
  final double totalEarned;
  final DateTime? updatedAt;

  const Wallet({
    required this.userId,
    this.availableBalance = 0.0,
    this.escrowBalance = 0.0,
    this.totalCashedIn = 0.0,
    this.totalEarned = 0.0,
    this.updatedAt,
  });

  double get totalBalance => availableBalance + escrowBalance;

  factory Wallet.fromFirestore(String userId, Map<String, dynamic>? data) {
    if (data == null) {
      return Wallet(userId: userId);
    }
    return Wallet(
      userId: userId,
      availableBalance: (data['availableBalance'] as num?)?.toDouble() ?? 0.0,
      escrowBalance: (data['escrowBalance'] as num?)?.toDouble() ?? 0.0,
      totalCashedIn: (data['totalCashedIn'] as num?)?.toDouble() ?? 0.0,
      totalEarned: (data['totalEarned'] as num?)?.toDouble() ?? 0.0,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as dynamic).toDate()
          : null,
    );
  }
}
