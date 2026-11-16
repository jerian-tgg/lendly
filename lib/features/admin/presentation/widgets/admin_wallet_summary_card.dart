import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lendly/features/admin/presentation/pages/admin_wallet_page.dart';
import 'package:lendly/features/admin/presentation/widgets/admin_ledger_transaction_card.dart';
import 'package:lendly/features/wallet/data/repositories/wallet_repository.dart';

/// Admin Wallet Summary Card displayed on the Admin Dashboard.
/// Visual styling, typography, and layout match the user-facing Wallet Card
/// on the User Home Page (LinearGradient purple, amber badge, ORC balance,
/// and live metrics).
class AdminWalletSummaryCard extends StatefulWidget {
  const AdminWalletSummaryCard({super.key});

  static const String adminEmail = WalletRepository.adminEmail;

  @override
  State<AdminWalletSummaryCard> createState() => _AdminWalletSummaryCardState();
}

class _AdminWalletSummaryCardState extends State<AdminWalletSummaryCard> {
  @override
  void initState() {
    super.initState();
    WalletRepository().reconcileRentalsAndAdminLedger();
  }

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
      stream: db.collection('wallets').doc(AdminWalletSummaryCard.adminEmail).snapshots(),
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
                        colors: [Color(0xFF98259A), Color(0xFF6B156C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF98259A).withValues(alpha: 0.3),
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
                            color: Color(0xFF98259A),
                          ),
                          label: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Color(0xFF98259A),
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

class _AdminFeeDetailsSheet extends StatefulWidget {
  final double balance;
  final double totalFees;
  final double activeEscrow;

  const _AdminFeeDetailsSheet({
    required this.balance,
    required this.totalFees,
    required this.activeEscrow,
  });

  @override
  State<_AdminFeeDetailsSheet> createState() => _AdminFeeDetailsSheetState();
}

class _AdminFeeDetailsSheetState extends State<_AdminFeeDetailsSheet> {
  final AdminLedgerDetailsLoader _detailsLoader = AdminLedgerDetailsLoader();
  final Set<String> _expandedIds = {};

  double get balance => widget.balance;
  double get totalFees => widget.totalFees;
  double get activeEscrow => widget.activeEscrow;

  void _toggleExpanded(String entryId, Map<String, dynamic> data) {
    final willExpand = !_expandedIds.contains(entryId);
    setState(() {
      if (willExpand) {
        _expandedIds.add(entryId);
      } else {
        _expandedIds.remove(entryId);
      }
    });
    if (willExpand) {
      _detailsLoader.ensureLoaded(data, () {
        if (mounted) setState(() {});
      });
    }
  }

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
                            color: Color(0xFF98259A),
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
                            const Color(0xFF98259A),
                            Icons.pie_chart,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            'Active Escrow',
                            _formatAmount(activeEscrow),
                            const Color(0xFF98259A),
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
                          'Recent Admin Ledger Activity',
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
                          label: const Text('Full Ledger', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Live ledger transactions stream
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
                                  final raw = d.data() as Map<String, dynamic>;
                                  final rentalId =
                                      (raw['rentalId'] as String?) ?? d.id;
                                  final feeAmt =
                                      (raw['amount'] as num?)?.toDouble() ?? 0.0;
                                  final grossAmt =
                                      (raw['grossAmount'] as num?)?.toDouble() ??
                                          (feeAmt * 10);
                                  final entryId = 'fee_$rentalId';
                                  final data = <String, dynamic>{
                                    ...raw,
                                    'id': entryId,
                                    'type': 'service_fee',
                                    'amount': feeAmt,
                                    'grossAmount': grossAmt,
                                    'payoutAmount':
                                        (raw['payoutAmount'] as num?)?.toDouble() ??
                                            (grossAmt - feeAmt),
                                    'referenceId': rentalId,
                                    'rentalId': rentalId,
                                    'itemName': raw['itemName'] ?? 'Rental Item',
                                    'status': raw['status'] ?? 'completed',
                                    'createdAt': raw['timestamp'],
                                  };
                                  return _buildLedgerItem(entryId, data);
                                }).toList(),
                              );
                            },
                          );
                        }

                        return Column(
                          children: docs.map((d) {
                            final data = Map<String, dynamic>.from(
                                d.data() as Map<String, dynamic>);
                            data['id'] = d.id;
                            return _buildLedgerItem(d.id, data);
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

  Widget _buildLedgerItem(String entryId, Map<String, dynamic> data) {
    final lenderId = (data['lenderId'] as String?) ?? '';
    final borrowerId = (data['borrowerId'] as String?) ?? '';
    final rentalId =
        (data['referenceId'] as String?) ?? (data['rentalId'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AdminLedgerTransactionCard(
        key: ValueKey(entryId),
        data: data,
        isExpanded: _expandedIds.contains(entryId),
        onTap: () => _toggleExpanded(entryId, data),
        lenderInfo: _detailsLoader.getUser(lenderId),
        borrowerInfo: _detailsLoader.getUser(borrowerId),
        rentalInfo: _detailsLoader.getRental(rentalId),
        isLoadingDetails: _detailsLoader.isLoadingFor(data),
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

