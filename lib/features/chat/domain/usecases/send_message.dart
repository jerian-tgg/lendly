import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class SendMessage {
  final ChatRepository repository;

  SendMessage(this.repository);

  Future<void> call(String convoId, ChatMessage message) =>
      repository.sendMessage(convoId, message);
}