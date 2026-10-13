import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/convo_id.dart';

Future<String> createOrGetConversation({
  required String currentUserId,
  required String otherUserId,
  required String itemId,
  DateTime? startDate,
  DateTime? endDate,
  int? totalDays,
  double? totalPrice,
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
    // Update borrow details if provided (borrower re-requested with new dates)
    if (startDate != null && endDate != null) {
      await existingConvo.reference.update({
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'totalDays': totalDays,
        'totalPrice': totalPrice,
        'approved': false,
        'denied': false,
      });
    }
    return existingConvo.id;
  } else {
    final convoId = getConvoId(currentUserId, otherUserId);
    final newConvoRef = convoRef.doc(convoId);

    await newConvoRef.set({
      'participants': [currentUserId, otherUserId],
      'itemOwnerId': otherUserId,
      'ownerId': otherUserId,
      'borrowerId': currentUserId,
      'itemId': itemId,
      'approved': false,
      'denied': false,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'totalDays': totalDays,
      'totalPrice': totalPrice,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    return convoId;
  }
}
