import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message_model.dart';

abstract class ChatRemoteDataSource {
  Stream<List<ChatMessageModel>> getMessages(String convoId);
  Future<void> sendMessage(String convoId, ChatMessageModel message);
}

class FirebaseChatDataSource implements ChatRemoteDataSource {
  final FirebaseFirestore _firestore;

  FirebaseChatDataSource(this._firestore);

  @override
  Stream<List<ChatMessageModel>> getMessages(String convoId) {
    return _firestore
        .collection('conversations')
        .doc(convoId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ChatMessageModel.fromDocument(doc))
        .toList());
  }

  @override
  Future<void> sendMessage(String convoId, ChatMessageModel message) async {
    await _firestore
        .collection('conversations')
        .doc(convoId)
        .collection('messages')
        .add(message.toMap());
  }
}
