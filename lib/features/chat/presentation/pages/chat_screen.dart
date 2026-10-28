// chat_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:lendly/core/utils/image_utils.dart';
import 'package:lendly/features/chat/presentation/pages/qr_handoff_screen.dart';
import 'package:lendly/features/wallet/data/repositories/wallet_repository.dart';
import 'package:lendly/features/items/presentation/pages/electronic_contract_page.dart';

class ChatScreen extends StatefulWidget {
  final String convoId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? itemId;

  const ChatScreen({
    super.key,
    required this.convoId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.itemId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Stream<DocumentSnapshot> _conversationStream;
  late Stream<DocumentSnapshot> _userStream;

  @override
  void initState() {
    super.initState();
    _conversationStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId)
        .snapshots();

    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final convoRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId);

    final convoSnap = await convoRef.get();
    final convoData = convoSnap.data();
    final isDenied = convoData?['denied'] == true;
    final isOwner = convoData?['itemOwnerId'] == widget.currentUserId ||
        convoData?['ownerId'] == widget.currentUserId;

    if (isDenied && !isOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.block, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('The lender has denied this request.'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    await convoRef.collection('messages').add({
      'senderId': widget.currentUserId,
      'type': 'text',
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await convoRef.update({
      'lastMessageText': text.trim(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message,
            style: const TextStyle(color: Colors.black54, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRequest() async {
    final ok = await _showConfirmDialog(
      title: 'Accept Request & Hold Escrow',
      message:
          'Accept this borrow request? The rental amount will be moved from the borrower\'s available ORC to escrow until the item is safely returned.',
      confirmLabel: 'Accept & Escrow',
      confirmColor: const Color(0xFF2ECC71),
    );
    if (ok != true) return;

    try {
      await WalletRepository().acceptRentalRequest(widget.convoId);
      Fluttertoast.showToast(msg: 'Request accepted & escrow secured!');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unable to Accept Request',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            e.message ?? 'Borrower has insufficient ORC balance to accept this rental.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to accept: $e');
    }
  }

  Future<void> _denyRequest() async {
    final ok = await _showConfirmDialog(
      title: 'Deny Request',
      message:
          'Deny this borrow request? Any held escrow funds will be immediately refunded to the borrower.',
      confirmLabel: 'Deny',
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    try {
      await WalletRepository().cancelOrRefundRental(widget.convoId, 'Denied by lender');
      Fluttertoast.showToast(msg: 'Request denied.');
    } catch (e) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.convoId)
          .update({'denied': true, 'approved': false});
      Fluttertoast.showToast(msg: 'Request denied.');
    }
  }

  /// Opens the ElectronicContractPage after fetching item and user data from Firestore.
  Future<void> _openContractPage(Map<String, dynamic> convoData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final itemId = convoData['itemId'] as String? ?? '';
    final lenderId   = convoData['ownerId'] ?? convoData['lenderId'] ?? '';
    final borrowerId = convoData['participants']?.firstWhere(
      (id) => id != lenderId,
      orElse: () => '',
    ) ?? '';

    // Fetch item data
    Map<String, dynamic> itemData = {};
    if (itemId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
      itemData = snap.data() as Map<String, dynamic>? ?? {};
    }

    // Fetch lender and borrower user docs
    Future<Map<String, dynamic>> fetchUser(String uid) async {
      if (uid.isEmpty) return {};
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return snap.data() as Map<String, dynamic>? ?? {};
    }

    final lenderDoc   = await fetchUser(lenderId);
    final borrowerDoc = await fetchUser(borrowerId);

    String _displayName(Map<String, dynamic> doc, String fallback) =>
        doc['displayName'] ?? doc['name'] ?? doc['username'] ?? fallback;
    String _email(Map<String, dynamic> doc, String fallback) =>
        doc['email'] ?? fallback;

    final isLender = currentUser.uid == lenderId;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ElectronicContractPage(
          convoId:       widget.convoId,
          currentUserId: currentUser.uid,
          isLender:      isLender,
          convoData:     convoData,
          itemData:      itemData,
          lenderName:    _displayName(lenderDoc, 'Lender'),
          lenderEmail:   _email(lenderDoc, ''),
          borrowerName:  _displayName(borrowerDoc, 'Borrower'),
          borrowerEmail: _email(borrowerDoc, ''),
        ),
      ),
    );
  }

  Future<void> _openQrScreen(String action, Map<String, dynamic> convoData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final itemId = convoData['itemId'] as String? ?? '';
    String itemName = 'Item';
    if (itemId.isNotEmpty) {
      final itemSnap = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .get();
      if (itemSnap.exists) {
        final d = itemSnap.data() as Map<String, dynamic>;
        itemName = d['name'] ?? d['title'] ?? 'Item';
      }
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrHandoffScreen(
          convoId: widget.convoId,
          currentUserId: currentUser.uid,
          currentUserName: currentUser.displayName ?? 'User',
          itemName: itemName,
          action: action,
        ),
      ),
    );
  }

  Future<void> _clearChatMessages() async {
    final convoRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId);
    final messagesRef = convoRef.collection('messages');
    while (true) {
      final snap = await messagesRef.limit(500).get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await convoRef.update({
      'lastMessageText': FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<DocumentSnapshot>(
          stream: _userStream,
          builder: (context, snap) {
            final photoUrl = snap.hasData && snap.data!.exists
                ? (snap.data!.data() as Map<String, dynamic>)['photoURL']
                : null;
            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: isValidImageUrl(photoUrl)
                      ? NetworkImage(photoUrl!)
                      : const AssetImage('assets/images/default_avatar.png')
                          as ImageProvider,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.otherUserName,
                      style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const Text('Lendly Chat',
                        style: TextStyle(
                            color: Colors.black45, fontSize: 11)),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Color(0xFF1A1A2E)),
            tooltip: 'Clear chat',
            onPressed: () async {
              final ok = await _showConfirmDialog(
                title: 'Clear Chat',
                message:
                    'Delete all messages? The conversation record will remain.',
                confirmLabel: 'Clear',
                confirmColor: Colors.red,
              );
              if (ok == true) {
                await _clearChatMessages();
                Fluttertoast.showToast(msg: 'Chat cleared');
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _conversationStream,
        builder: (context, convoSnap) {
          if (!convoSnap.hasData) {
            return const Center(
                child:
                    CircularProgressIndicator(color: Color(0xFF7B40B5)));
          }

          final convoData =
              convoSnap.data!.data() as Map<String, dynamic>? ?? {};
          final isOwner =
              convoData['itemOwnerId'] == widget.currentUserId ||
                  convoData['ownerId'] == widget.currentUserId;
          final isApproved = convoData['approved'] == true;
          final isDenied = convoData['denied'] == true;
          final isPaid = convoData['isPaid'] == true;
          final isReceived = convoData['isReceived'] == true;
          final isReturned = convoData['isReturned'] == true;
          final isReturnConfirmed = convoData['isReturnConfirmed'] == true;
          final isFullyDone =
              isPaid && isReceived && isReturned && isReturnConfirmed;
          // Contract state
          final contractSigned     = convoData['contractSigned']         == true;
          final lenderSigned       = convoData['contractLenderSigned']   == true;
          final borrowerSigned     = convoData['contractBorrowerSigned'] == true;
          final iHaveSigned        = isOwner ? lenderSigned : borrowerSigned;
          final contractPdfUrl     = convoData['contractPdfUrl'] as String?;

          return Column(
            children: [
              // Pinned borrow request card
              _BorrowRequestCard(convoData: convoData),

              // Messages
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('conversations')
                      .doc(widget.convoId)
                      .collection('messages')
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
                  builder: (context, msgSnap) {
                    if (!msgSnap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF7B40B5)));
                    }

                    final messages = msgSnap.data!.docs;
                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text('No messages yet.',
                                style: TextStyle(
                                    color: Colors.black38,
                                    fontSize: 13)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index].data()
                            as Map<String, dynamic>;
                        final type = msg['type'] ?? 'text';

                        if (type == 'borrow_request') {
                          return _BorrowRequestMessage(
                            msg: msg,
                            isMe: msg['senderId'] ==
                                widget.currentUserId,
                          );
                        }

                        final isMe =
                            msg['senderId'] == widget.currentUserId;
                        return _ChatBubble(
                          text: msg['text'] ?? '',
                          isMe: isMe,
                          senderName:
                              isMe ? null : widget.otherUserName,
                          timestamp: msg['timestamp'] as Timestamp?,
                        );
                      },
                    );
                  },
                ),
              ),

              // Status banner
              _StatusBar(
                isApproved: isApproved,
                isDenied: isDenied,
                isFullyDone: isFullyDone,
                isPaid: isPaid,
                isReceived: isReceived,
                isReturned: isReturned,
                isReturnConfirmed: isReturnConfirmed,
              ),

              // Owner: approve / deny
              if (!isDenied && !isFullyDone && isOwner && !isApproved)
                _OwnerActionPanel(
                  onApprove: _approveRequest,
                  onDeny: _denyRequest,
                ),

              // Contract signing panel — shown after approval until both sign
              if (isApproved && !isFullyDone && !contractSigned)
                _ContractSigningPanel(
                  contractSigned:  contractSigned,
                  lenderSigned:    lenderSigned,
                  borrowerSigned:  borrowerSigned,
                  iHaveSigned:     iHaveSigned,
                  onOpenContract:  () => _openContractPage(convoData),
                ),

              // QR handoff/return buttons → only after contract is signed
              if (isApproved && !isFullyDone && contractSigned)
                _QrActionPanel(
                  isOwner: isOwner,
                  isPaid: isPaid,
                  isReceived: isReceived,
                  isReturned: isReturned,
                  isReturnConfirmed: isReturnConfirmed,
                  onConfirmHandoff: () =>
                      _openQrScreen('handoff', convoData),
                  onConfirmReturn: () =>
                      _openQrScreen('return', convoData),
                ),

              // Input
              if (!isDenied || isOwner)
                _MessageInput(
                  controller: _messageController,
                  onSend: () => _sendMessage(_messageController.text),
                )
              else
                _DeniedBar(),
            ],
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Pinned Borrow Request Card (top of chat)
// ────────────────────────────────────────────────────────────────────────────

class _BorrowRequestCard extends StatelessWidget {
  final Map<String, dynamic> convoData;
  const _BorrowRequestCard({required this.convoData});

  @override
  Widget build(BuildContext context) {
    final startStr = convoData['startDate'] as String?;
    final endStr = convoData['endDate'] as String?;
    if (startStr == null || endStr == null) return const SizedBox.shrink();

    final start = DateTime.tryParse(startStr);
    final end = DateTime.tryParse(endStr);
    if (start == null || end == null) return const SizedBox.shrink();

    final totalDays = convoData['totalDays'] as int? ?? 0;
    final totalPrice =
        (convoData['totalPrice'] as num?)?.toDouble() ?? 0;
    final fmt = DateFormat('MMM d, yyyy');
    final isApproved = convoData['approved'] == true;
    final isDenied = convoData['denied'] == true;

    final statusColor = isDenied
        ? Colors.red
        : isApproved
            ? const Color(0xFF2ECC71)
            : const Color(0xFFE67E22);
    final statusLabel =
        isDenied ? '✗ Denied' : isApproved ? '✓ Accepted' : '⏳ Pending';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 16, color: Color(0xFF7B40B5)),
              const SizedBox(width: 6),
              const Text('Borrow Request',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B40B5))),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4))),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Chip(
                  icon: Icons.calendar_today_outlined,
                  text:
                      '${fmt.format(start)} — ${fmt.format(end)}'),
              _Chip(
                  icon: Icons.timelapse,
                  text:
                      '$totalDays day${totalDays > 1 ? 's' : ''}'),
              _Chip(
                  icon: Icons.payments_outlined,
                  text:
                      '₱${totalPrice.toStringAsFixed(0)} total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.black45),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Borrow Request Message Bubble
// ────────────────────────────────────────────────────────────────────────────

class _BorrowRequestMessage extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  const _BorrowRequestMessage(
      {required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final itemName = msg['itemName'] ?? 'Item';
    final startStr = msg['startDate'] as String?;
    final endStr = msg['endDate'] as String?;
    final totalDays = msg['totalDays'] as int? ?? 0;
    final totalPrice =
        (msg['totalPrice'] as num?)?.toDouble() ?? 0;
    final location = msg['location'] ?? 'Location TBD';
    final fmt = DateFormat('MMM d, yyyy');
    final start =
        startStr != null ? DateTime.tryParse(startStr) : null;
    final end = endStr != null ? DateTime.tryParse(endStr) : null;

    return Align(
      alignment:
          isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width * 0.78),
        margin:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF7B40B5).withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.handshake_outlined,
                    size: 16, color: Color(0xFF7B40B5)),
                SizedBox(width: 6),
                Text('Borrow Request',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7B40B5))),
              ],
            ),
            const SizedBox(height: 10),
            _R(icon: Icons.inventory_2_outlined, label: 'Item', value: itemName, bold: true),
            const SizedBox(height: 6),
            if (start != null)
              _R(icon: Icons.calendar_today_outlined, label: 'Start', value: fmt.format(start)),
            const SizedBox(height: 6),
            if (end != null)
              _R(icon: Icons.event_outlined, label: 'End', value: fmt.format(end)),
            const SizedBox(height: 6),
            _R(icon: Icons.timelapse, label: 'Duration', value: '$totalDays day${totalDays > 1 ? 's' : ''}'),
            const SizedBox(height: 6),
            _R(icon: Icons.location_on_outlined, label: 'Location', value: location),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        fontSize: 12, color: Colors.black45)),
                Text('₱${totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7B40B5))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _R extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool bold;
  const _R(
      {required this.icon,
      required this.label,
      required this.value,
      this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.black38),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 11, color: Colors.black45)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.w500,
                  color: const Color(0xFF1A1A2E)),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Chat Bubble
