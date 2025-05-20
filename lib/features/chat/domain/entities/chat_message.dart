import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String convoId;  // Added convoId here
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final bool seen;
  final String? type;

  ChatMessage({
    required this.id,
    required this.convoId,  // required
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    required this.seen,
    this.type,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] ?? '',
      convoId: map['convoId'] ?? '',
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      timestamp: map['timestamp'] != null && map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      seen: map['seen'] ?? false,
      type: map['type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'convoId': convoId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'seen': seen,
      'type': type,
    };
  }
}
