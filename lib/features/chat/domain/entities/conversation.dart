import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final List<String> participants;
  final DateTime lastUpdated;
  final String? lastMessageText; // ✅ Optional last message text

  Conversation({
    required this.id,
    required this.participants,
    required this.lastUpdated,
    this.lastMessageText,
  });

  factory Conversation.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageText: data['lastMessageText'], // ✅ Extracted from Firestore
    );
  }
}
