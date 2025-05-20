import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/chat_message.dart';

class ChatMessageModel {
  final String id;
  final String convoId;    // Added convoId
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final bool seen;
  final String? type;      // Added optional type

  ChatMessageModel({
    required this.id,
    required this.convoId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    required this.seen,
    this.type,
  });

  // Create model from Firestore document snapshot
  factory ChatMessageModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ChatMessageModel(
      id: doc.id,
      convoId: data['convoId'] ?? '',
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      text: data['text'] as String,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      seen: data['seen'] ?? false,
      type: data['type'],
    );
  }

  // Convert model to Firestore data map
  Map<String, dynamic> toMap() {
    return {
      'convoId': convoId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'seen': seen,
      'type': type,
    };
  }

  // Convert model to domain entity
  ChatMessage toEntity() {
    return ChatMessage(
      id: id,
      convoId: convoId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      timestamp: timestamp,
      seen: seen,
      type: type,
    );
  }
}
