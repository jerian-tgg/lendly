import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shared helper that lazily fetches and caches user profiles and rental
/// conversation records when an admin ledger transaction card is expanded.
class AdminLedgerDetailsLoader {
  AdminLedgerDetailsLoader({FirebaseFirestore? firestore})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  final Map<String, Map<String, dynamic>?> userCache = {};
  final Map<String, Map<String, dynamic>?> rentalCache = {};
  final Set<String> _loadingUsers = {};
  final Set<String> _loadingRentals = {};

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  bool isLoadingFor(Map<String, dynamic> data) {
    final lenderId = (data['lenderId'] as String?) ?? '';
    final borrowerId = (data['borrowerId'] as String?) ?? '';
    final rentalId =
        (data['referenceId'] as String?) ?? (data['rentalId'] as String?) ?? '';

    return (lenderId.isNotEmpty && _loadingUsers.contains(lenderId)) ||
        (borrowerId.isNotEmpty && _loadingUsers.contains(borrowerId)) ||
        (rentalId.isNotEmpty && _loadingRentals.contains(rentalId));
  }

  Map<String, dynamic>? getUser(String userId) =>
      userId.isEmpty ? null : userCache[userId];

  Map<String, dynamic>? getRental(String rentalId) =>
      rentalId.isEmpty ? null : rentalCache[rentalId];

  Future<void> ensureLoaded(
    Map<String, dynamic> data,
    VoidCallback onUpdated,
  ) async {
    final lenderId = (data['lenderId'] as String?) ?? '';
    final borrowerId = (data['borrowerId'] as String?) ?? '';
    final rentalId =
        (data['referenceId'] as String?) ?? (data['rentalId'] as String?) ?? '';

    final futures = <Future<void>>[];

    if (lenderId.isNotEmpty &&
        !userCache.containsKey(lenderId) &&
        !_loadingUsers.contains(lenderId)) {
      _loadingUsers.add(lenderId);
      futures.add(_fetchUser(lenderId));
    }

    if (borrowerId.isNotEmpty &&
        borrowerId != lenderId &&
        !userCache.containsKey(borrowerId) &&
        !_loadingUsers.contains(borrowerId)) {
      _loadingUsers.add(borrowerId);
      futures.add(_fetchUser(borrowerId));
    }

    if (rentalId.isNotEmpty &&
        !rentalCache.containsKey(rentalId) &&
        !_loadingRentals.contains(rentalId)) {
      _loadingRentals.add(rentalId);
      futures.add(_fetchRental(rentalId));
    }

    if (futures.isEmpty) return;

    onUpdated();
    await Future.wait(futures);
    onUpdated();
  }

  Future<void> _fetchUser(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (doc.exists) {
        userCache[userId] = doc.data();
      } else if (userId.contains('@')) {
        final query = await _db
            .collection('users')
            .where('email', isEqualTo: userId)
            .limit(1)
            .get();
        userCache[userId] =
            query.docs.isNotEmpty ? query.docs.first.data() : null;
      } else {
        userCache[userId] = null;
      }
    } catch (_) {
      userCache[userId] = null;
    } finally {
      _loadingUsers.remove(userId);
    }
  }

  Future<void> _fetchRental(String rentalId) async {
    try {
      final doc = await _db.collection('conversations').doc(rentalId).get();
      rentalCache[rentalId] = doc.exists ? doc.data() : null;
    } catch (_) {
      rentalCache[rentalId] = null;
    } finally {
      _loadingRentals.remove(rentalId);
    }
  }
}

/// Expandable transaction history card for the Admin Wallet & Transaction Ledger.
class AdminLedgerTransactionCard extends StatelessWidget {
  const AdminLedgerTransactionCard({
    super.key,
    required this.data,
    required this.isExpanded,
    required this.onTap,
    this.lenderInfo,
    this.borrowerInfo,
    this.rentalInfo,
    this.isLoadingDetails = false,
  });

  final Map<String, dynamic> data;
  final bool isExpanded;
  final VoidCallback onTap;
  final Map<String, dynamic>? lenderInfo;
  final Map<String, dynamic>? borrowerInfo;
  final Map<String, dynamic>? rentalInfo;
  final bool isLoadingDetails;

  static DateTime? parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  static String formatCurrency(num amount) {
    return '₱${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String _shortId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}...';
  }

