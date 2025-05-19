import '../../domain/entities/chat_message.dart';
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
          messageModels.map((ChatMessageModel model) => model.toEntity()).toList(),
    );
  }


  @override
  Future<void> sendMessage(String convoId, ChatMessage message) {
    final messageId = FirebaseFirestore.instance.collection('conversations').doc(convoId).collection('messages').doc().id;

    return remoteDataSource.sendMessage(
      convoId,
      ChatMessageModel(
        id: messageId,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: message.text,
        timestamp: message.timestamp,
        seen: message.seen,
      ),
    );
  }


}
