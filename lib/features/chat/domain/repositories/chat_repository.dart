import '../entities/chat_message.dart';
import '../entities/conversation.dart';

abstract class ChatRepository {
  Stream<List<ChatMessage>> getMessages(String convoId);
  Future<void> sendMessage(String convoId, ChatMessage message);

  // Add this method to get conversations of a user:
  Stream<List<Conversation>> getUserConversations(String userId);
}
