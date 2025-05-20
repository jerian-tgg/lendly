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
      appBar: AppBar(
        title: const Text('Conversations'),
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: chatRepo.getUserConversations(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No conversations yet.'));
          }

          final conversations = snapshot.data!;

          return ListView.builder(
            itemCount: conversations.length,
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
                    return ListTile(title: Text("User not found"));
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                  final username = userData['username'] ?? otherUserId;
                  final profilePicUrl = userData['profilePicUrl'] as String?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: profilePicUrl != null
                          ? NetworkImage(profilePicUrl)
                          : const AssetImage('assets/default_avatar.png') as ImageProvider,
                    ),
                    title: Text(username),
                    subtitle: convo.lastMessageText != null
                        ? Text(convo.lastMessageText!)
                        : const Text('No messages yet.'),
                    trailing: Text(
                      _formatDate(convo.lastUpdated),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            convoId: convo.id,
                            currentUserId: currentUserId,
                            otherUserId: otherUserId,
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
