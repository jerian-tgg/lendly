import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lendly/core/utils/image_utils.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/features/items/presentation/pages/contract_service.dart';
import 'package:lendly/features/items/presentation/pages/electronic_contract_page.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isCompleted(Map<String, dynamic> data) =>
      data['isPaid'] == true &&
      data['isReceived'] == true &&
      data['isReturned'] == true &&
      data['isReturnConfirmed'] == true;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Not logged in.'));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transactions',
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              'Official Activity Records • View Only',
              style: TextStyle(
                color: Colors.black45,
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF98259A),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF98259A),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Borrow'),
            Tab(text: 'Lend'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .where('participants', arrayContains: currentUser.uid)
            .where('approved', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF98259A)),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final allDocs = snapshot.data!.docs;
          // Exclude appraisal coordination chats from rental transactions
          final docs = allDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['conversationType'] != 'appraisal';
          }).toList();

          final borrow = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final isLender = data['lenderId'] == currentUser.uid ||
                data['ownerId'] == currentUser.uid;
            return !_isCompleted(data) && !isLender;
          }).toList();

          final lend = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final isLender = data['lenderId'] == currentUser.uid ||
                data['ownerId'] == currentUser.uid;
            return !_isCompleted(data) && isLender;
          }).toList();

          final history = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return _isCompleted(data);
          }).toList();

          // Docs with a pending return date for the reminder banner
          final reminderDocs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return !_isCompleted(data) && data['returnDate'] != null;
          }).toList();

          return Column(
            children: [
              if (reminderDocs.isNotEmpty)
                _ReturnReminderBanner(
                  docs: reminderDocs,
                  currentUserId: currentUser.uid,
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TransactionList(
                      docs: borrow,
                      currentUserId: currentUser.uid,
                      isLenderView: false,
                    ),
                    _TransactionList(
                      docs: lend,
                      currentUserId: currentUser.uid,
                      isLenderView: true,
                    ),
                    _TransactionList(
                      docs: history,
                      currentUserId: currentUser.uid,
                      isCompletedTab: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF98259A).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Color(0xFF98259A),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your approved borrow requests\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// -- Return Reminder Banner (top-level aggregate) --

class _ReturnReminderBanner extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final String currentUserId;

  const _ReturnReminderBanner({
    required this.docs,
    required this.currentUserId,
  });

  @override
  State<_ReturnReminderBanner> createState() => _ReturnReminderBannerState();
}

class _ReturnReminderBannerState extends State<_ReturnReminderBanner> {
  late Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    int overdueCount = 0;
    int soonCount = 0;
    DateTime? nearestDue;

    for (final doc in widget.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['returnDate'] == null) continue;
      final due = (data['returnDate'] as Timestamp).toDate();
      final diff = due.difference(now);
      if (diff.isNegative) {
        overdueCount++;
      } else if (diff.inHours < 24) {
        soonCount++;
      }
      if (nearestDue == null || due.isBefore(nearestDue)) {
        nearestDue = due;
      }
    }

    final hasUrgent = overdueCount > 0 || soonCount > 0;
    final bg = overdueCount > 0
        ? const Color(0xFFFFEDED)
        : soonCount > 0
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFEDF7FF);
    final fg = overdueCount > 0
        ? const Color(0xFFB00020)
        : soonCount > 0
            ? const Color(0xFFE67E22)
            : const Color(0xFF2980B9);
    final icon = overdueCount > 0
        ? Icons.warning_amber_rounded
        : soonCount > 0
            ? Icons.timelapse
            : Icons.notifications_active_outlined;

    String message;
    if (overdueCount > 0 && soonCount > 0) {
      message = '$overdueCount overdue, $soonCount due within 24h';
    } else if (overdueCount > 0) {
      final s = overdueCount > 1 ? 's are' : ' is';
      message = '$overdueCount return$s overdue - act now!';
    } else if (soonCount > 0) {
      final s = soonCount > 1 ? 's' : '';
      message = '$soonCount return$s due within 24 hours';
    } else if (nearestDue != null) {
      final diff = nearestDue.difference(now);
      final dStr = diff.inDays > 0
          ? '${diff.inDays}d ${diff.inHours.remainder(24)}h'
          : diff.inHours > 0
              ? '${diff.inHours}h ${diff.inMinutes.remainder(60)}m'
              : '${diff.inMinutes}m';
      message = 'Next return due in $dStr';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUrgent ? 'Return Reminder' : 'Return Schedule',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                      fontSize: 11, color: fg.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          if (nearestDue != null) _MiniCountdown(due: nearestDue, color: fg),
        ],
      ),
    );
  }
}

