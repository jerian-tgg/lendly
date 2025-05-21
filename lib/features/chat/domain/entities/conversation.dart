import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final List<String> participants;
  final DateTime lastUpdated;
  final String? lastMessageText;
  final String itemId;
  final String itemOwnerId;
  final bool approved;

  Conversation({
    required this.id,
    required this.participants,
    required this.lastUpdated,
    this.lastMessageText,
    required this.itemId,
    required this.itemOwnerId,
    required this.approved,
  });

  factory Conversation.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageText: data['lastMessageText'],
      itemId: data['itemId'] ?? '',
      itemOwnerId: data['itemOwnerId'] ?? '',
      approved: data['approved'] ?? false,
    );
  }
}
