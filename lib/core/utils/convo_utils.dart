import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/convo_id.dart';

Future<String> createOrGetConversation({
  required String currentUserId,
  required String otherUserId,
  required String itemId,
}) async {
  final convoRef = FirebaseFirestore.instance.collection('conversations');
  final querySnapshot = await convoRef
      .where('participants', arrayContains: currentUserId)
      .get();

  QueryDocumentSnapshot? existingConvo;

  try {
    existingConvo = querySnapshot.docs.firstWhere((doc) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      return participants.contains(currentUserId) &&
          participants.contains(otherUserId) &&
          data['itemId'] == itemId;
    });
  } catch (e) {
    existingConvo = null;
  }

  if (existingConvo != null) {
    return existingConvo.id;
  } else {
    final convoId = getConvoId(currentUserId, otherUserId);
    final newConvoRef = convoRef.doc(convoId);

    await newConvoRef.set({
      'participants': [currentUserId, otherUserId],
      'itemOwnerId': otherUserId,
      'itemId': itemId,
      'approved': false,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    return convoId;
  }
}
