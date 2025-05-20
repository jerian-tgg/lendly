import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/conversation.dart';

class ConversationModel extends Conversation {
  ConversationModel({
    required String id,
    required List<String> participants,
    required DateTime lastUpdated,
  }) : super(
    id: id,
    participants: participants,
    lastUpdated: lastUpdated,
  );

  factory ConversationModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ConversationModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastUpdated: (data['lastUpdated'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'lastUpdated': lastUpdated,
    };
  }
}
