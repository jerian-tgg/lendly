import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/chat_message.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../data/datasources/chat_remote_data_source.dart';

class ChatScreen extends StatefulWidget {
  final String convoId;
  final String currentUserId;
  final String otherUserId;
  final String? itemId; // Optional itemId for reference

  const ChatScreen({
    Key? key,
    required this.convoId,
    required this.currentUserId,
    required this.otherUserId,
    this.itemId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _chatRepo =
  ChatRepositoryImpl(FirebaseChatDataSource(FirebaseFirestore.instance));

  String? otherUserName;

  @override
  void initState() {
    super.initState();
    _fetchOtherUserName();
  }

  Future<void> _fetchOtherUserName() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();

    if (userDoc.exists) {
      setState(() {
        otherUserName = userDoc.data()?['username'] ?? widget.otherUserId;
      });
    } else {
      setState(() {
        otherUserName = widget.otherUserId; // fallback
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Chat with ${otherUserName ?? '...'}"),
            if (widget.itemId != null)
              Text(
                "Item ID: ${widget.itemId}",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatRepo.getMessages(widget.convoId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("No messages yet."));
                }

                final messages = snapshot.data!;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == widget.currentUserId;
                    return Align(
                      alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(msg.text),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration:
                    const InputDecoration(hintText: "Type a message..."),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final text = _messageController.text.trim();
                    if (text.isNotEmpty) {
                      final message = ChatMessage(
                        id: '',
                        convoId: widget.convoId,
                        senderId: widget.currentUserId,
                        receiverId: widget.otherUserId,
                        text: text,
                        timestamp: DateTime.now(),
                        seen: false,
                        type: 'text',
                      );
                      await _chatRepo.sendMessage(widget.convoId, message);
                      _messageController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
