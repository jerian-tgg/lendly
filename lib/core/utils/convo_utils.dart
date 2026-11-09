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
        'contractSigned': false,
        'contractLenderSigned': false,
        'contractBorrowerSigned': false,
        'contractPdfUrl': null,
        'isPaid': false,
        'isReceived': false,
        'isReturned': false,
        'isReturnConfirmed': false,
        'ownerId': otherUserId,
        'itemOwnerId': otherUserId,
        'borrowerId': currentUserId,
        'lastUpdated': FieldValue.serverTimestamp(),
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
      'contractSigned': false,
      'contractLenderSigned': false,
      'contractBorrowerSigned': false,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'totalDays': totalDays,
      'totalPrice': totalPrice,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    return convoId;
  }
}

/// Creates or retrieves a dedicated in-person appraisal conversation between an
/// accredited appraiser and an item owner.
/// Keeps appraisal discussions and meetup QR verifications completely separate
/// from borrowing/lending rental contracts.
Future<String> createOrGetAppraisalConversation({
  required String appraiserId,
  required String ownerId,
  required String itemId,
  String? appraiserBusinessName,
  String? itemName,
}) async {
  final convoRef = FirebaseFirestore.instance.collection('conversations');
  final convoId = 'appraisal_${getConvoId(appraiserId, ownerId)}_$itemId';
  final docRef = convoRef.doc(convoId);
  final docSnap = await docRef.get();

  if (docSnap.exists) {
    return convoId;
  }

  // Create new appraisal conversation document
  await docRef.set({
    'conversationType': 'appraisal',
    'participants': [appraiserId, ownerId],
    'appraiserId': appraiserId,
    'ownerId': ownerId,
    'itemOwnerId': ownerId,
    'borrowerId': appraiserId,
    'itemId': itemId,
    'itemName': itemName ?? 'Item',
    'appraiserBusinessName': appraiserBusinessName ?? 'Licensed Appraiser',
    'approved': true, // Appraisal doesn't use borrow rental approval flow
    'denied': false,
    'isMeetupConfirmed': false,
    'isAppraisalCompleted': false,
    'lastMessageText': 'Appraisal meetup requested for ${itemName ?? 'item'}',
    'lastUpdated': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  // Post the first system message in the appraisal conversation
  await docRef.collection('messages').add({
    'senderId': appraiserId,
    'type': 'appraisal_request',
    'itemId': itemId,
    'itemName': itemName ?? 'Item',
    'appraiserBusinessName': appraiserBusinessName ?? 'Licensed Appraiser',
    'text': 'Hello! I am an accredited appraiser interested in inspecting and certifying your item. Let\'s coordinate where and when to meet in person to inspect the item.',
    'timestamp': FieldValue.serverTimestamp(),
  });

  return convoId;
}