// -- Mini Countdown --

class _MiniCountdown extends StatefulWidget {
  final DateTime due;
  final Color color;
  const _MiniCountdown({required this.due, required this.color});

  @override
  State<_MiniCountdown> createState() => _MiniCountdownState();
}

class _MiniCountdownState extends State<_MiniCountdown> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.due.difference(DateTime.now());
    final overdue = diff.isNegative;
    final d = diff.abs();

    String top, bottom;
    if (d.inDays >= 1) {
      top = '${d.inDays}';
      bottom = 'days';
    } else if (d.inHours >= 1) {
      top = '${d.inHours}';
      bottom = 'hrs';
    } else {
      top = '${d.inMinutes}';
      bottom = 'min';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            overdue ? '+$top' : top,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: widget.color,
            ),
          ),
          Text(bottom, style: TextStyle(fontSize: 9, color: widget.color)),
        ],
      ),
    );
  }
}

// -- List --

class _TransactionList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String currentUserId;
  final bool isCompletedTab;
  final bool isLenderView;

  const _TransactionList({
    required this.docs,
    required this.currentUserId,
    this.isCompletedTab = false,
    this.isLenderView = false,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCompletedTab
                  ? Icons.history
                  : isLenderView
                      ? Icons.handshake_outlined
                      : Icons.shopping_bag_outlined,
              size: 48,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              isCompletedTab
                  ? 'No transaction history yet.'
                  : isLenderView
                      ? 'You have no active lending.'
                      : 'No active borrowed items.',
              style: const TextStyle(color: Colors.black45),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: docs.length,
      itemBuilder: (context, i) => _TransactionCard(
        convoDoc: docs[i],
        currentUserId: currentUserId,
        isLenderView: isLenderView,
      ),
    );
  }
}

// -- Card --

class _TransactionCard extends StatelessWidget {
  final QueryDocumentSnapshot convoDoc;
  final String currentUserId;
  final bool isLenderView;

  const _TransactionCard({
    required this.convoDoc,
    required this.currentUserId,
    this.isLenderView = false,
  });

