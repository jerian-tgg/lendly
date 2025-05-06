import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_message_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;

  ChatRepositoryImpl(this.remoteDataSource);

  @override
  Stream<List<ChatMessage>> getMessages(String convoId) {
    return remoteDataSource.getMessages(convoId);
  }

  @override
  Future<void> sendMessage(String convoId, ChatMessage message) {
    return remoteDataSource.sendMessage(
      convoId,
      ChatMessageModel(
        id: message.id,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: message.text,
        timestamp: message.timestamp,
      ),
    );
  }
}