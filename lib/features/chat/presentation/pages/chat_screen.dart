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
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';
import 'package:lendly/features/profile/presentation/widgets/review_dialog.dart';
import 'package:lendly/features/appraisal/presentation/widgets/appraisal_form_dialog.dart';

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

  String _getEffectiveItemId(Map<String, dynamic> convoData) {
    final fromConvo = convoData['itemId'] as String?;
    if (fromConvo != null && fromConvo.isNotEmpty) return fromConvo;
    if (widget.itemId != null && widget.itemId!.isNotEmpty) return widget.itemId!;
    return '';
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

    final itemId = _getEffectiveItemId(convoData);

    // Fetch item data
    Map<String, dynamic> itemData = {};
    if (itemId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
      itemData = snap.data() ?? {};
    }

    final lenderId = convoData['itemOwnerId'] ??
        convoData['ownerId'] ??
        convoData['lenderId'] ??
        itemData['ownerId'] ??
        '';
    final borrowerId = convoData['borrowerId'] ??
        ((convoData['participants'] as List<dynamic>?)?.firstWhere(
          (id) => id != lenderId,
          orElse: () => '',
        ) as String? ?? '');

    // Fetch lender and borrower user docs
    Future<Map<String, dynamic>> fetchUser(String uid) async {
      if (uid.isEmpty) return {};
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return snap.data() ?? {};
    }

    final lenderDoc   = await fetchUser(lenderId);
    final borrowerDoc = await fetchUser(borrowerId);

    String displayName(Map<String, dynamic> doc, String fallback) =>
        doc['displayName'] ?? doc['name'] ?? doc['username'] ?? fallback;
    String email(Map<String, dynamic> doc, String fallback) =>
        doc['email'] ?? fallback;

    final isLender = currentUser.uid == lenderId;

    if (!mounted) return;
    final signedResult = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ElectronicContractPage(
          convoId:       widget.convoId,
          currentUserId: currentUser.uid,
          isLender:      isLender,
          convoData:     convoData,
          itemData:      itemData,
          lenderName:    displayName(lenderDoc, 'Lender'),
          lenderEmail:   email(lenderDoc, ''),
          borrowerName:  displayName(borrowerDoc, 'Borrower'),
          borrowerEmail: email(borrowerDoc, ''),
        ),
      ),
    );

    if (signedResult == true && mounted) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.convoId)
            .get();
        final updatedData = snap.data() ?? {};
        final bool isFullySigned = updatedData['contractSigned'] == true ||
            (updatedData['contractLenderSigned'] == true &&
                updatedData['contractBorrowerSigned'] == true);
        final bool handoffDone =
            updatedData['isPaid'] == true && updatedData['isReceived'] == true;

        if (isFullySigned && !handoffDone && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Both parties signed! Tap "Confirm Handoff" below to scan QR and exchange item.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2ECC71),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _openItemReviewDialog({
    required String itemId,
    required String itemTitle,
    required String ownerId,
    required String ownerName,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit a review.')),
      );
      return;
    }
    if (currentUser.uid == ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot review your own listing.')),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ReviewDialog(
        revieweeId: ownerId,
        targetName: ownerName.isNotEmpty ? ownerName : widget.otherUserName,
        itemId: itemId,
        itemTitle: itemTitle,
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _openUserReviewDialog({
    required String targetUserId,
    required String targetUserName,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit a review.')),
      );
      return;
    }
    if (currentUser.uid == targetUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot review yourself.')),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ReviewDialog(
        revieweeId: targetUserId,
        targetName: targetUserName.isNotEmpty ? targetUserName : 'User',
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _navigateToItemDetail(String itemId, Map<String, dynamic> itemData) async {
    if (itemId.isEmpty) return;
    Map<String, dynamic> data = Map<String, dynamic>.from(itemData);
    if (data.isEmpty) {
      try {
        final snap = await FirebaseFirestore.instance.collection('items').doc(itemId).get();
        if (snap.exists && snap.data() != null) {
          data = snap.data()!;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(
          itemId: itemId,
          itemData: data,
        ),
      ),
    );
  }

  void _promptPostReturnReview({
    required String itemId,
    required String itemName,
    required String ownerId,
    required String ownerName,
  }) {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded, color: Colors.amber, size: 36),
              ),
              const SizedBox(height: 12),
              const Text(
                'How was your rental experience?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Help the Lendly community by sharing a review and rating for "$itemName".',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openItemReviewDialog(
                      itemId: itemId,
                      itemTitle: itemName,
                      ownerId: ownerId,
                      ownerName: ownerName,
                    );
                  },
                  icon: const Icon(Icons.star, color: Colors.white, size: 18),
                  label: const Text('Review This Item', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B40B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Maybe Later', style: TextStyle(color: Colors.grey[600])),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _openQrScreen(String action, Map<String, dynamic> convoData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final itemId = _getEffectiveItemId(convoData);
    String itemName = 'Item';
    String ownerId = convoData['itemOwnerId'] ?? convoData['ownerId'] ?? '';
    String ownerName = widget.otherUserName;

    if (itemId.isNotEmpty) {
      final itemSnap = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .get();
      if (itemSnap.exists) {
        final d = itemSnap.data() as Map<String, dynamic>;
        itemName = d['name'] ?? d['title'] ?? 'Item';
        if (ownerId.isEmpty) ownerId = d['ownerId'] ?? '';
        if (d['ownerName'] != null) ownerName = d['ownerName'];
      }
    }

    if (!mounted) return;
    final result = await Navigator.push<bool>(
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

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action == 'handoff'
                      ? '✓ Handoff confirmed! Item exchange complete.'
                      : action == 'appraisal_meetup'
                          ? '✓ In-person meetup confirmed! Appraiser may now inspect and submit the appraisal.'
                          : '✓ Return confirmed! Transaction concluded.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: action == 'handoff'
              ? const Color(0xFF3498DB)
              : action == 'appraisal_meetup'
                  ? const Color(0xFF059669)
                  : const Color(0xFF7B40B5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );

      // Prompt borrower to review the item when return is confirmed
      if (action == 'return') {
        final isOwner = convoData['itemOwnerId'] == widget.currentUserId ||
            convoData['ownerId'] == widget.currentUserId;
        if (!isOwner && itemId.isNotEmpty) {
          _promptPostReturnReview(
            itemId: itemId,
            itemName: itemName,
            ownerId: ownerId.isNotEmpty ? ownerId : widget.otherUserId,
            ownerName: ownerName,
          );
        }
      }
    }
  }

  void _openAppraisalModalFromChat(
    Map<String, dynamic> convoData,
    Map<String, dynamic> itemData,
    String itemId,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppraisalFormDialog(
        itemData: itemData,
        itemId: itemId,
        convoId: widget.convoId,
        isMeetupPreVerified: true,
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
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
    return StreamBuilder<DocumentSnapshot>(
      stream: _conversationStream,
      builder: (context, convoSnap) {
        final convoData = convoSnap.hasData && convoSnap.data!.exists
            ? convoSnap.data!.data() as Map<String, dynamic>? ?? {}
            : <String, dynamic>{};

        final effectiveItemId = _getEffectiveItemId(convoData);
        final isOwner = convoData['itemOwnerId'] == widget.currentUserId ||
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
        final lenderSigned       = convoData['contractLenderSigned']   == true;
        final borrowerSigned     = convoData['contractBorrowerSigned'] == true;
        final contractSigned     = convoData['contractSigned'] == true ||
            (lenderSigned && borrowerSigned);
        final iHaveSigned        = isOwner ? lenderSigned : borrowerSigned;

        // Self-heal Firestore if both signed but contractSigned flag was not set
        if (lenderSigned && borrowerSigned && convoData['contractSigned'] != true) {
          FirebaseFirestore.instance
              .collection('conversations')
              .doc(widget.convoId)
              .update({
            'contractSigned': true,
            'contractFinalizedAt': FieldValue.serverTimestamp(),
          }).catchError((_) {});
        }

        final isAppraisalChat = convoData['conversationType'] == 'appraisal';
        final isMeetupConfirmed = convoData['isMeetupConfirmed'] == true;
        final isAppraisalCompleted = convoData['isAppraisalCompleted'] == true;
        final appraiserId = convoData['appraiserId'] as String? ?? '';
        final isAppraiser = (widget.currentUserId == appraiserId) || (!isOwner && isAppraisalChat);

        final ownerId = convoData['ownerId'] ?? convoData['itemOwnerId'] ?? '';
        final borrowerId = convoData['borrowerId'] ??
            ((convoData['participants'] as List<dynamic>?)?.firstWhere(
              (id) => id != ownerId,
              orElse: () => '',
            ) as String? ?? '');

        return StreamBuilder<DocumentSnapshot>(
          stream: effectiveItemId.isNotEmpty
              ? FirebaseFirestore.instance.collection('items').doc(effectiveItemId).snapshots()
              : null,
          builder: (context, itemSnap) {
            Map<String, dynamic> itemData = {};
            if (itemSnap.hasData && itemSnap.data != null && itemSnap.data!.exists) {
              itemData = itemSnap.data!.data() as Map<String, dynamic>? ?? {};
            }

            final itemName = itemData['name'] ?? itemData['title'] ?? 'Item';
            final itemOwnerId = itemData['ownerId'] as String? ?? ownerId;
            final itemOwnerName = itemData['ownerName'] as String? ?? widget.otherUserName;

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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.otherUserName,
                                style: const TextStyle(
                                    color: Color(0xFF1A1A2E),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                effectiveItemId.isNotEmpty ? itemName : 'Lendly Chat',
                                style: const TextStyle(
                                    color: Colors.black45, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                actions: [
                  if (!isAppraisalChat && !isOwner && effectiveItemId.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.star_rounded, color: Colors.amber),
                      tooltip: 'Rate & Review Item',
                      onPressed: () => _openItemReviewDialog(
                        itemId: effectiveItemId,
                        itemTitle: itemName,
                        ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                        ownerName: itemOwnerName,
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF1A1A2E)),
                    onSelected: (val) async {
                      if (val == 'view_contract') {
                        _openContractPage(convoData);
                      } else if (val == 'review_item') {
                        _openItemReviewDialog(
                          itemId: effectiveItemId,
                          itemTitle: itemName,
                          ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                          ownerName: itemOwnerName,
                        );
                      } else if (val == 'view_item') {
                        _navigateToItemDetail(effectiveItemId, itemData);
                      } else if (val == 'clear_chat') {
                        final ok = await _showConfirmDialog(
                          title: 'Clear Chat',
                          message: 'Delete all messages? The conversation record will remain.',
                          confirmLabel: 'Clear',
                          confirmColor: Colors.red,
                        );
                        if (ok == true) {
                          await _clearChatMessages();
                          Fluttertoast.showToast(msg: 'Chat cleared');
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (!isAppraisalChat && contractSigned)
                        const PopupMenuItem(
                          value: 'view_contract',
                          child: Row(
                            children: [
                              Icon(Icons.description_outlined, color: Color(0xFF2E7D32), size: 18),
                              SizedBox(width: 8),
                              Text('View Signed Contract'),
                            ],
                          ),
                        ),
                      if (!isAppraisalChat && !isOwner && effectiveItemId.isNotEmpty)
                        const PopupMenuItem(
                          value: 'review_item',
                          child: Row(
                            children: [
                              Icon(Icons.rate_review_outlined, color: Color(0xFF7B40B5), size: 18),
                              SizedBox(width: 8),
                              Text('Rate & Review Item'),
                            ],
                          ),
                        ),
                      if (effectiveItemId.isNotEmpty)
                        const PopupMenuItem(
                          value: 'view_item',
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, color: Color(0xFF7B40B5), size: 18),
                              SizedBox(width: 8),
                              Text('View Item Details'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'clear_chat',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Clear Chat'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              body: !convoSnap.hasData
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)))
                  : Column(
                      children: [
                        // Pinned header card (Appraisal vs Borrow Request)
                        if (isAppraisalChat)
                          _AppraisalHeaderCard(
                            convoData: convoData,
                            itemId: effectiveItemId,
                            itemData: itemData,
                            isAppraiser: isAppraiser,
                            isOwner: isOwner,
                            isMeetupConfirmed: isMeetupConfirmed,
                            isAppraisalCompleted: isAppraisalCompleted,
                            onViewItem: effectiveItemId.isNotEmpty
                                ? () => _navigateToItemDetail(effectiveItemId, itemData)
                                : null,
                          )
                        else
                          _BorrowRequestCard(
                            convoData: convoData,
                            itemId: effectiveItemId,
                            itemData: itemData,
                            isOwner: isOwner,
                            onViewItem: effectiveItemId.isNotEmpty
                                ? () => _navigateToItemDetail(effectiveItemId, itemData)
                                : null,
                            onReviewItem: (!isOwner && effectiveItemId.isNotEmpty)
                                ? () => _openItemReviewDialog(
                                      itemId: effectiveItemId,
                                      itemTitle: itemName,
                                      ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                                      ownerName: itemOwnerName,
                                    )
                                : null,
                            onViewContract: contractSigned
                                ? () => _openContractPage(convoData)
                                : null,
                          ),

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

                                  if (type == 'appraisal_request') {
                                    return _AppraisalRequestMessage(
                                      msg: msg,
                                      isMe: msg['senderId'] == widget.currentUserId,
                                      onViewItem: effectiveItemId.isNotEmpty
                                          ? () => _navigateToItemDetail(effectiveItemId, itemData)
                                          : null,
                                    );
                                  }

                                  if (type == 'appraisal_completed') {
                                    return _AppraisalCompletedMessage(
                                      msg: msg,
                                      isMe: msg['senderId'] == widget.currentUserId,
                                    );
                                  }

                                  if (type == 'borrow_request') {
                                    return _BorrowRequestMessage(
                                      msg: msg,
                                      isMe: msg['senderId'] == widget.currentUserId,
                                      onViewItem: effectiveItemId.isNotEmpty
                                          ? () => _navigateToItemDetail(effectiveItemId, itemData)
                                          : null,
                                      onReviewItem: (!isOwner && effectiveItemId.isNotEmpty)
                                          ? () => _openItemReviewDialog(
                                                itemId: effectiveItemId,
                                                itemTitle: itemName,
                                                ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                                                ownerName: itemOwnerName,
                                              )
                                          : null,
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
                        if (isAppraisalChat)
                          _AppraisalStatusBar(
                            isMeetupConfirmed: isMeetupConfirmed,
                            isAppraisalCompleted: isAppraisalCompleted,
                            isAppraiser: isAppraiser,
                          )
                        else
                          _StatusBar(
                            isApproved: isApproved,
                            isDenied: isDenied,
                            isFullyDone: isFullyDone,
                            isPaid: isPaid,
                            isReceived: isReceived,
                            isReturned: isReturned,
                            isReturnConfirmed: isReturnConfirmed,
                            isOwner: isOwner,
                            contractSigned: contractSigned,
                          ),

                        // Appraisal Action Panel (In-Person Meetup QR Scan + Appraise Item)
                        if (isAppraisalChat)
                          _AppraisalActionPanel(
                            isAppraiser: isAppraiser,
                            isMeetupConfirmed: isMeetupConfirmed,
                            isAppraisalCompleted: isAppraisalCompleted,
                            onConfirmMeetup: () =>
                                _openQrScreen('appraisal_meetup', convoData),
                            onAppraiseItem: () =>
                                _openAppraisalModalFromChat(convoData, itemData, effectiveItemId),
                          ),

                        // Owner: approve / deny (Rental only)
                        if (!isAppraisalChat && !isDenied && !isFullyDone && isOwner && !isApproved)
                          _OwnerActionPanel(
                            onApprove: _approveRequest,
                            onDeny: _denyRequest,
                          ),

                        // Contract signing panel — shown after approval until both sign (Rental only)
                        if (!isAppraisalChat && isApproved && !isFullyDone && !contractSigned)
                          _ContractSigningPanel(
                            contractSigned:  contractSigned,
                            lenderSigned:    lenderSigned,
                            borrowerSigned:  borrowerSigned,
                            iHaveSigned:     iHaveSigned,
                            onOpenContract:  () => _openContractPage(convoData),
                          ),

                        // QR handoff/return buttons → only after contract is signed (Rental only)
                        if (!isAppraisalChat && isApproved && !isFullyDone && contractSigned)
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

                        // Review callout panel: shown after completion (Rental only)
                        if (!isAppraisalChat && (isFullyDone || (isReturned && isReturnConfirmed)))
                          _CompletedReviewPanel(
                            itemId: effectiveItemId,
                            itemName: itemName,
                            itemImageUrl: (itemData['imageUrls'] is List && itemData['imageUrls'].isNotEmpty)
                                ? itemData['imageUrls'][0]
                                : null,
                            ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                            ownerName: itemOwnerName,
                            isOwner: isOwner,
                            borrowerId: borrowerId.isNotEmpty ? borrowerId : widget.otherUserId,
                            borrowerName: isOwner ? widget.otherUserName : 'Borrower',
                            currentUserId: widget.currentUserId,
                            onReviewItem: () => _openItemReviewDialog(
                              itemId: effectiveItemId,
                              itemTitle: itemName,
                              ownerId: itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId,
                              ownerName: itemOwnerName,
                            ),
                            onReviewUser: () => _openUserReviewDialog(
                              targetUserId: isOwner
                                  ? (borrowerId.isNotEmpty ? borrowerId : widget.otherUserId)
                                  : (itemOwnerId.isNotEmpty ? itemOwnerId : widget.otherUserId),
                              targetUserName: isOwner ? widget.otherUserName : itemOwnerName,
                            ),
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
                    ),
            );
          },
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Pinned Borrow Request & Item Card (top of chat)
// ────────────────────────────────────────────────────────────────────────────

class _BorrowRequestCard extends StatelessWidget {
  final Map<String, dynamic> convoData;
  final String itemId;
  final Map<String, dynamic> itemData;
  final bool isOwner;
  final VoidCallback? onViewItem;
  final VoidCallback? onReviewItem;
  final VoidCallback? onViewContract;

  const _BorrowRequestCard({
    required this.convoData,
    required this.itemId,
    required this.itemData,
    required this.isOwner,
    this.onViewItem,
    this.onReviewItem,
    this.onViewContract,
  });

  @override
  Widget build(BuildContext context) {
    final startStr = convoData['startDate'] as String?;
    final endStr = convoData['endDate'] as String?;
    final bool hasDates = startStr != null && endStr != null;
    final start = hasDates ? DateTime.tryParse(startStr) : null;
    final end = hasDates ? DateTime.tryParse(endStr) : null;

    if (!hasDates && itemId.isEmpty) return const SizedBox.shrink();

    final totalDays = convoData['totalDays'] as int? ?? 0;
    final totalPrice =
        (convoData['totalPrice'] as num?)?.toDouble() ?? 0;
    final fmt = DateFormat('MMM d, yyyy');
    final isApproved = convoData['approved'] == true;
    final isDenied = convoData['denied'] == true;
    final isFullyDone = convoData['isPaid'] == true &&
        convoData['isReceived'] == true &&
        convoData['isReturned'] == true &&
        convoData['isReturnConfirmed'] == true;

    final itemName = itemData['name'] ?? itemData['title'] ?? 'Item';
    final imageUrl = (itemData['imageUrls'] is List && itemData['imageUrls'].isNotEmpty)
        ? itemData['imageUrls'][0]
        : (itemData['imageUrl'] as String?);
    final rating = (itemData['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (itemData['reviewCount'] as num?)?.toInt() ?? 0;

    final statusColor = isDenied
        ? Colors.red
        : isFullyDone
            ? const Color(0xFF2ECC71)
            : isApproved
                ? const Color(0xFF2ECC71)
                : const Color(0xFFE67E22);
    final statusLabel = isDenied
        ? '✗ Denied'
        : isFullyDone
            ? '✓ Completed'
            : isApproved
                ? '✓ Accepted'
                : '⏳ Pending';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
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
          // Top row: Item thumbnail, Title, Status chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isValidImageUrl(imageUrl))
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey[200],
                      child: const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, size: 22, color: Color(0xFF7B40B5)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (rating > 0) ...[
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            '${rating.toStringAsFixed(1)} ($reviewCount)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (totalPrice > 0)
                          Text(
                            '₱${totalPrice.toStringAsFixed(0)} total',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7B40B5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          // Date chips if available
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Chip(
                  icon: Icons.calendar_today_outlined,
                  text: '${fmt.format(start)} — ${fmt.format(end)}',
                ),
                _Chip(
                  icon: Icons.timelapse,
                  text: '$totalDays day${totalDays > 1 ? 's' : ''}',
                ),
              ],
            ),
          ],

          // Action row: View Listing & Review Item & Signed Contract
          const Divider(height: 16),
          Row(
            children: [
              if (onViewItem != null)
                InkWell(
                  onTap: onViewItem,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF7B40B5)),
                        SizedBox(width: 4),
                        Text(
                          'View Listing',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (onViewContract != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onViewContract,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 13, color: Color(0xFF2E7D32)),
                        SizedBox(width: 4),
                        Text(
                          'Signed Contract',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (!isOwner && onReviewItem != null)
                InkWell(
                  onTap: onReviewItem,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Rate & Review',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
  final VoidCallback? onViewItem;
  final VoidCallback? onReviewItem;

  const _BorrowRequestMessage({
    required this.msg,
    required this.isMe,
    this.onViewItem,
    this.onReviewItem,
  });

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
            if (onViewItem != null || onReviewItem != null) ...[
              const Divider(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onViewItem != null)
                    TextButton.icon(
                      onPressed: onViewItem,
                      icon: const Icon(Icons.open_in_new, size: 13),
                      label: const Text('View Listing', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7B40B5),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      ),
                    ),
                  if (onReviewItem != null) ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: onReviewItem,
                      icon: const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      label: const Text('Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7B40B5),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ],
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
                border: isMe
                    ? null
                    : Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                      color:
                          Colors.black.withValues(alpha: 0.04),
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
  final bool isOwner;
  final bool contractSigned;

  const _StatusBar({
    required this.isApproved,
    required this.isDenied,
    required this.isFullyDone,
    required this.isPaid,
    required this.isReceived,
    required this.isReturned,
    required this.isReturnConfirmed,
    this.isOwner = false,
    this.contractSigned = false,
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
      label = isOwner
          ? 'Transaction complete! Item returned safely.'
          : 'Transaction complete! Please rate & review the item.';
    } else if (isApproved && isReceived) {
      bg = const Color(0xFFEDF7FF);
      icon = Icons.inventory_2_outlined;
      label = 'Item borrowed — return pending.';
    } else if (isApproved && contractSigned) {
      bg = const Color(0xFFE8F8F0);
      icon = Icons.handshake_outlined;
      label = 'Contract signed — meet up & scan QR for item handoff.';
    } else if (isApproved) {
      bg = const Color(0xFFF0E8FF);
      icon = Icons.description_outlined;
      label = 'Request accepted — sign electronic contract to proceed.';
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
                ? (contractSigned ? const Color(0xFF2E7D32) : const Color(0xFF7B40B5))
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
// Completed Review Panel (Post-transaction review callout in chat)
// ────────────────────────────────────────────────────────────────────────────

class _CompletedReviewPanel extends StatelessWidget {
  final String itemId;
  final String itemName;
  final String? itemImageUrl;
  final String ownerId;
  final String ownerName;
  final bool isOwner;
  final String borrowerId;
  final String borrowerName;
  final String currentUserId;
  final VoidCallback onReviewItem;
  final VoidCallback onReviewUser;

  const _CompletedReviewPanel({
    required this.itemId,
    required this.itemName,
    this.itemImageUrl,
    required this.ownerId,
    required this.ownerName,
    required this.isOwner,
    required this.borrowerId,
    required this.borrowerName,
    required this.currentUserId,
    required this.onReviewItem,
    required this.onReviewUser,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOwner) {
      // Borrower view: Review the ITEM (and Lender)
      if (itemId.isEmpty) {
        return const SizedBox.shrink();
      }

      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reviews')
            .where('reviewerId', isEqualTo: currentUserId)
            .where('itemId', isEqualTo: itemId)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.hasData ? snapshot.data!.docs : [];
          final bool hasReviewed = docs.isNotEmpty;
          final double rating = hasReviewed
              ? ((docs.first.data() as Map<String, dynamic>)['rating'] as num?)?.toDouble() ?? 5.0
              : 5.0;
          final String comment = hasReviewed
              ? ((docs.first.data() as Map<String, dynamic>)['comment'] as String?) ?? ''
              : '';

          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasReviewed
                    ? [const Color(0xFFF3E8FF), const Color(0xFFEDE9FE)]
                    : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasReviewed
                    ? const Color(0xFF7B40B5).withValues(alpha: 0.3)
                    : Colors.amber.shade300,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasReviewed ? const Color(0xFF7B40B5) : Colors.amber.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasReviewed ? Icons.verified_rounded : Icons.star_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasReviewed ? 'You Reviewed This Item' : 'How was the item?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: hasReviewed ? const Color(0xFF5B21B6) : const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasReviewed
                                ? 'Thank you for rating "$itemName"!'
                                : 'Rate "$itemName" to help the community.',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasReviewed ? Colors.purple.shade900 : Colors.brown.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (hasReviewed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7B40B5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (hasReviewed && comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '"$comment"',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onReviewItem,
                        icon: Icon(
                          hasReviewed ? Icons.edit_outlined : Icons.rate_review_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          hasReviewed ? 'Edit Your Review' : 'Rate & Review Item',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasReviewed ? const Color(0xFF7B40B5) : Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } else {
      // Owner view: Rate the BORROWER
      final targetUserId = borrowerId.isNotEmpty ? borrowerId : '';
      if (targetUserId.isEmpty) return const SizedBox.shrink();

      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reviews')
            .where('reviewerId', isEqualTo: currentUserId)
            .where('revieweeId', isEqualTo: targetUserId)
            .where('itemId', isNull: true)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.hasData ? snapshot.data!.docs : [];
          final bool hasReviewed = docs.isNotEmpty;

          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasReviewed
                    ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
                    : const Color(0xFF7B40B5).withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasReviewed
                            ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                            : const Color(0xFF7B40B5).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasReviewed ? Icons.verified_user : Icons.person_pin_rounded,
                        color: hasReviewed ? const Color(0xFF2ECC71) : const Color(0xFF7B40B5),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasReviewed ? 'Borrower Reviewed' : 'Rate Borrower',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            hasReviewed
                                ? 'You reviewed $borrowerName.'
                                : 'How was your lending experience with $borrowerName?',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onReviewUser,
                      icon: Icon(hasReviewed ? Icons.edit_outlined : Icons.star_rate_rounded, size: 16),
                      label: Text(hasReviewed ? 'Edit' : 'Rate'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7B40B5),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
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
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 1.5),
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

// ────────────────────────────────────────────────────────────────────────────
// Appraisal Header Card (Top of chat for appraisal coordination)
// ────────────────────────────────────────────────────────────────────────────

class _AppraisalHeaderCard extends StatelessWidget {
  final Map<String, dynamic> convoData;
  final String itemId;
  final Map<String, dynamic> itemData;
  final bool isAppraiser;
  final bool isOwner;
  final bool isMeetupConfirmed;
  final bool isAppraisalCompleted;
  final VoidCallback? onViewItem;

  const _AppraisalHeaderCard({
    required this.convoData,
    required this.itemId,
    required this.itemData,
    required this.isAppraiser,
    required this.isOwner,
    required this.isMeetupConfirmed,
    required this.isAppraisalCompleted,
    this.onViewItem,
  });

  @override
  Widget build(BuildContext context) {
    final itemName = itemData['name'] ?? itemData['title'] ?? convoData['itemName'] ?? 'Item';
    final imageUrl = (itemData['imageUrls'] is List && itemData['imageUrls'].isNotEmpty)
        ? itemData['imageUrls'][0]
        : (itemData['imageUrl'] as String?);
    final appraiserBiz = convoData['appraiserBusinessName'] ?? 'Licensed Appraiser';
    final conditionGrade = itemData['conditionGrade'] ?? convoData['conditionGrade'];

    final statusColor = isAppraisalCompleted
        ? const Color(0xFF059669)
        : isMeetupConfirmed
            ? const Color(0xFF0284C7)
            : const Color(0xFF7B40B5);

    final statusLabel = isAppraisalCompleted
        ? '✓ Certified'
        : isMeetupConfirmed
            ? '✓ Met In-Person'
            : '1. Coordinate Meetup';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isValidImageUrl(imageUrl))
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey[200],
                      child: const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.verified_outlined, size: 22, color: Color(0xFF7B40B5)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.business_outlined, size: 12, color: Colors.grey),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            'Appraiser: $appraiserBiz',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          // Steps progression indicator
          const SizedBox(height: 10),
          Row(
            children: [
              _AppraisalStepIndicator(
                stepNum: '1',
                label: 'Message',
                active: true,
                done: isMeetupConfirmed || isAppraisalCompleted,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: isMeetupConfirmed ? const Color(0xFF059669) : Colors.grey[300],
                ),
              ),
              _AppraisalStepIndicator(
                stepNum: '2',
                label: 'Scan QR',
                active: true,
                done: isMeetupConfirmed,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: isAppraisalCompleted ? const Color(0xFF059669) : Colors.grey[300],
                ),
              ),
              _AppraisalStepIndicator(
                stepNum: '3',
                label: 'Appraise',
                active: isMeetupConfirmed,
                done: isAppraisalCompleted,
              ),
            ],
          ),

          if (isAppraisalCompleted && conditionGrade != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, size: 14, color: Color(0xFF059669)),
                  const SizedBox(width: 6),
                  Text(
                    'Certified Condition: $conditionGrade',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),
            ),
          ],

          if (onViewItem != null) ...[
            const Divider(height: 14),
            InkWell(
              onTap: onViewItem,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF7B40B5)),
                  SizedBox(width: 4),
                  Text(
                    'View Item Listing',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppraisalStepIndicator extends StatelessWidget {
  final String stepNum;
  final String label;
  final bool active;
  final bool done;

  const _AppraisalStepIndicator({
    required this.stepNum,
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF059669)
        : active
            ? const Color(0xFF7B40B5)
            : Colors.grey;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? const Color(0xFF059669) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: done
              ? const Icon(Icons.check, size: 11, color: Colors.white)
              : Text(
                  stepNum,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: color),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Appraisal Status Bar
// ────────────────────────────────────────────────────────────────────────────

class _AppraisalStatusBar extends StatelessWidget {
  final bool isMeetupConfirmed;
  final bool isAppraisalCompleted;
  final bool isAppraiser;

  const _AppraisalStatusBar({
    required this.isMeetupConfirmed,
    required this.isAppraisalCompleted,
    required this.isAppraiser,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    IconData icon;
    String label;
    Color fg;

    if (isAppraisalCompleted) {
      bg = const Color(0xFFE8F8F0);
      icon = Icons.verified_rounded;
      fg = const Color(0xFF059669);
      label = 'Official appraisal certified! Condition grade has been published.';
    } else if (isMeetupConfirmed) {
      bg = const Color(0xFFEDF7FF);
      icon = Icons.handshake_rounded;
      fg = const Color(0xFF0284C7);
      label = isAppraiser
          ? 'Physical meetup verified! Inspect the item and complete the rating below.'
          : 'Physical meetup verified! The appraiser is now inspecting your item.';
    } else {
      bg = const Color(0xFFF3E8FF);
      icon = Icons.qr_code_scanner_rounded;
      fg = const Color(0xFF7B40B5);
      label = 'Agree where to meet in person, then scan QR code together to confirm meetup.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bg,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Appraisal Action Panel
// ────────────────────────────────────────────────────────────────────────────

class _AppraisalActionPanel extends StatelessWidget {
  final bool isAppraiser;
  final bool isMeetupConfirmed;
  final bool isAppraisalCompleted;
  final VoidCallback onConfirmMeetup;
  final VoidCallback onAppraiseItem;

  const _AppraisalActionPanel({
    required this.isAppraiser,
    required this.isMeetupConfirmed,
    required this.isAppraisalCompleted,
    required this.onConfirmMeetup,
    required this.onAppraiseItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appraisal Anti-Fraud Verification Flow',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Step 1: In-Person Meetup QR Scan
              Expanded(
                child: _QBtn(
                  icon: Icons.qr_code_scanner,
                  label: isMeetupConfirmed ? 'Meetup Done ✓' : 'Scan Meetup QR',
                  sublabel: isMeetupConfirmed ? 'Verified in-person' : 'Confirm in-person meetup',
                  done: isMeetupConfirmed,
                  color: const Color(0xFF0284C7),
                  onTap: isMeetupConfirmed ? null : onConfirmMeetup,
                ),
              ),
              const SizedBox(width: 10),
              // Step 2: Appraise & Certify
              Expanded(
                child: isAppraiser
                    ? _QBtn(
                        icon: Icons.verified_outlined,
                        label: isAppraisalCompleted ? 'Appraised ✓' : 'Appraise Item',
                        sublabel: !isMeetupConfirmed
                            ? 'Locked (Meetup required)'
                            : isAppraisalCompleted
                                ? 'Certified & Published'
                                : 'Rate Function & Cosmetic',
                        done: isAppraisalCompleted,
                        color: const Color(0xFF059669),
                        onTap: (!isMeetupConfirmed)
                            ? null
                            : onAppraiseItem,
                      )
                    : _QBtn(
                        icon: Icons.verified_outlined,
                        label: isAppraisalCompleted ? 'Appraised ✓' : 'Item Inspection',
                        sublabel: isAppraisalCompleted ? 'Certified & Published' : (isMeetupConfirmed ? 'Appraiser inspecting' : 'Awaiting meetup'),
                        done: isAppraisalCompleted,
                        color: const Color(0xFF059669),
                        onTap: null,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Appraisal Request & Completed Message Cards
// ────────────────────────────────────────────────────────────────────────────

class _AppraisalRequestMessage extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;
  final VoidCallback? onViewItem;

  const _AppraisalRequestMessage({
    required this.msg,
    required this.isMe,
    this.onViewItem,
  });

  @override
  Widget build(BuildContext context) {
    final itemName = msg['itemName'] ?? 'Item';
    final appraiserBiz = msg['appraiserBusinessName'] ?? 'Licensed Appraiser';
    final text = msg['text'] ?? '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF7B40B5).withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined, size: 16, color: Color(0xFF7B40B5)),
                SizedBox(width: 6),
                Text(
                  'Official Appraisal Request',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7B40B5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _R(icon: Icons.inventory_2_outlined, label: 'Item', value: itemName, bold: true),
            const SizedBox(height: 6),
            _R(icon: Icons.business_outlined, label: 'Appraiser', value: appraiserBiz),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
            if (onViewItem != null) ...[
              const Divider(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onViewItem,
                  icon: const Icon(Icons.open_in_new, size: 13),
                  label: const Text('View Listing', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7B40B5),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppraisalCompletedMessage extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;

  const _AppraisalCompletedMessage({
    required this.msg,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final grade = msg['conditionGrade'] ?? 'Certified';
    final fnScore = msg['functionScore'] ?? '-';
    final cosScore = msg['cosmeticScore'] ?? '-';
    final certId = msg['certificateId'] ?? 'CERT-APPRAISED';
    final defectCount = msg['defectCount'] as num? ?? 0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium, size: 18, color: Color(0xFF15803D)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Appraisal Certified & Submitted',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Text('Certified Grade: ', style: TextStyle(fontSize: 12, color: Colors.black54)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    grade,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Scores: Function ($fnScore/10) • Cosmetic ($cosScore/10)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534))),
            const SizedBox(height: 4),
            Text('Certificate ID: $certId',
                style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
            if (defectCount > 0) ...[
              const SizedBox(height: 4),
              Text('$defectCount defect(s) documented during physical inspection',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}
