import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lendly/core/services/cloudinary/cloudinary_service.dart';

class FirebaseUserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Update user profile including location and optionally profile picture URL
  Future<void> updateUserProfile({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String phone,
    required String location,
    String? photoURL,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");

    final Map<String, dynamic> updateData = {
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'email': email,
      'phone': phone,
      'location': location,
    };

    if (photoURL != null) {
      updateData['photoURL'] = photoURL;
    }

    await _firestore.collection('users').doc(uid).set(updateData, SetOptions(merge: true));
    await _auth.currentUser?.verifyBeforeUpdateEmail(email);
  }

  // Update verification status in Firestore
  Future<void> updateUserVerificationStatus({
    required bool isVerified,
    String? sessionId,
    String? status,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");

    final Map<String, dynamic> updateData = {
      'isVerified': isVerified,
      'verificationStatus': status ?? (isVerified ? 'Approved' : 'Declined'),
    };

    if (isVerified) {
      updateData['verifiedAt'] = FieldValue.serverTimestamp();
    }

    if (sessionId != null) {
      updateData['verificationSessionId'] = sessionId;
    }

    await _firestore.collection('users').doc(uid).set(updateData, SetOptions(merge: true));
  }


  // Get user's profile as a map
  Future<Map<String, dynamic>> getUserProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    // Check for both 'photoURL' and 'profilePictureUrl' as fallback
    final profilePictureUrl = data['profilePictureUrl'] ?? data['photoURL'];

    return {
      ...data,
      'profilePictureUrl': profilePictureUrl,
    };
  }

  // Real-time stream of user's listed items
  Stream<QuerySnapshot> getUserItems() {
    final uid = _auth.currentUser?.uid;
    return _firestore.collection('items')
        .where('ownerId', isEqualTo: uid)
        .snapshots();
  }

  // Real-time stream of user's borrowing history
  Stream<QuerySnapshot> getBorrowingHistory() {
    final uid = _auth.currentUser?.uid;
    return _firestore.collection('borrowings')
        .where('userId', isEqualTo: uid)
        .orderBy('borrowDate', descending: true)
        .snapshots();
  }

  // Real-time stream of reviews received
  Stream<QuerySnapshot> getUserReviews() {
    final uid = _auth.currentUser?.uid;
    return _firestore.collection('reviews')
        .where('revieweeId', isEqualTo: uid)
        .snapshots();
  }

  // Uploads new profile picture to Cloudinary and returns the image URL
  Future<String?> uploadProfilePicture() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");

    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return null;

    // 🔁 Upload to Cloudinary
    final imageUrl = await CloudinaryService.uploadImage(); // No need to pass 'file' here

    if (imageUrl != null) {
      await _firestore.collection('users').doc(uid).update({
        'photoURL': imageUrl,
      });
    }

    return imageUrl;
  }

  // Real-time stream for user's profile
  Stream<DocumentSnapshot> getUserProfileStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");

    return _firestore.collection('users').doc(uid).snapshots();
  }
}
