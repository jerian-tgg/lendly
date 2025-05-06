import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class GetMessages {
  final ChatRepository repository;

  GetMessages(this.repository);

  Stream<List<ChatMessage>> call(String convoId) => repository.getMessages(convoId);
}