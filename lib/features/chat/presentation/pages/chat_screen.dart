import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/datasources/chat_remote_data_source.dart' show FirebaseChatDataSource;
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/get_messages.dart';
import '../../domain/usecases/send_message.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String convoId;
  final String receiverId;

  const ChatScreen({
    super.key,
    required this.convoId,
    required this.receiverId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final ChatRepositoryImpl _repository;
  late final GetMessages _getMessages;
  late final SendMessage _sendMessage;

  String receiverName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _repository = ChatRepositoryImpl(FirebaseChatDataSource(_firestore));
    _getMessages = GetMessages(_repository);
    _sendMessage = SendMessage(_repository);
    _loadReceiverName();
  }

  Future<void> _loadReceiverName() async {
    final doc = await _firestore.collection('users').doc(widget.receiverId).get();
    final data = doc.data();
    setState(() {
      receiverName = data?['username'] ?? 'User';
    });
  }

  // Mark incoming messages as seen when viewed
  void _markMessagesAsSeen(List<ChatMessage> messages, String userId) {
    for (var message in messages) {
      if (message.receiverId == userId && !message.seen) {
        _firestore
            .collection('conversations')
            .doc(widget.convoId)
            .collection('messages')
            .doc(message.id)
            .update({'seen': true});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF90E0F3),
        title: Text(
          receiverName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _getMessages(widget.convoId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                _markMessagesAsSeen(messages, userId); // Mark unseen incoming messages as seen

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return ChatBubble(
                      message: message,
                      isMe: message.senderId == userId,
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF90E0F3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () async {
                      final text = _controller.text.trim();
                      if (text.isEmpty) return;

                      final message = ChatMessage(
                        id: '',
                        senderId: userId,
                        receiverId: widget.receiverId,
                        text: text,
                        timestamp: DateTime.now(),
                        seen: false,  // required now
                      );


                      await _sendMessage(widget.convoId, message);
                      _controller.clear();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
