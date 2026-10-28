import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminWalletPage extends StatelessWidget {
  const AdminWalletPage({super.key});

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
          'Admin Wallet & Revenue',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF007799),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: db.collection('admin_wallet').doc('main').snapshots(),
        builder: (context, walletSnap) {
          final walletData = walletSnap.data?.data() as Map<String, dynamic>? ?? {};
          final double balance = (walletData['balance'] as num?)?.toDouble() ?? 0.0;
          final double totalCommission =
              (walletData['totalCommission'] as num?)?.toDouble() ?? 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Revenue Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Wallet Balance',
                        value: _formatCurrency(balance),
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFF27AE60),
                        subtitle: 'Current ORC reserves',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Commission',
                        value: _formatCurrency(totalCommission),
                        icon: Icons.pie_chart_rounded,
                        color: const Color(0xFF007799),
                        subtitle: '10% on settled rentals',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Platform fee notice
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF007799).withValues(alpha: 0.2)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF007799), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Commission Rules: 10% platform fee is credited to Admin Wallet only upon successful rental completion. Pending or cancelled rentals are never credited.',
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Commission History Section
                const Text(
                  'Settled Commission History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),

                StreamBuilder<QuerySnapshot>(
                  stream: db
                      .collection('admin_wallet')
                      .doc('main')
                      .collection('commissions')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, commSnap) {
                    if (commSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: Color(0xFF007799)),
                        ),
                      );
                    }

                    final docs = commSnap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return _buildEmptyHistory();
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return _buildCommissionTile(data);
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
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
              fontSize: 20,
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

  Widget _buildCommissionTile(Map<String, dynamic> data) {
    final num amount = data['amount'] ?? 0;
    final num gross = data['grossAmount'] ?? (amount * 10);
    final String rentalId = data['rentalId'] ?? 'N/A';
    final String lenderId = data['lenderId'] ?? '';
    final String borrowerId = data['borrowerId'] ?? '';

    DateTime? date;
    if (data['timestamp'] is Timestamp) {
      date = (data['timestamp'] as Timestamp).toDate();
    }

    final formattedDate = date != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(date)
        : 'Recent';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF27AE60).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.monetization_on_outlined,
                color: Color(0xFF27AE60), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Rental Settlement',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF27AE60).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '10% FEE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF27AE60),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Rental: $rentalId',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
                if (lenderId.isNotEmpty || borrowerId.isNotEmpty)
                  Text(
                    'Lender: ${lenderId.length > 8 ? lenderId.substring(0, 8) : lenderId}... | Borrower: ${borrowerId.length > 8 ? borrowerId.substring(0, 8) : borrowerId}...',
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${_formatCurrency(amount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF27AE60),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Gross: ${_formatCurrency(gross)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
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
            'No commission history yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Platform commissions will automatically record here when rentals are completed and settled.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
