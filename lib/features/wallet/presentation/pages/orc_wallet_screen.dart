import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/entities/wallet_transaction.dart';
import '../../data/repositories/wallet_repository.dart';
import '../widgets/cash_in_dialog.dart';

class OrcWalletScreen extends StatefulWidget {
  const OrcWalletScreen({super.key});

  @override
  State<OrcWalletScreen> createState() => _OrcWalletScreenState();
}

class _OrcWalletScreenState extends State<OrcWalletScreen> {
  final WalletRepository _repository = WalletRepository();
  String _selectedFilter = 'all'; // 'all', 'cash_in', 'escrow', 'earning', 'refund'

  String _formatCurrency(double amount) {
    return '₱${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view your wallet.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A2E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ORC Wallet',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF7B40B5)),
            tooltip: 'About ORC Wallet',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<Wallet>(
        stream: _repository.getWalletStream(user.uid),
        builder: (context, walletSnapshot) {
          final wallet = walletSnapshot.data ?? Wallet(userId: user.uid);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main Balance Card
                _buildBalanceCard(context, wallet),

                const SizedBox(height: 24),

                // Transaction History Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Transaction History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Rate: ₱1 = 1 ORC',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Filter Pills
                _buildFilterChips(),

                const SizedBox(height: 14),

                // Transactions List
                StreamBuilder<List<WalletTransaction>>(
                  stream: _repository.getTransactionsStream(user.uid),
                  builder: (context, txSnapshot) {
                    if (txSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
                        ),
                      );
                    }

                    final allTx = txSnapshot.data ?? [];
                    final filteredTx = _filterTransactions(allTx);

                    if (filteredTx.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTx.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _buildTransactionTile(filteredTx[index]);
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, Wallet wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B40B5).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Available Balance',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Escrow Protected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Available balance text
          Text(
            _formatCurrency(wallet.availableBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),

          const SizedBox(height: 16),

          // Secondary balances & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // In Escrow info
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_clock,
                        color: Colors.amber[200],
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Locked in Escrow',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCurrency(wallet.escrowBalance),
                    style: TextStyle(
                      color: Colors.amber[200],
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Cash In Button
              ElevatedButton.icon(
                onPressed: () => CashInDialog.show(context),
                icon: const Icon(Icons.add, size: 18, color: Color(0xFF7B40B5)),
                label: const Text(
                  'Cash In',
                  style: TextStyle(
                    color: Color(0xFF7B40B5),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': 'All'},
      {'key': 'cash_in', 'label': 'Cash In'},
      {'key': 'escrow', 'label': 'Escrow'},
      {'key': 'earning', 'label': 'Earnings'},
      {'key': 'refund', 'label': 'Refunds'},
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
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = f['key']!);
              },
              selectedColor: const Color(0xFF7B40B5),
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF7B40B5) : Colors.grey[300]!,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<WalletTransaction> _filterTransactions(List<WalletTransaction> list) {
    if (_selectedFilter == 'all') return list;
    if (_selectedFilter == 'cash_in') {
      return list.where((t) => t.type == 'cash_in').toList();
    }
    if (_selectedFilter == 'escrow') {
      return list
          .where((t) => t.type == 'rental_escrow' || t.type == 'rental_payment')
          .toList();
    }
    if (_selectedFilter == 'earning') {
      return list.where((t) => t.type == 'rental_earning').toList();
    }
    if (_selectedFilter == 'refund') {
      return list.where((t) => t.type == 'rental_refund').toList();
    }
    return list;
  }

  Widget _buildTransactionTile(WalletTransaction tx) {
    Color iconBg;
    Color iconColor;
    IconData icon;
    String displayTitle;

    switch (tx.type) {
      case 'cash_in':
        icon = Icons.add_card;
        iconBg = const Color(0xFF2ECC71).withValues(alpha: 0.12);
        iconColor = const Color(0xFF2ECC71);
        displayTitle = 'Stripe Cash-In';
        break;
      case 'rental_escrow':
        icon = Icons.lock_outline;
        iconBg = const Color(0xFFE67E22).withValues(alpha: 0.12);
        iconColor = const Color(0xFFE67E22);
        displayTitle = 'Escrow Hold';
        break;
      case 'rental_earning':
        icon = Icons.trending_up;
        iconBg = const Color(0xFF27AE60).withValues(alpha: 0.12);
        iconColor = const Color(0xFF27AE60);
        displayTitle = 'Rental Earnings (90%)';
        break;
      case 'rental_refund':
        icon = Icons.undo;
        iconBg = const Color(0xFF3498DB).withValues(alpha: 0.12);
        iconColor = const Color(0xFF3498DB);
        displayTitle = 'Escrow Refund';
        break;
      case 'rental_payment':
        icon = Icons.check_circle_outline;
        iconBg = const Color(0xFF7B40B5).withValues(alpha: 0.12);
        iconColor = const Color(0xFF7B40B5);
        displayTitle = 'Rental Settled';
        break;
      default:
        icon = Icons.account_balance_wallet_outlined;
        iconBg = Colors.grey.withValues(alpha: 0.12);
        iconColor = Colors.grey;
        displayTitle = 'Transaction';
    }

    final formattedDate = tx.createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(tx.createdAt!)
        : 'Just now';

    final isPositive = tx.amount > 0;
    final amountPrefix = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tx.description ?? formattedDate,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix${_formatCurrency(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isPositive ? const Color(0xFF27AE60) : const Color(0xFFE74C3C),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tx.status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
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

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 54, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text(
            'No transactions yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Cash in ORC credits or borrow items to start!',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF7B40B5)),
            SizedBox(width: 8),
            Text('How ORC Escrow Works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• ₱1 PHP = 1 ORC Credit.\n'
              '• When a lender accepts your rental request, the rental total is securely held in escrow.\n'
              '• Funds remain locked until the rental is successfully returned and confirmed.\n'
              '• Upon completion, 90% is released to the lender and 10% platform fee is deducted.\n'
              '• If a rental is cancelled or denied, your held funds are immediately refunded to your available balance.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Color(0xFF7B40B5), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
