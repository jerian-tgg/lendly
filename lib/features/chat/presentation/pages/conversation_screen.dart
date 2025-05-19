// features/chat/presentation/conversations_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart'; // where your individual chat logic is

class ConversationsScreen extends StatelessWidget {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final conversations = snapshot.data!.docs;

        return ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final convo = conversations[index];
            final participantIds = List<String>.from(convo['participants']);
            final otherUserId = participantIds.firstWhere((id) => id != currentUserId);

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) return const ListTile(title: Text("Loading..."));

                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final username = userData['username'] ?? 'User';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(userData['photoURL'] ?? ''),
                  ),
                  title: Text(username),
                  subtitle: Text("Tap to chat"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          convoId: convo.id,
                          receiverId: otherUserId,
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
    );
  }
}