  @override
  Widget build(BuildContext context) {
    final convo = convoDoc.data() as Map<String, dynamic>;
    final itemId = (convo['itemId'] ?? '') as String;
    if (itemId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('items').doc(itemId).get(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final itemData = snap.data!.data() as Map<String, dynamic>;

        final isPaid = convo['isPaid'] == true;
        final isReceived = convo['isReceived'] == true;
        final isReturned = convo['isReturned'] == true;
        final isReturnConfirmed = convo['isReturnConfirmed'] == true;
        final isCompleted =
            isPaid && isReceived && isReturned && isReturnConfirmed;

        final returnDue = convo['returnDate'] != null
            ? (convo['returnDate'] as Timestamp).toDate()
            : null;

        final imageUrl =
            (itemData['imageUrls'] is List &&
                    (itemData['imageUrls'] as List).isNotEmpty)
                ? itemData['imageUrls'][0] as String
                : null;

        final step = isReturnConfirmed
            ? 4
            : isReturned
                ? 3
                : isReceived
                    ? 2
                    : isPaid
                        ? 1
                        : 0;

        final isLenderRole = convo['ownerId'] == currentUserId ||
            convo['lenderId'] == currentUserId;

        // Contract state
        final contractSigned = convo['contractSigned'] == true ||
            (convo['contractLenderSigned'] == true &&
             convo['contractBorrowerSigned'] == true);
        final contractPdfUrl = convo['contractPdfUrl'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openChat(context, convo, itemId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: isValidImageUrl(imageUrl)
                              ? Image.network(
                                  imageUrl!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _placeholder(),
                                )
                              : _placeholder(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemData['name'] ?? 'Item',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A2E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${itemData['price'] ?? ''} / ${itemData['pricePer'] ?? 'day'}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              _RoleChip(isLender: isLenderRole),
                            ],
                          ),
                        ),
                        _StatusBadge(isCompleted: isCompleted, step: step),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _ProgressStepper(step: step),
                  ),
                  // Contract badge (interactive: tap to view signed contract or PDF)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: _ContractBadge(
                      signed: contractSigned,
                      pdfUrl: contractPdfUrl,
                      onTap: contractSigned
                          ? () => _openContract(context, convo, itemData)
                          : null,
                      onPdfTap: contractSigned
                          ? () => _viewPdf(context, convo, itemData)
                          : null,
                    ),
                  ),
                  if (returnDue != null) ...[
                    const SizedBox(height: 10),
                    _ReturnDeadlineBanner(returnDue: returnDue),
                  ] else if (!isCompleted) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.event_note_outlined,
                                size: 14, color: Colors.black45),
                            SizedBox(width: 6),
                            Text(
                              'Return Schedule: Fixed by contract / chat agreement',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 22, indent: 14, endIndent: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _buildRecordFooter(
                        context, convo, itemId, itemData, isCompleted, step, contractSigned),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordFooter(
    BuildContext context,
    Map<String, dynamic> convo,
    String itemId,
    Map<String, dynamic> itemData,
    bool isCompleted,
    int step,
    bool contractSigned,
  ) {
    return Row(
      children: [
        Icon(
          Icons.shield_outlined,
          size: 15,
          color: Colors.blueGrey.shade600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            isCompleted
                ? 'Immutable Record • Completed'
                : 'View-Only Record • Verified via QR & Escrow',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey.shade600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        if (contractSigned) ...[
          OutlinedButton.icon(
            onPressed: () => _openContract(context, convo, itemData),
            icon: const Icon(Icons.description_outlined, size: 13),
            label: const Text('Contract', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32),
              side: const BorderSide(color: Color(0xFF2E7D32)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        OutlinedButton.icon(
          onPressed: () => _openChat(context, convo, itemId),
          icon: const Icon(Icons.chat_bubble_outline, size: 13),
          label: const Text('Chat', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF98259A),
            side: const BorderSide(color: Color(0xFF98259A)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openContract(
    BuildContext context,
    Map<String, dynamic> convo,
    Map<String, dynamic> itemData,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF98259A)),
      ),
    );

    try {
      final lenderId = convo['itemOwnerId'] ??
          convo['ownerId'] ??
          convo['lenderId'] ??
          itemData['ownerId'] ??
          '';
      final borrowerId = convo['borrowerId'] ??
          ((convo['participants'] as List<dynamic>?)?.firstWhere(
            (id) => id != lenderId,
            orElse: () => '',
          ) as String? ?? '');

      Future<Map<String, dynamic>> fetchUser(String uid) async {
        if (uid.isEmpty) return {};
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        return snap.data() ?? {};
      }

      final lenderDoc = await fetchUser(lenderId);
      final borrowerDoc = await fetchUser(borrowerId);

      String displayName(Map<String, dynamic> doc, String fallback) =>
          doc['displayName'] ?? doc['name'] ?? doc['username'] ?? fallback;
      String email(Map<String, dynamic> doc, String fallback) =>
          doc['email'] ?? fallback;

      final isLender = currentUserId == lenderId;

      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ElectronicContractPage(
            convoId: convoDoc.id,
            currentUserId: currentUserId,
            isLender: isLender,
            convoData: convo,
            itemData: itemData,
            lenderName: displayName(lenderDoc, convo['lenderName'] ?? 'Lender'),
            lenderEmail: email(lenderDoc, convo['lenderEmail'] ?? ''),
            borrowerName: displayName(borrowerDoc, convo['borrowerName'] ?? 'Borrower'),
            borrowerEmail: email(borrowerDoc, convo['borrowerEmail'] ?? ''),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open contract: $e')),
        );
      }
    }
  }

  Future<void> _viewPdf(
    BuildContext context,
    Map<String, dynamic> convo,
    Map<String, dynamic> itemData,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF98259A)),
      ),
    );

    try {
      final lenderId = convo['itemOwnerId'] ??
          convo['ownerId'] ??
          convo['lenderId'] ??
          itemData['ownerId'] ??
          '';
      final borrowerId = convo['borrowerId'] ??
          ((convo['participants'] as List<dynamic>?)?.firstWhere(
            (id) => id != lenderId,
            orElse: () => '',
          ) as String? ?? '');

      Future<Map<String, dynamic>> fetchUser(String uid) async {
        if (uid.isEmpty) return {};
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        return snap.data() ?? {};
      }

      final lenderDoc = await fetchUser(lenderId);
      final borrowerDoc = await fetchUser(borrowerId);

      String displayName(Map<String, dynamic> doc, String fallback) =>
          doc['displayName'] ?? doc['name'] ?? doc['username'] ?? fallback;
      String email(Map<String, dynamic> doc, String fallback) =>
          doc['email'] ?? fallback;

      final startStr = convo['startDate'] as String? ?? '';
      final endStr = convo['endDate'] as String? ?? '';
      final start = DateTime.tryParse(startStr) ?? DateTime.now();
      final end = DateTime.tryParse(endStr) ?? DateTime.now();
      final retTs = convo['returnDate'];
      String? retFmt;
      if (retTs != null) {
        retFmt = DateFormat('MMM d, yyyy – h:mm a')
            .format((retTs as Timestamp).toDate());
      }

      final rawDefects = itemData['documentedDefects'];
      List<String> defectsList = [];
      if (rawDefects is List && rawDefects.isNotEmpty) {
        for (var d in rawDefects) {
          if (d is Map) {
            final cat = d['category'] ?? 'Defect';
            final sev = d['severity'] ?? 'Minor';
            final desc = d['description'] ?? '';
            defectsList.add('[$sev] $cat: $desc');
          }
        }
      }

      final contractData = ContractData(
        convoId: convoDoc.id,
        itemName: itemData['name'] ?? 'Item',
        itemDescription: itemData['description'] ?? '',
        lenderName: displayName(lenderDoc, convo['lenderName'] ?? 'Lender'),
        lenderEmail: email(lenderDoc, convo['lenderEmail'] ?? ''),
        borrowerName: displayName(borrowerDoc, convo['borrowerName'] ?? 'Borrower'),
        borrowerEmail: email(borrowerDoc, convo['borrowerEmail'] ?? ''),
        totalPrice: (convo['totalPrice'] as num?)?.toDouble() ?? 0,
        totalDays: convo['totalDays'] as int? ?? 0,
        startDate: start,
        endDate: end,
        returnDateFormatted: retFmt,
        documentedDefects: defectsList,
      );

      final pdfBytes = await ContractService.generatePdfBytes(contractData);

      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewPage(pdfBytes: pdfBytes),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open contract PDF: $e')),
        );
      }
    }
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFFFBEBFB),
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.black26, size: 28),
      );

  Future<void> _openChat(
      BuildContext context, Map<String, dynamic> convo, String itemId) async {
    final participants = List<String>.from(convo['participants'] ?? []);
    final otherUserId = participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    String otherUserName = (convo['ownerId'] == currentUserId
            ? convo['borrowerName']
            : convo['lenderName']) ??
        'User';

    if (otherUserId.isNotEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(otherUserId)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data();
          final name = data?['name'] ?? data?['username'];
          if (name is String && name.isNotEmpty) {
            otherUserName = name;
          }
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          convoId: convoDoc.id,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          itemId: itemId,
        ),
      ),
    );
  }
}

