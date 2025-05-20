import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart'; // ✅ Import Conversation
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;

  ChatRepositoryImpl(this.remoteDataSource);

  @override
  Stream<List<ChatMessage>> getMessages(String convoId) {
    return remoteDataSource.getMessages(convoId).map(
          (List<ChatMessageModel> messageModels) =>
          messageModels.map((model) => model.toEntity()).toList(),
    );
  }

  @override
  Future<void> sendMessage(String convoId, ChatMessage message) async {
    final convoRef = FirebaseFirestore.instance.collection('conversations').doc(convoId);
    final convoDoc = await convoRef.get();

    if (!convoDoc.exists) {
      await convoRef.set({
        'participants': [message.senderId, message.receiverId],
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastMessageText': message.text, // ✅ Add this
        'approved': false,
      });
    } else {
      await convoRef.update({
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastMessageText': message.text, // ✅ Add this
      });
    }

    final messageId = FirebaseFirestore.instance
        .collection('conversations')
        .doc(convoId)
        .collection('messages')
        .doc()
        .id;

    await remoteDataSource.sendMessage(
      convoId,
      ChatMessageModel(
        id: messageId,
        convoId: convoId,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: message.text,
        timestamp: message.timestamp,
        seen: message.seen,
        type: message.type ?? 'text',
      ),
    );
  }


  @override
  Stream<List<Conversation>> getUserConversations(String userId) {
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: userId)
        .orderBy('lastUpdated', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Conversation.fromDoc(doc)).toList());
  }
}
