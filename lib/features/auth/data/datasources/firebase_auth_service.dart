import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const String defaultAdminEmail = 'admin@lendly.com';
  static const String defaultAdminPassword = 'AdminPassword123!';

  // Sign Up with Email and Password
  Future<User?> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required DateTime birthdate,
    String middleName = '',
    String suffix = '',
    String sex = '',
    String civilStatus = '',
    String phone = '',
    String altPhone = '',
    String street = '',
    String barangay = '',
    String city = '',
    String province = '',
    String zip = '',
    String occupation = '',
    String employer = '',
    String emergencyName = '',
    String emergencyPhone = '',
    String emergencyRelation = '',
    bool isAppraiser = false,
    String? businessName,
    String? licenseNumber,
    String? specialization,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        final bool isSystemAdmin = email.trim().toLowerCase() == defaultAdminEmail;

        // Send email verification (unless system admin)
        if (!isSystemAdmin) {
          await user.sendEmailVerification();
        }

        // Add user details to Firestore
        await _firestore.collection('users').doc(user.uid).set({
          // ── Name ──
          'firstName': firstName,
          'middleName': middleName,
          'lastName': lastName,
          'suffix': suffix,
          'displayName': '$firstName $lastName'.trim(),
          'username': isSystemAdmin ? 'admin' : '$firstName$lastName'.toLowerCase(),

          // ── Personal ──
          'birthdate': Timestamp.fromDate(birthdate),
          'sex': sex,
          'civilStatus': civilStatus,

          // ── Contact ──
          'email': user.email,
          'phone': phone,
          'altPhone': altPhone,

          // ── Address ──
          'address': {
            'street': street,
            'barangay': barangay,
            'city': city,
            'province': province,
            'zip': zip,
            'full': '$street, $barangay, $city, $province $zip'.trim(),
          },

          // ── Occupation ──
          'occupation': occupation,
          'employer': employer,

          // ── Emergency Contact ──
          'emergencyContact': {
            'name': emergencyName,
            'phone': emergencyPhone,
            'relation': emergencyRelation,
          },

          // ── Account ──
          'photoURL': '',
          'isVerified': isSystemAdmin,
          'isAdmin': isSystemAdmin,
          'role': isSystemAdmin ? 'admin' : 'user',
          'isAppraiser': isSystemAdmin ? true : isAppraiser,
          'isBusiness': isSystemAdmin ? true : isAppraiser,
          'accountType': isSystemAdmin ? 'appraiser' : (isAppraiser ? 'appraiser' : 'standard'),
          'businessVerificationStatus': isSystemAdmin ? 'approved' : 'none',
          'businessName': isSystemAdmin ? 'Lendly Official Appraisal & Verification' : (businessName ?? ''),
          'licenseNumber': isSystemAdmin ? 'BIR-PRC-APPRAISER-001' : (licenseNumber ?? ''),
          'specialization': isSystemAdmin ? 'General Equipment, Electronics, Cameras & Tools' : (specialization ?? ''),
          'joinedAt': FieldValue.serverTimestamp(),

          // ── Location ──
          'location': {
            'lat': 14.5547,
            'lng': 121.0244,
            'name': city.isNotEmpty ? city : 'Makati, Metro Manila',
            'geohash': '',
          },
        });
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // Log In with Email and Password
  Future<User?> login({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = result.user;

      // Check if the user has been blocked by an admin (skip for admins)
      if (user != null &&
          user.email != 'palenciajerjer28@gmail.com' &&
          user.email != 'admin-portal@lendly.internal' &&
          user.email != defaultAdminEmail) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['isBlocked'] == true) {
          await _auth.signOut(); // Sign them back out immediately
          throw Exception(
            'Your account has been blocked. Please contact support.'
          );
        }
      }

      if (user != null && email.trim().toLowerCase() == defaultAdminEmail) {
        await _firestore.collection('users').doc(user.uid).set({
          'isAdmin': true,
          'role': 'admin',
          'isAppraiser': true,
          'isBusiness': true,
          'businessVerificationStatus': 'approved',
          'businessName': 'Lendly Official Appraisal & Verification',
          'licenseNumber': 'BIR-PRC-APPRAISER-001',
          'specialization': 'General Equipment, Electronics, Cameras & Tools',
          'accountType': 'appraiser',
        }, SetOptions(merge: true));
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // Sign in as Admin or automatically initialize the Admin account if it does not exist
  Future<User?> signInOrCreateAdmin({
    String email = defaultAdminEmail,
    String password = defaultAdminPassword,
  }) async {
    try {
      // 1. Try signing in first
      try {
        final result = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (result.user != null) {
          await _firestore.collection('users').doc(result.user!.uid).set({
            'isAdmin': true,
            'role': 'admin',
            'isAppraiser': true,
            'isBusiness': true,
            'businessVerificationStatus': 'approved',
            'businessName': 'Lendly Official Appraisal & Verification',
            'licenseNumber': 'BIR-PRC-APPRAISER-001',
            'specialization': 'General Equipment, Electronics, Cameras & Tools',
            'accountType': 'appraiser',
          }, SetOptions(merge: true));
          return result.user;
        }
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' && e.code != 'invalid-credential' && e.code != 'wrong-password') {
          rethrow;
        }
      }

      // 2. If admin doesn't exist yet, create it
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'firstName': 'Lendly',
          'lastName': 'Admin',
          'username': 'admin',
          'email': user.email,
          'photoURL': '',
          'isAdmin': true,
          'role': 'admin',
          'isVerified': true,
          'isAppraiser': true,
          'isBusiness': true,
          'accountType': 'appraiser',
          'businessVerificationStatus': 'approved',
          'businessName': 'Lendly Official Appraisal & Verification',
          'licenseNumber': 'BIR-PRC-APPRAISER-001',
          'specialization': 'General Equipment, Electronics, Cameras & Tools',
          'joinedAt': FieldValue.serverTimestamp(),
          'location': {
            'lat': 14.5547,
            'lng': 121.0244,
            'name': 'Makati, Metro Manila',
          },
          'birthdate': Timestamp.fromDate(DateTime(1995, 1, 1)),
        }, SetOptions(merge: true));
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      await _googleSignIn.initialize();
      final googleUser = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user != null) {
        // Check if user exists in Firestore
        DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          // If not, create user document
          await _firestore.collection('users').doc(user.uid).set({
            'firstName': user.displayName?.split(' ').first ?? 'Jerian', // Handle first name
            'lastName': user.displayName?.split(' ').last ?? 'Josh',    // Handle last name
            'email': user.email,
            'photoURL': user.photoURL ?? '',
            'isVerified': user.emailVerified,
            'joinedAt': FieldValue.serverTimestamp(),
            'location': {
              'lat': 0.0,
              'lng': 0.0,
              'geohash': '',
            },
            'birthdate': Timestamp.fromDate(DateTime(2004, 12, 28)), // Default for Google sign in
          });
        } else {
          // Check if the existing user has been blocked by an admin (skip for admins)
          if (user.email != 'palenciajerjer28@gmail.com' &&
              user.email != 'admin-portal@lendly.internal' &&
              doc.data() != null &&
              (doc.data() as Map<String, dynamic>)['isBlocked'] == true) {
            await _auth.signOut(); // Sign them back out immediately
            throw Exception(
              'Your account has been blocked. Please contact support.'
            );
          }
        }
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // Log out
  Future<void> logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
