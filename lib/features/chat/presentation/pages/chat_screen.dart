// chat_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:lendly/core/utils/image_utils.dart';

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

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final messageData = {
      'senderId': widget.currentUserId,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    final convoRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId);

    await convoRef.collection('messages').add(messageData);
    await convoRef.update({
      'lastMessageText': text.trim(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
  }

  void _approveRequest() async {
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId)
        .update({'approved': true});
  }

  Future<void> _markTransactionAsCompleted() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Transaction'),
        content: const Text('Are you sure you want to mark this transaction as completed?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Yes, Complete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.convoId)
          .update({'isCompleted': true});

      Fluttertoast.showToast(msg: "Transaction marked as completed.");
    }
  }

  Future<void> _confirmAndClearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('This will delete all messages in this conversation. The chat head will be preserved. Continue?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Clear'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _clearChatMessages();
        Fluttertoast.showToast(msg: 'Chat cleared');
      } catch (e) {
        Fluttertoast.showToast(msg: 'Failed to clear chat');
      }
    }
  }

  Future<void> _clearChatMessages() async {
    final convoRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.convoId);
    final messagesRef = convoRef.collection('messages');

    // Delete in batches to handle large conversations
    while (true) {
      final snapshot = await messagesRef.limit(500).get();
      if (snapshot.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // Optionally reset conversation preview fields but keep the convo doc
    await convoRef.update({
      'lastMessageText': FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: _userStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircleAvatar(
                    radius: 16,
                    child: CircularProgressIndicator(),
                  );
                }

                final photoUrl = snapshot.hasData && snapshot.data!.exists
                    ? (snapshot.data!.data() as Map<String, dynamic>)['photoURL']
                    : null;

                return CircleAvatar(
                  radius: 16,
                  backgroundImage: isValidImageUrl(photoUrl)
                      ? NetworkImage(photoUrl!)
                      : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                );
              },
            ),
            const SizedBox(width: 12),
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF90E0F3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: _confirmAndClearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(widget.convoId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == widget.currentUserId;

                    return Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0, bottom: 4),
                            child: Text(
                              widget.otherUserName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF90E0F3) : const Color(0xFFEDEDED),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isMe ? 20 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 20),
                            ),
                          ),
                          child: Text(
                            message['text'] ?? '',
                            style: TextStyle(
                              fontSize: 16,
                              color: isMe ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: _conversationStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();

              final convoData = snapshot.data!.data() as Map<String, dynamic>;
              final itemOwnerId = convoData['itemOwnerId'] ?? '';
              final isApproved = convoData['approved'] ?? false;
              final isCompleted = convoData['isCompleted'] ?? false;

              return Column(
                children: [
                  if (isCompleted)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        "✅ This transaction has been completed.",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  if (widget.currentUserId == itemOwnerId)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          if (!isApproved)
                            ElevatedButton.icon(
                              onPressed: _approveRequest,
                              icon: const Icon(Icons.check),
                              label: const Text("Approve Request"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                            )
                          else if (!isCompleted)
                            Column(
                              children: [
                                const Text(
                                  "You have approved this item request ✅",
                                  style: TextStyle(color: Colors.green),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _markTransactionAsCompleted,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text("Mark Transaction Complete"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        isCompleted
                            ? "✅ This transaction has been completed."
                            : isApproved
                            ? "Your request is approved ✅"
                            : "Waiting for owner approval...",
                        style: TextStyle(
                          color: isCompleted
                              ? Colors.grey
                              : isApproved
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: "Type your message...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
