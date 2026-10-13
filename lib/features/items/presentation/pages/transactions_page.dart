import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lendly/core/utils/image_utils.dart';

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
        title: const Text(
          'Transactions',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7B40B5),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF7B40B5),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
            Tab(text: 'As Lender'),
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
              child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final docs = snapshot.data!.docs;

          final ongoing = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return !_isCompleted(data);
          }).toList();

          final completed = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return _isCompleted(data);
          }).toList();

          final asLender = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['lenderId'] == currentUser.uid ||
                data['ownerId'] == currentUser.uid;
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
                        docs: ongoing, currentUserId: currentUser.uid),
                    _TransactionList(
                      docs: completed,
                      currentUserId: currentUser.uid,
                      isCompletedTab: true,
                    ),
                    _TransactionList(
                      docs: asLender,
                      currentUserId: currentUser.uid,
                      isLenderView: true,
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
              color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: Color(0xFF7B40B5),
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
                  ? Icons.check_circle_outline
                  : isLenderView
                      ? Icons.handshake_outlined
                      : Icons.receipt_outlined,
              size: 48,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              isCompletedTab
                  ? 'No completed transactions yet.'
                  : isLenderView
                      ? 'You have no active lending.'
                      : 'No ongoing transactions.',
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

        final isOwner = convo['ownerId'] == currentUserId ||
            convo['lenderId'] == currentUserId;

        final isLenderRole = convo['ownerId'] == currentUserId ||
            convo['lenderId'] == currentUserId;

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
              if (returnDue != null) ...[
                const SizedBox(height: 10),
                _ReturnDeadlineBanner(returnDue: returnDue),
              ],
              if (!isCompleted) ...[
                const Divider(height: 24, indent: 14, endIndent: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _buildActionRow(context, convo, isOwner),
                ),
              ] else
                const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow(
      BuildContext context, Map<String, dynamic> convo, bool isOwner) {
    final nextBtn = _nextActionButton(convo, convoDoc.id);
    final showCalendar = isOwner || isLenderView;
    if (!showCalendar && nextBtn == null) return const SizedBox.shrink();

    return Row(
      children: [
        if (showCalendar) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickReturnDate(
                context,
                convoDoc.id,
                convo['returnDate'] != null
                    ? (convo['returnDate'] as Timestamp).toDate()
                    : null,
              ),
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
              label: Text(
                convo['returnDate'] == null ? 'Set Return Date' : 'Edit Date',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7B40B5),
                side: const BorderSide(color: Color(0xFF7B40B5)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (nextBtn != null) const SizedBox(width: 10),
        ],
        if (nextBtn != null) Expanded(child: nextBtn),
      ],
    );
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFFEFF6F9),
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.black26, size: 28),
      );

  Widget? _nextActionButton(Map<String, dynamic> convo, String convoId) {
    final isPaid = convo['isPaid'] == true;
    final isReceived = convo['isReceived'] == true;
    final isReturned = convo['isReturned'] == true;
    final isReturnConfirmed = convo['isReturnConfirmed'] == true;

    Future<void> update(Map<String, dynamic> data) =>
        FirebaseFirestore.instance
            .collection('conversations')
            .doc(convoId)
            .update(data);

    if (!isPaid) {
      return _ActionButton(
        label: 'Mark Paid',
        color: const Color(0xFF2ECC71),
        icon: Icons.payments_outlined,
        onTap: () => update({'isPaid': true}),
      );
    } else if (!isReceived) {
      return _ActionButton(
        label: 'Mark Received',
        color: const Color(0xFF3498DB),
        icon: Icons.check_circle_outline,
        onTap: () => update({'isReceived': true}),
      );
    } else if (!isReturned) {
      return _ActionButton(
        label: 'Mark Returned',
        color: const Color(0xFFE67E22),
        icon: Icons.undo_outlined,
        onTap: () => update({'isReturned': true}),
      );
    } else if (!isReturnConfirmed) {
      return _ActionButton(
        label: 'Confirm Return',
        color: const Color(0xFF7B40B5),
        icon: Icons.verified_outlined,
        onTap: () => update({'isReturnConfirmed': true}),
      );
    }
    return null;
  }

  Future<void> _pickReturnDate(
      BuildContext context, String convoId, DateTime? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF7B40B5),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF7B40B5),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (!context.mounted) return;

    final finalDate = time != null
        ? DateTime(
            picked.year, picked.month, picked.day, time.hour, time.minute)
        : DateTime(picked.year, picked.month, picked.day, 17, 0);

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(convoId)
        .update({'returnDate': Timestamp.fromDate(finalDate)});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Return date set to ${DateFormat('MMM d, yyyy - h:mm a').format(finalDate)}',
          ),
          backgroundColor: const Color(0xFF7B40B5),
        ),
      );
    }
  }
}

// -- Role Chip --

class _RoleChip extends StatelessWidget {
  final bool isLender;
  const _RoleChip({required this.isLender});

  @override
  Widget build(BuildContext context) {
    final color =
        isLender ? const Color(0xFF7B40B5) : const Color(0xFF3498DB);
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
    Color(0xFF3498DB),
    Color(0xFFE67E22),
    Color(0xFF7B40B5),
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
                ? const Color(0xFF3498DB)
                : const Color(0xFF7B40B5);

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

// -- Action Button --

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
            fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