// ────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String? senderName;
  final Timestamp? timestamp;

  const _ChatBubble({
    required this.text,
    required this.isMe,
    this.senderName,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = timestamp != null
        ? DateFormat('h:mm a').format(timestamp!.toDate())
        : '';

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && senderName != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 2),
            child: Text(senderName!,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold)),
          ),
        Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isMe)
              Text(timeStr,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.black38)),
            if (isMe) const SizedBox(width: 4),
            Container(
              constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.68),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              margin: const EdgeInsets.symmetric(
                  vertical: 3, horizontal: 6),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFF7B40B5)
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft:
                      Radius.circular(isMe ? 18 : 4),
                  bottomRight:
                      Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                      color:
                          Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14,
                      color: isMe
                          ? Colors.white
                          : const Color(0xFF1A1A2E))),
            ),
            if (!isMe) const SizedBox(width: 4),
            if (!isMe)
              Text(timeStr,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.black38)),
          ],
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Status Bar
// ────────────────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final bool isApproved, isDenied, isFullyDone;
  final bool isPaid, isReceived, isReturned, isReturnConfirmed;

  const _StatusBar({
    required this.isApproved,
    required this.isDenied,
    required this.isFullyDone,
    required this.isPaid,
    required this.isReceived,
    required this.isReturned,
    required this.isReturnConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    IconData icon;
    String label;

    if (isDenied) {
      bg = const Color(0xFFFFEDED);
      icon = Icons.block;
      label = 'Request denied by lender.';
    } else if (isFullyDone) {
      bg = const Color(0xFFE8F8F0);
      icon = Icons.check_circle_outline;
      label = 'Transaction complete!';
    } else if (isApproved && isReceived) {
      bg = const Color(0xFFEDF7FF);
      icon = Icons.inventory_2_outlined;
      label = 'Item borrowed — return pending.';
    } else if (isApproved) {
      bg = const Color(0xFFF0E8FF);
      icon = Icons.handshake_outlined;
      label = 'Request accepted — meet to exchange.';
    } else {
      bg = const Color(0xFFFFF3E0);
      icon = Icons.hourglass_empty;
      label = 'Waiting for lender to respond...';
    }

    final fg = isDenied
        ? const Color(0xFFB00020)
        : isFullyDone
            ? const Color(0xFF2ECC71)
            : isApproved
                ? const Color(0xFF7B40B5)
                : const Color(0xFFE67E22);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bg,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Owner Approve / Deny Panel
// ────────────────────────────────────────────────────────────────────────────

class _OwnerActionPanel extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  const _OwnerActionPanel(
      {required this.onApprove, required this.onDeny});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDeny,
              icon: const Icon(Icons.close,
                  size: 16, color: Colors.red),
              label: const Text('Deny',
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onApprove,
              icon: const Icon(Icons.check,
                  size: 16, color: Colors.white),
              label: const Text('Accept Request',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2ECC71),
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// QR Action Panel (after approval — handoff + return)
// ────────────────────────────────────────────────────────────────────────────

class _QrActionPanel extends StatelessWidget {
  final bool isOwner;
  final bool isPaid, isReceived, isReturned, isReturnConfirmed;
  final VoidCallback onConfirmHandoff;
  final VoidCallback onConfirmReturn;

  const _QrActionPanel({
    required this.isOwner,
    required this.isPaid,
    required this.isReceived,
    required this.isReturned,
    required this.isReturnConfirmed,
    required this.onConfirmHandoff,
    required this.onConfirmReturn,
  });

  @override
  Widget build(BuildContext context) {
    final handoffDone = isPaid && isReceived;
    final returnDone = isReturned && isReturnConfirmed;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Transaction Actions',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black45)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QBtn(
                  icon: Icons.swap_horiz_rounded,
                  label: handoffDone
                      ? 'Handoff Done ✓'
                      : 'Confirm Handoff',
                  sublabel: 'Item exchange',
                  done: handoffDone,
                  color: const Color(0xFF3498DB),
                  onTap:
                      handoffDone ? null : onConfirmHandoff,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QBtn(
                  icon: Icons.undo_rounded,
                  label: returnDone
                      ? 'Return Done ✓'
                      : 'Confirm Return',
                  sublabel: 'Item returned',
                  done: returnDone,
                  color: const Color(0xFF7B40B5),
                  onTap: (!handoffDone || returnDone)
                      ? null
                      : onConfirmReturn,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool done;
  final Color color;
  final VoidCallback? onTap;

  const _QBtn({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.done,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: done
              ? color.withValues(alpha: 0.08)
              : onTap != null
                  ? color.withValues(alpha: 0.1)
                  : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: done
                  ? color.withValues(alpha: 0.4)
                  : onTap != null
                      ? color.withValues(alpha: 0.35)
                      : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : icon,
              size: 20,
              color: done
                  ? color
                  : onTap != null
                      ? color
                      : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: done
                              ? color
                              : onTap != null
                                  ? color
                                  : Colors.grey)),
                  Text(sublabel,
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black38)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Message Input
// ────────────────────────────────────────────────────────────────────────────

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _MessageInput(
      {required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(
                    color: Colors.black38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF7B40B5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Denied Bar
// ────────────────────────────────────────────────────────────────────────────

class _DeniedBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFFEDED),
        border:
            Border(top: BorderSide(color: Color(0xFFFFCDD2))),
      ),
      child: const Row(
        children: [
          Icon(Icons.block, color: Color(0xFFB00020), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This request has been denied. You can no longer contact this lender for this item.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFB00020),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Contract Signing Panel
// ────────────────────────────────────────────────────────────────────────────

class _ContractSigningPanel extends StatelessWidget {
  final bool contractSigned;
  final bool lenderSigned;
  final bool borrowerSigned;
  final bool iHaveSigned;
  final VoidCallback onOpenContract;

  const _ContractSigningPanel({
    required this.contractSigned,
    required this.lenderSigned,
    required this.borrowerSigned,
    required this.iHaveSigned,
    required this.onOpenContract,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iHaveSigned
              ? Colors.orange.withValues(alpha: 0.5)
              : const Color(0xFF7B40B5).withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF7B40B5),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Electronic Contract Required',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Both parties must sign before proceeding',
                      style: TextStyle(fontSize: 10, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'RA 8792',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7B40B5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Signature status chips
          Row(
            children: [
              _SigChip(label: 'Lender', signed: lenderSigned),
              const SizedBox(width: 8),
              _SigChip(label: 'Borrower', signed: borrowerSigned),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpenContract,
              icon: Icon(
                iHaveSigned ? Icons.hourglass_top_outlined : Icons.draw_outlined,
                size: 16,
                color: Colors.white,
              ),
              label: Text(
                iHaveSigned ? 'View Contract (Waiting for other party)' : 'Review & Sign Contract',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: iHaveSigned ? Colors.orange : const Color(0xFF7B40B5),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SigChip extends StatelessWidget {
  final String label;
  final bool signed;
  const _SigChip({required this.label, required this.signed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: signed ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: signed
              ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            signed ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 12,
            color: signed ? const Color(0xFF2E7D32) : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: signed ? const Color(0xFF2E7D32) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
