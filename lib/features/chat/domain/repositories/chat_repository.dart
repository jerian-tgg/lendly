import '../entities/chat_message.dart';

abstract class ChatRepository {
  Stream<List<ChatMessage>> getMessages(String convoId);
  Future<void> sendMessage(String convoId, ChatMessage message);
}