// -- Role Chip --

class _RoleChip extends StatelessWidget {
  final bool isLender;
  const _RoleChip({required this.isLender});

  @override
  Widget build(BuildContext context) {
    final color =
        isLender ? const Color(0xFF98259A) : const Color(0xFF98259A);
    final label = isLender ? 'You: Lender' : 'You: Borrower';
    final icon =
        isLender ? Icons.handshake_outlined : Icons.shopping_bag_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Progress Stepper --

class _ProgressStepper extends StatelessWidget {
  final int step;
  const _ProgressStepper({required this.step});

  static const _labels = ['Paid', 'Received', 'Returned', 'Confirmed'];
  static const _colors = [
    Color(0xFF2ECC71),
    Color(0xFF98259A),
    Color(0xFFE67E22),
    Color(0xFF98259A),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length, (i) {
        final done = step > i;
        final active = step == i;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? _colors[i]
                            : active
                                ? _colors[i].withValues(alpha: 0.15)
                                : Colors.grey[200],
                        border: active
                            ? Border.all(color: _colors[i], width: 2)
                            : null,
                      ),
                      child: Center(
                        child: done
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: active ? _colors[i] : Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: done || active
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: done || active ? _colors[i] : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < _labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: done ? _colors[i] : Colors.grey[200],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// -- Return Deadline Banner (per card) --

class _ReturnDeadlineBanner extends StatefulWidget {
  final DateTime returnDue;
  const _ReturnDeadlineBanner({required this.returnDue});

  @override
  State<_ReturnDeadlineBanner> createState() => _ReturnDeadlineBannerState();
}

class _ReturnDeadlineBannerState extends State<_ReturnDeadlineBanner> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.returnDue.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(
            () => _remaining = widget.returnDue.difference(DateTime.now()));
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays}d ${d.inHours.remainder(24)}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _remaining.isNegative;
    final soon = !overdue && _remaining.inHours < 24;

    final bg = overdue
        ? const Color(0xFFFFEDED)
        : soon
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFEDF7FF);
    final fg = overdue
        ? const Color(0xFFB00020)
        : soon
            ? const Color(0xFFE67E22)
            : const Color(0xFF2980B9);
    final icon = overdue
        ? Icons.warning_amber_rounded
        : soon
            ? Icons.timelapse
            : Icons.schedule;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overdue
                      ? 'Overdue by ${_fmt(_remaining.abs())}'
                      : 'Return in ${_fmt(_remaining)}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: fg),
                ),
                Text(
                  'Due: ${DateFormat('EEE, MMM d, yyyy  h:mm a').format(widget.returnDue)}',
                  style: TextStyle(
                      fontSize: 10, color: fg.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: fg.withValues(alpha: 0.25)),
            ),
            child: Text(
              overdue ? '+${_fmt(_remaining.abs())}' : _fmt(_remaining),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Status Badge --

class _StatusBadge extends StatelessWidget {
  final bool isCompleted;
  final int step;
  const _StatusBadge({required this.isCompleted, required this.step});

  @override
  Widget build(BuildContext context) {
    final label = isCompleted
        ? 'Done'
        : step == 0
            ? 'Pending Pay'
            : step == 1
                ? 'In Transit'
                : step == 2
                    ? 'Active'
                    : 'Awaiting Confirm';

    final color = isCompleted
        ? const Color(0xFF2ECC71)
        : step == 0
            ? Colors.orange
            : step == 1
                ? const Color(0xFF98259A)
                : const Color(0xFF98259A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}


// ── Contract Badge ─────────────────────────────────────────────────────────

class _ContractBadge extends StatelessWidget {
  final bool signed;
  final String? pdfUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPdfTap;

  const _ContractBadge({
    required this.signed,
    this.pdfUrl,
    this.onTap,
    this.onPdfTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: signed ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: signed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: signed
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                  : Colors.orange.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                signed ? Icons.verified_user_outlined : Icons.description_outlined,
                size: 16,
                color: signed ? const Color(0xFF2E7D32) : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      signed
                          ? 'Electronic Contract Signed (RA 8792)'
                          : 'Awaiting Contract Signatures',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: signed ? const Color(0xFF2E7D32) : Colors.orange.shade800,
                      ),
                    ),
                    if (signed)
                      const Text(
                        'Tap to review signed copy & legal terms',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF388E3C),
                        ),
                      ),
                  ],
                ),
              ),
              if (signed) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onPdfTap ?? onTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 12, color: Color(0xFF2E7D32)),
                        SizedBox(width: 4),
                        Text(
                          'PDF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFF2E7D32)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
