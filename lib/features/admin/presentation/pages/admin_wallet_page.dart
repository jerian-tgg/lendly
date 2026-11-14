import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/wallet/data/repositories/wallet_repository.dart';

class AdminWalletPage extends StatefulWidget {
  const AdminWalletPage({super.key});

  @override
  State<AdminWalletPage> createState() => _AdminWalletPageState();
}

class _AdminWalletPageState extends State<AdminWalletPage> {
  static const String adminEmail = WalletRepository.adminEmail;

  final WalletRepository _walletRepository = WalletRepository();
  String _selectedFilter = 'all'; // 'all', 'service_fee', 'escrow_hold', 'lender_payout', 'escrow_refund'
  bool _reconciling = false;

  @override
  void initState() {
    super.initState();
    _triggerReconcile();
  }

  Future<void> _triggerReconcile() async {
    if (_reconciling) return;
    setState(() => _reconciling = true);
    try {
      await _walletRepository.reconcileRentalsAndAdminLedger();
    } finally {
      if (mounted) {
        setState(() => _reconciling = false);
      }
    }
  }

  String _formatCurrency(num amount) {
    return '₱${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'Admin Wallet & Transaction Ledger',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
        ),
        backgroundColor: const Color(0xFF98259A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _reconciling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, color: Colors.white),
            tooltip: 'Sync & Reconcile Ledger',
            onPressed: _reconciling ? null : _triggerReconcile,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: db.collection('wallets').doc(adminEmail).snapshots(),
        builder: (context, dedicatedSnap) {
          return StreamBuilder<DocumentSnapshot>(
            stream: db.collection('admin_wallet').doc('main').snapshots(),
            builder: (context, legacySnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: db
                    .collection('conversations')
                    .where('escrowStatus', isEqualTo: 'held')
                    .snapshots(),
                builder: (context, escrowSnap) {
                  final dedicatedData =
                      dedicatedSnap.data?.data() as Map<String, dynamic>? ?? {};
                  final legacyData =
                      legacySnap.data?.data() as Map<String, dynamic>? ?? {};

                  double balance = (dedicatedData['balance'] as num?)?.toDouble() ??
                      (dedicatedData['availableBalance'] as num?)?.toDouble() ??
                      0.0;
                  if (balance == 0.0) {
                    balance = (legacyData['balance'] as num?)?.toDouble() ?? 0.0;
                  }

                  double totalCommission =
                      (dedicatedData['totalFeesCollected'] as num?)?.toDouble() ??
                          (dedicatedData['totalCommission'] as num?)?.toDouble() ??
                          0.0;
                  if (totalCommission == 0.0) {
                    totalCommission =
                        (legacyData['totalCommission'] as num?)?.toDouble() ?? 0.0;
                  }

                  double totalPayouts =
                      (dedicatedData['totalPayoutsProcessed'] as num?)?.toDouble() ??
                          (legacyData['totalPayoutsProcessed'] as num?)?.toDouble() ??
                          0.0;
                  if (totalPayouts == 0.0 && totalCommission > 0) {
                    totalPayouts = ((totalCommission * 9) * 100).round() / 100.0;
                  }

                  double activeEscrowVolume = 0.0;
                  int activeEscrowCount = 0;
                  if (escrowSnap.hasData) {
                    for (final doc in escrowSnap.data!.docs) {
                      final d = doc.data() as Map<String, dynamic>? ?? {};
                      if (d['conversationType'] == 'appraisal') continue;
                      final amt = (d['escrowAmount'] as num?)?.toDouble() ?? 0.0;
                      if (amt > 0) {
                        activeEscrowVolume += amt;
                        activeEscrowCount++;
                      }
                    }
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Admin Balance & Total 10% Commission
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Admin Balance',
                                value: _formatCurrency(balance),
                                icon: Icons.account_balance_wallet_rounded,
                                color: const Color(0xFF27AE60),
                                subtitle: 'Available ORC reserves',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: '10% Commissions',
                                value: _formatCurrency(totalCommission),
                                icon: Icons.pie_chart_rounded,
                                color: const Color(0xFF98259A),
                                subtitle: 'Collected platform fees',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Row 2: Active Escrow Holds & 90% Lender Payouts
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Active Escrow',
                                value: _formatCurrency(activeEscrowVolume),
                                icon: Icons.lock_clock_rounded,
                                color: const Color(0xFF98259A),
                                subtitle: '$activeEscrowCount active hold(s)',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'User Payouts (90%)',
                                value: _formatCurrency(totalPayouts),
                                icon: Icons.payments_rounded,
                                color: const Color(0xFFE67E22),
                                subtitle: 'Transferred to lenders',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Platform fee & escrow audit notice
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF98259A).withValues(alpha: 0.2),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user_outlined,
                                  color: Color(0xFF98259A), size: 22),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Complete Escrow & Payout Ledger: Logs every ORC escrow hold when a borrow request is accepted, the 90% lender payout upon item return, and the 10% platform commission credited to the Admin Wallet.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                      height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Ledger Header
                        const Text(
                          'Complete Transaction History Ledger',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Filter Chips
                        _buildFilterChips(),

                        const SizedBox(height: 14),

                        // Unified Ledger Stream
                        StreamBuilder<QuerySnapshot>(
                          stream: db
                              .collection('wallets')
                              .doc(adminEmail)
                              .collection('transactions')
                              .snapshots(),
                          builder: (context, txSnap) {
                            return StreamBuilder<QuerySnapshot>(
                              stream: db
                                  .collection('admin_wallet')
                                  .doc('main')
                                  .collection('commissions')
                                  .snapshots(),
                              builder: (context, commSnap) {
                                if (txSnap.connectionState == ConnectionState.waiting &&
                                    !txSnap.hasData) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: CircularProgressIndicator(
                                          color: Color(0xFF98259A)),
                                    ),
                                  );
                                }

                                final entries = _mergeLedgerEntries(
                                  txSnap.data?.docs ?? const [],
                                  commSnap.data?.docs ?? const [],
                                );

                                final filtered = _filterEntries(entries);

                                if (filtered.isEmpty) {
                                  return _buildEmptyHistory();
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    return _buildLedgerTile(filtered[index]);
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': 'All Ledger'},
      {'key': 'service_fee', 'label': '10% Commissions'},
      {'key': 'escrow_hold', 'label': 'Escrow Holds'},
      {'key': 'lender_payout', 'label': 'User Payouts (90%)'},
      {'key': 'escrow_refund', 'label': 'Refunds'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedFilter = f['key']!);
                }
              },
              selectedColor: const Color(0xFF98259A),
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF98259A)
                      : Colors.grey.shade300,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _mergeLedgerEntries(
    List<QueryDocumentSnapshot> txDocs,
    List<QueryDocumentSnapshot> legacyCommDocs,
  ) {
    final Map<String, Map<String, dynamic>> byId = {};

    for (final doc in txDocs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['id'] = doc.id;
      byId[doc.id] = data;
    }

    // Backfill from legacy commissions if any commission wasn't in txDocs
    for (final doc in legacyCommDocs) {
      final d = Map<String, dynamic>.from(doc.data() as Map);
      final rentalId = (d['rentalId'] as String?) ?? doc.id;
      final feeKey = 'fee_$rentalId';
      if (!byId.containsKey(feeKey)) {
        final feeAmt = (d['amount'] as num?)?.toDouble() ?? 0.0;
        final grossAmt = (d['grossAmount'] as num?)?.toDouble() ?? (feeAmt * 10);
        byId[feeKey] = {
          'id': feeKey,
          'type': 'service_fee',
          'amount': feeAmt,
          'grossAmount': grossAmt,
          'payoutAmount': grossAmt - feeAmt,
          'referenceId': rentalId,
          'rentalId': rentalId,
          'itemName': d['itemName'] ?? 'Rental Item',
          'lenderId': d['lenderId'] ?? '',
          'borrowerId': d['borrowerId'] ?? '',
          'status': 'completed',
          'timestamp': d['timestamp'],
          'createdAt': d['timestamp'],
        };
      }
    }

    final list = byId.values.toList();
    list.sort((a, b) {
      final tsA = _extractDate(a);
      final tsB = _extractDate(b);
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      return tsB.compareTo(tsA);
    });
    return list;
  }

  List<Map<String, dynamic>> _filterEntries(List<Map<String, dynamic>> entries) {
    if (_selectedFilter == 'all') return entries;
    return entries.where((e) => e['type'] == _selectedFilter).toList();
  }

  DateTime? _extractDate(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['timestamp'] ?? data['settledAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTile(Map<String, dynamic> data) {
    final String type = (data['type'] as String?) ?? 'service_fee';
    final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final double gross = (data['grossAmount'] as num?)?.toDouble() ??
        (type == 'service_fee' && amount > 0 ? amount * 10 : amount);
    final String rentalId =
        (data['referenceId'] as String?) ?? (data['rentalId'] as String?) ?? 'N/A';
    final String itemName = (data['itemName'] as String?) ?? 'Rental Item';
    final String lenderId = (data['lenderId'] as String?) ?? '';
    final String borrowerId = (data['borrowerId'] as String?) ?? '';
    final String status = ((data['status'] as String?) ?? 'completed').toUpperCase();

    final date = _extractDate(data);
    final formattedDate = date != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(date)
        : 'Recent';

    IconData icon;
    Color accentColor;
    String title;
    String badgeText;
    String amountPrefix;

    switch (type) {
      case 'escrow_hold':
        icon = Icons.lock_clock_outlined;
        accentColor = const Color(0xFF98259A);
        title = 'Escrow Hold ($itemName)';
        badgeText = status == 'SETTLED' ? 'HOLD SETTLED' : 'ESCROW HOLD';
        amountPrefix = '';
        break;
      case 'lender_payout':
        icon = Icons.payments_outlined;
        accentColor = const Color(0xFF98259A);
        title = 'User Payout ($itemName)';
        badgeText = '90% PAYOUT';
        amountPrefix = '';
        break;
      case 'escrow_refund':
        icon = Icons.undo_rounded;
        accentColor = const Color(0xFFE67E22);
        title = 'Escrow Refund ($itemName)';
        badgeText = 'REFUNDED';
        amountPrefix = '';
        break;
      case 'service_fee':
      default:
        icon = Icons.monetization_on_outlined;
        accentColor = const Color(0xFF27AE60);
        title = 'Commission Collected ($itemName)';
        badgeText = '10% FEE';
        amountPrefix = '+';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (data['description'] != null)
                  Text(
                    data['description'].toString(),
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                const SizedBox(height: 3),
                Text(
                  'Rental ID: $rentalId',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
                if (lenderId.isNotEmpty || borrowerId.isNotEmpty)
                  Text(
                    'Lender: ${lenderId.length > 8 ? lenderId.substring(0, 8) : lenderId}...  •  Borrower: ${borrowerId.length > 8 ? borrowerId.substring(0, 8) : borrowerId}...',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix${_formatCurrency(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Gross: ${_formatCurrency(gross)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text(
            'No ledger transactions match this filter',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Escrow holds, 90% user payouts, and 10% platform commissions are automatically logged here.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

