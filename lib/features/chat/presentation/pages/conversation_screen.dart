// conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lendly/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lendly/features/chat/domain/entities/conversation.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';

class ConversationScreen extends StatelessWidget {
  final chatRepo = ChatRepositoryImpl(FirebaseChatDataSource(FirebaseFirestore.instance));

  ConversationScreen({super.key});

  String _getOtherUserId(List<String> participants, String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId, orElse: () => 'Unknown');
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF90E0F3),
        title: const Text(
          'Conversations',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: chatRepo.getUserConversations(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF90E0F3)));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No conversations yet.'));
          }

          final conversations = snapshot.data!;

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: conversations.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final convo = conversations[index];
              final otherUserId = _getOtherUserId(convo.participants, currentUserId);

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(title: Text("Loading..."));
                  }

                  if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                    return const ListTile(title: Text("User not found"));
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                  final username = userData['username'] ?? userData['name'] ?? 'User';
                  final profilePicUrl = userData['photoURL'] as String?;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundImage: profilePicUrl != null
                          ? NetworkImage(profilePicUrl)
                          : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                    ),
                    title: Text(
                      username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      convo.lastMessageText ?? 'No messages yet.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    trailing: Text(
                      _formatDate(convo.lastUpdated),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: const Color(0xFFF6FDFF),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            convoId: convo.id,
                            currentUserId: currentUserId,
                            otherUserId: otherUserId,
                            otherUserName: username,
                            itemId: convo.itemId,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}