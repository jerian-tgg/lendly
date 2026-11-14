// conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lendly/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lendly/features/chat/domain/entities/conversation.dart';
import 'package:lendly/features/chat/presentation/pages/chat_screen.dart';
import 'package:lendly/core/utils/image_utils.dart';

class ConversationScreen extends StatelessWidget {
  final chatRepo = ChatRepositoryImpl(FirebaseChatDataSource(FirebaseFirestore.instance));

  ConversationScreen({super.key});

  String _getOtherUserId(List<String> participants, String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId, orElse: () => 'Unknown');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0 && now.day == date.day) {
      return DateFormat('h:mm a').format(date);
    } else if (difference.inDays < 7 && now.weekday >= date.weekday) {
      return DateFormat('EEE').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF98259A).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF98259A),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Messages',
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: chatRepo.getUserConversations(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF98259A)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text(
                      'Failed to load conversations.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF98259A).withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 52,
                        color: Color(0xFF98259A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No conversations yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Messages with lenders and borrowers will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final conversations = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final convo = conversations[index];
              final otherUserId = _getOtherUserId(convo.participants, currentUserId);

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
                builder: (context, userSnapshot) {
                  final userData = userSnapshot.hasData && userSnapshot.data!.exists
                      ? userSnapshot.data!.data() as Map<String, dynamic>?
                      : null;
                  final username = userData?['username'] ?? userData?['name'] ?? 'User';
                  final profilePicUrl = userData?['photoURL'] as String?;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
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
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: const Color(0xFF98259A).withValues(alpha: 0.1),
                                  backgroundImage: isValidImageUrl(profilePicUrl)
                                      ? NetworkImage(profilePicUrl!)
                                      : null,
                                  child: !isValidImageUrl(profilePicUrl)
                                      ? Text(
                                          username.isNotEmpty ? username[0].toUpperCase() : '?',
                                          style: const TextStyle(
                                            color: Color(0xFF98259A),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),

                                // Text details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              username,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Color(0xFF1A1A2E),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatDate(convo.lastUpdated),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          if (convo.itemId.isNotEmpty) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: convo.conversationType == 'appraisal'
                                                    ? const Color(0xFF059669).withValues(alpha: 0.12)
                                                    : const Color(0xFF98259A).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    convo.conversationType == 'appraisal'
                                                        ? Icons.verified_outlined
                                                        : Icons.inventory_2_outlined,
                                                    size: 10,
                                                    color: convo.conversationType == 'appraisal'
                                                        ? const Color(0xFF059669)
                                                        : const Color(0xFF98259A),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    convo.conversationType == 'appraisal'
                                                        ? 'Appraisal'
                                                        : 'Rental',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: convo.conversationType == 'appraisal'
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFF98259A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Expanded(
                                            child: Text(
                                              convo.lastMessageText ?? 'No messages yet.',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey[400],
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
