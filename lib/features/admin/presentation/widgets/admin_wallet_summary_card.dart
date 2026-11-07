import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/admin/presentation/pages/admin_wallet_page.dart';

/// Admin Wallet Summary Card displayed on the Admin Dashboard.
/// Visual styling, typography, and layout match the user-facing Wallet Card
/// on the User Home Page (LinearGradient purple, amber badge, ORC balance,
/// and live metrics).
class AdminWalletSummaryCard extends StatelessWidget {
  const AdminWalletSummaryCard({super.key});

  static const String adminEmail = 'palenciajerjer28@gmail.com';

  String _formatAmount(num amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // Stream 1: Dedicated Admin Wallet document stream
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('wallets').doc(adminEmail).snapshots(),
      builder: (context, adminWalletSnap) {
        // Stream 2: Fallback / legacy admin wallet for unified totals
        return StreamBuilder<DocumentSnapshot>(
          stream: db.collection('admin_wallet').doc('main').snapshots(),
          builder: (context, legacySnap) {
            // Stream 3: Active Escrow volume (held conversations)
            return StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('conversations')
                  .where('escrowStatus', isEqualTo: 'held')
                  .snapshots(),
              builder: (context, convoSnap) {
                // Compute admin balance & fees
                double balance = 0.0;
                double totalFees = 0.0;

                final walletData = adminWalletSnap.data?.data() as Map<String, dynamic>?;
                if (walletData != null) {
                  balance = (walletData['balance'] as num?)?.toDouble() ??
                      (walletData['availableBalance'] as num?)?.toDouble() ??
                      0.0;
                  totalFees = (walletData['totalFeesCollected'] as num?)?.toDouble() ??
                      (walletData['totalCommission'] as num?)?.toDouble() ??
                      0.0;
                }

                // If dedicated wallet has 0, fallback to legacy main wallet if present
                if (balance == 0.0 && legacySnap.hasData && legacySnap.data!.exists) {
                  final legacyData = legacySnap.data!.data() as Map<String, dynamic>?;
                  if (legacyData != null) {
                    balance = (legacyData['balance'] as num?)?.toDouble() ?? 0.0;
                    totalFees = (legacyData['totalCommission'] as num?)?.toDouble() ?? 0.0;
                  }
                }

                // Compute active escrow volume
                double activeEscrowVolume = 0.0;
                if (convoSnap.hasData && convoSnap.data!.docs.isNotEmpty) {
                  for (final doc in convoSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>?;
                    if (data != null) {
                      activeEscrowVolume += (data['escrowAmount'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showFeeDetailsModal(context, balance, totalFees, activeEscrowVolume),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B40B5).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left column: Balance & Escrow metrics
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Admin Fee Balance:',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.amber[300]!,
                                          Colors.amber[600]!,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber.withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'O',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${_formatAmount(balance)} ORC',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.lock_clock,
                                    size: 12,
                                    color: Colors.amber[200],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active Escrow: ${_formatAmount(activeEscrowVolume)} ORC',
                                    style: TextStyle(
                                      color: Colors.amber[200],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '• 10% Fee Split',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Right side action: View Details button
                        ElevatedButton.icon(
                          onPressed: () => _showFeeDetailsModal(
                            context,
                            balance,
                            totalFees,
                            activeEscrowVolume,
                          ),
                          icon: const Icon(
                            Icons.receipt_long,
                            size: 16,
                            color: Color(0xFF7B40B5),
                          ),
                          label: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Color(0xFF7B40B5),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showFeeDetailsModal(
    BuildContext context,
    double balance,
    double totalFees,
    double activeEscrow,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AdminFeeDetailsSheet(
        balance: balance,
        totalFees: totalFees,
        activeEscrow: activeEscrow,
      ),
    );
  }
}

class _AdminFeeDetailsSheet extends StatelessWidget {
  final double balance;
  final double totalFees;
  final double activeEscrow;

  const _AdminFeeDetailsSheet({
    required this.balance,
    required this.totalFees,
    required this.activeEscrow,
  });

  String _formatAmount(num amount) {
    return '₱${amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}';
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final transactionsQuery = db
        .collection('wallets')
        .doc(AdminWalletSummaryCard.adminEmail)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(30);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '10% Platform Service Fee Breakdown',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007799),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Dedicated Admin Wallet (${AdminWalletSummaryCard.adminEmail})',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary metric cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            'Fee Balance',
                            _formatAmount(balance),
                            const Color(0xFF27AE60),
                            Icons.account_balance_wallet,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            'Total Collected',
                            _formatAmount(totalFees),
                            const Color(0xFF007799),
                            Icons.pie_chart,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            'Active Escrow',
                            _formatAmount(activeEscrow),
                            const Color(0xFF7B40B5),
                            Icons.lock_clock,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Section title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent 10% Fee Inflows',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminWalletPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('All Revenue', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Live fee inflow transactions stream
                    StreamBuilder<QuerySnapshot>(
                      stream: transactionsQuery.snapshots(),
                      builder: (context, txSnap) {
                        if (txSnap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final docs = txSnap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          // Try falling back to commissions subcollection on legacy admin wallet
                          return StreamBuilder<QuerySnapshot>(
                            stream: db
                                .collection('admin_wallet')
                                .doc('main')
                                .collection('commissions')
                                .orderBy('timestamp', descending: true)
                                .limit(20)
                                .snapshots(),
                            builder: (context, commSnap) {
                              final commDocs = commSnap.data?.docs ?? [];
                              if (commDocs.isEmpty) {
                                return _buildEmptyState();
                              }
                              return Column(
                                children: commDocs.map((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return _buildCommissionItem(
                                    txId: d.id,
                                    feeAmount: (data['amount'] as num?)?.toDouble() ?? 0.0,
                                    grossAmount: (data['grossAmount'] as num?)?.toDouble() ?? 0.0,
                                    lenderId: data['lenderId'] as String?,
                                    borrowerId: data['borrowerId'] as String?,
                                    timestamp: data['timestamp'] as Timestamp?,
                                  );
                                }).toList(),
                              );
                            },
                          );
                        }

                        return Column(
                          children: docs.map((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final feeAmount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                            final grossAmount = (data['grossAmount'] as num?)?.toDouble() ??
                                (feeAmount > 0 ? feeAmount / 0.10 : 0.0);
                            final referenceId = data['referenceId'] as String? ?? d.id;
                            final borrowerId = data['borrowerId'] as String?;
                            final lenderId = data['lenderId'] as String?;
                            final timestamp = data['createdAt'] as Timestamp?;

                            return _buildCommissionItem(
                              txId: referenceId,
                              feeAmount: feeAmount,
                              grossAmount: grossAmount,
                              lenderId: lenderId,
                              borrowerId: borrowerId,
                              timestamp: timestamp,
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionItem({
    required String txId,
    required double feeAmount,
    required double grossAmount,
    required String? lenderId,
    required String? borrowerId,
    required Timestamp? timestamp,
  }) {
    final dateStr = timestamp != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(timestamp.toDate())
        : 'Just now';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Rental ID & 10% Fee Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007799).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'TX: ${txId.length > 12 ? txId.substring(0, 12) : txId}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF007799),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '10% Platform Fee',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '+₱${feeAmount.toStringAsFixed(2)} ORC',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF27AE60),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Middle row: Gross transaction amount & timestamp
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gross Amount: ₱${grossAmount.toStringAsFixed(2)} ORC',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Source user IDs row
          Row(
            children: [
              if (borrowerId != null && borrowerId.isNotEmpty)
                Expanded(
                  child: Text(
                    'Borrower: ${borrowerId.length > 8 ? borrowerId.substring(0, 8) : borrowerId}...',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (lenderId != null && lenderId.isNotEmpty)
                Expanded(
                  child: Text(
                    'Lender: ${lenderId.length > 8 ? lenderId.substring(0, 8) : lenderId}...',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.savings_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          const Text(
            'No Service Fees Settled Yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'When users complete rentals, the 10% platform fee will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