  String _formatUserSummary(String id, Map<String, dynamic>? info) {
    if (info != null) {
      final first = (info['firstName'] as String?)?.trim() ?? '';
      final last = (info['lastName'] as String?)?.trim() ?? '';
      final fullName = '$first $last'.trim();
      if (fullName.isNotEmpty) return fullName;
      final displayName = (info['displayName'] as String?)?.trim() ?? '';
      if (displayName.isNotEmpty) return displayName;
      final email = (info['email'] as String?)?.trim() ?? '';
      if (email.isNotEmpty) return email;
    }
    return _shortId(id);
  }

  String _formatUserFull(String id, Map<String, dynamic>? info) {
    if (id.isEmpty) return 'N/A';
    if (info == null) return id;

    final first = (info['firstName'] as String?)?.trim() ?? '';
    final last = (info['lastName'] as String?)?.trim() ?? '';
    final fullName = '$first $last'.trim();
    final displayName = (info['displayName'] as String?)?.trim() ?? '';
    final name = fullName.isNotEmpty ? fullName : displayName;
    final email = (info['email'] as String?)?.trim() ?? '';

    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name ($email)';
    }
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return id;
  }

  void _copyText(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String txId = (data['id'] as String?) ?? 'N/A';
    final String type = (data['type'] as String?) ?? 'service_fee';
    final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final bool isFeeType = type == 'service_fee' || type == 'platform_fee';
    final bool isPayoutType = type == 'lender_payout' || type == 'user_payout';
    final double gross = (data['grossAmount'] as num?)?.toDouble() ??
        (isFeeType && amount > 0 ? amount * 10 : amount);
    final String rentalId =
        (data['referenceId'] as String?) ?? (data['rentalId'] as String?) ?? 'N/A';
    final String itemId =
        (data['itemId'] as String?) ?? (rentalInfo?['itemId'] as String?) ?? '';
    final String itemName = (data['itemName'] as String?) ??
        (rentalInfo?['itemName'] as String?) ??
        'Rental Item';
    final String lenderId = (data['lenderId'] as String?) ??
        (rentalInfo?['itemOwnerId'] as String?) ??
        (rentalInfo?['ownerId'] as String?) ??
        '';
    final String borrowerId = (data['borrowerId'] as String?) ??
        (rentalInfo?['borrowerId'] as String?) ??
        '';
    final String status =
        ((data['status'] as String?) ?? 'completed').toUpperCase();
    final String description = (data['description'] as String?)?.trim() ?? '';

    final DateTime? primaryDate =
        parseDate(data['createdAt'] ?? data['timestamp'] ?? data['settledAt']);
    final String formattedDate = primaryDate != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(primaryDate)
        : 'Recent';

    final IconData icon;
    final Color accentColor;
    final String title;
    final String badgeText;
    final String typeLabel;
    final String amountPrefix;

    switch (type) {
      case 'escrow_hold':
        icon = Icons.lock_clock_outlined;
        accentColor = const Color(0xFF98259A);
        title = 'Escrow Hold ($itemName)';
        badgeText = status == 'SETTLED'
            ? 'HOLD SETTLED'
            : (status == 'REFUNDED' ? 'HOLD REFUNDED' : 'ESCROW HOLD');
        typeLabel = 'Escrow Hold';
        amountPrefix = '';
        break;
      case 'lender_payout':
      case 'user_payout':
        icon = Icons.payments_outlined;
        accentColor = const Color(0xFF98259A);
        title = 'User Payout ($itemName)';
        badgeText = '90% PAYOUT';
        typeLabel = '90% Lender Payout';
        amountPrefix = '';
        break;
      case 'escrow_refund':
        icon = Icons.undo_rounded;
        accentColor = const Color(0xFFE67E22);
        title = 'Escrow Refund ($itemName)';
        badgeText = 'REFUNDED';
        typeLabel = 'Escrow Refund';
        amountPrefix = '';
        break;
      case 'service_fee':
      case 'platform_fee':
      default:
        icon = Icons.monetization_on_outlined;
        accentColor = const Color(0xFF27AE60);
        title = 'Commission Collected ($itemName)';
        badgeText = '10% FEE';
        typeLabel = '10% Platform Commission';
        amountPrefix = '+';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? accentColor.withValues(alpha: 0.45)
              : accentColor.withValues(alpha: 0.15),
          width: isExpanded ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? accentColor.withValues(alpha: 0.08)
                : Colors.black12,
            blurRadius: isExpanded ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Header Row (always visible)
                Row(
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
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
                          if (description.isNotEmpty)
                            Text(
                              description,
                              maxLines: isExpanded ? null : 2,
                              overflow: isExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black87),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            'Rental ID: $rentalId',
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (lenderId.isNotEmpty || borrowerId.isNotEmpty)
                            Text(
                              'Lender: ${_formatUserSummary(lenderId, lenderInfo)}  •  Borrower: ${_formatUserSummary(borrowerId, borrowerInfo)}',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$amountPrefix${formatCurrency(amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Gross: ${formatCurrency(gross)}',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
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
                            const SizedBox(width: 4),
                            AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                // Expanded Full Transaction Details Section
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? _buildExpandedDetails(
                          context: context,
                          txId: txId,
                          type: type,
                          typeLabel: typeLabel,
                          isFeeType: isFeeType,
                          isPayoutType: isPayoutType,
                          amount: amount,
                          amountPrefix: amountPrefix,
                          gross: gross,
                          rentalId: rentalId,
                          itemId: itemId,
                          itemName: itemName,
                          lenderId: lenderId,
                          borrowerId: borrowerId,
                          status: status,
                          accentColor: accentColor,
                          primaryDate: primaryDate,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails({
    required BuildContext context,
    required String txId,
    required String type,
    required String typeLabel,
    required bool isFeeType,
    required bool isPayoutType,
    required double amount,
    required String amountPrefix,
    required double gross,
    required String rentalId,
    required String itemId,
    required String itemName,
    required String lenderId,
    required String borrowerId,
    required String status,
    required Color accentColor,
    required DateTime? primaryDate,
  }) {
    final double? commissionAmt = isFeeType
        ? amount
        : (data['commissionAmount'] as num?)?.toDouble() ??
            (isPayoutType || (type == 'escrow_hold' && status == 'SETTLED')
                ? ((gross * 0.10) * 100).round() / 100.0
                : null);
    final double? payoutAmt = isPayoutType
        ? amount
        : (data['payoutAmount'] as num?)?.toDouble() ??
            (isFeeType || (type == 'escrow_hold' && status == 'SETTLED')
                ? ((gross - (commissionAmt ?? 0.0)) * 100).round() / 100.0
                : null);

    final DateTime? acceptedAt = parseDate(rentalInfo?['acceptedAt']);
    final DateTime? settledAt =
        parseDate(data['settledAt'] ?? rentalInfo?['settledAt']);
    final DateTime? refundedAt =
        parseDate(data['refundedAt'] ?? rentalInfo?['refundedAt']);
    final DateTime? startDate = parseDate(rentalInfo?['startDate']);
    final DateTime? endDate = parseDate(rentalInfo?['endDate']);
    final int? totalDays = (rentalInfo?['totalDays'] as num?)?.toInt();
    final String? cancelReason = (data['refundReason'] as String?) ??
        (rentalInfo?['refundReason'] as String?) ??
        (rentalInfo?['cancelReason'] as String?);
    final String? rentalEscrowStatus = rentalInfo?['escrowStatus'] as String?;

    final fullDateFmt = DateFormat('MMM d, yyyy • h:mm:ss a');
    final shortDateFmt = DateFormat('MMM d, yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(height: 1, color: accentColor.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'FULL TRANSACTION DETAILS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: accentColor,
                    ),
                  ),
                  if (isLoadingDetails)
                    Row(
                      children: [
                        SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Loading info...',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Financial Breakdown
              _buildSectionHeader('Financial Breakdown'),
              _buildDetailRow(
                'Ledger Entry Amount',
                '$amountPrefix${formatCurrency(amount)} ORC',
                valueColor: accentColor,
                isBold: true,
              ),
              _buildDetailRow(
                'Gross Rental Amount',
                '${formatCurrency(gross)} ORC',
              ),
              if (payoutAmt != null)
                _buildDetailRow(
                  '90% Lender Payout',
                  '${formatCurrency(payoutAmt)} ORC',
                ),
              if (commissionAmt != null)
                _buildDetailRow(
                  '10% Platform Commission',
                  '${formatCurrency(commissionAmt)} ORC',
                ),

              const SizedBox(height: 10),
              _buildSectionHeader('Transaction & Item Info'),
              _buildDetailRow(
                'Transaction ID',
                txId,
                onCopy: txId != 'N/A'
                    ? () => _copyText(context, 'Transaction ID', txId)
                    : null,
              ),
              _buildDetailRow('Ledger Type', '$typeLabel ($type)'),
              _buildDetailRow('Status', status),
              _buildDetailRow(
                'Rental / Reference ID',
                rentalId,
                onCopy: rentalId != 'N/A'
                    ? () => _copyText(context, 'Rental ID', rentalId)
                    : null,
              ),
              _buildDetailRow('Item Name', itemName),
              if (itemId.isNotEmpty)
                _buildDetailRow(
                  'Item ID',
                  itemId,
                  onCopy: () => _copyText(context, 'Item ID', itemId),
                ),
              if (rentalEscrowStatus != null && rentalEscrowStatus.isNotEmpty)
                _buildDetailRow(
                  'Rental Escrow State',
                  rentalEscrowStatus.toUpperCase(),
                ),
              if (cancelReason != null && cancelReason.trim().isNotEmpty)
                _buildDetailRow('Reason / Notes', cancelReason.trim()),

              if (lenderId.isNotEmpty || borrowerId.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildSectionHeader('Parties Involved'),
                if (lenderId.isNotEmpty) ...[
                  _buildDetailRow(
                    'Lender',
                    _formatUserFull(lenderId, lenderInfo),
                  ),
                  _buildDetailRow(
                    'Lender UID',
                    lenderId,
                    onCopy: () => _copyText(context, 'Lender UID', lenderId),
                  ),
                ],
                if (borrowerId.isNotEmpty) ...[
                  _buildDetailRow(
                    'Borrower',
                    _formatUserFull(borrowerId, borrowerInfo),
                  ),
                  _buildDetailRow(
                    'Borrower UID',
                    borrowerId,
                    onCopy: () =>
                        _copyText(context, 'Borrower UID', borrowerId),
                  ),
                ],
              ],

              const SizedBox(height: 10),
              _buildSectionHeader('Timeline & Schedule'),
              _buildDetailRow(
                'Logged At',
                primaryDate != null ? fullDateFmt.format(primaryDate) : 'Pending',
              ),
              if (acceptedAt != null)
                _buildDetailRow(
                  'Rental Accepted',
                  fullDateFmt.format(acceptedAt),
                ),
              if (startDate != null && endDate != null)
                _buildDetailRow(
                  'Rental Period',
                  '${shortDateFmt.format(startDate)} – ${shortDateFmt.format(endDate)}'
                      '${totalDays != null && totalDays > 0 ? ' ($totalDays day${totalDays == 1 ? '' : 's'})' : ''}',
                )
              else if (totalDays != null && totalDays > 0)
                _buildDetailRow(
                  'Rental Duration',
                  '$totalDays day${totalDays == 1 ? '' : 's'}',
                ),
              if (settledAt != null)
                _buildDetailRow(
                  'Settled At',
                  fullDateFmt.format(settledAt),
                ),
              if (refundedAt != null)
                _buildDetailRow(
                  'Refunded At',
                  fullDateFmt.format(refundedAt),
                ),
              if (rentalInfo != null) _buildRentalProgressRow(rentalInfo!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: valueColor ?? Colors.black87,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          if (onCopy != null)
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.only(left: 6, top: 1, bottom: 1),
                child: Icon(
                  Icons.copy_rounded,
                  size: 13,
                  color: Colors.black45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRentalProgressRow(Map<String, dynamic> rental) {
    final stages = <String>[
      if (rental['approved'] == true) 'Approved',
      if (rental['isPaid'] == true) 'Paid',
      if (rental['isReceived'] == true) 'Received',
      if (rental['isReturned'] == true) 'Returned',
      if (rental['isReturnConfirmed'] == true) 'Confirmed',
      if (rental['cancelled'] == true || rental['denied'] == true) 'Cancelled',
    ];
    if (stages.isEmpty) return const SizedBox.shrink();

    return _buildDetailRow('Rental Milestones', stages.join(' → '));
  }
}
