import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

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
        // Send email verification
        await user.sendEmailVerification();

        // Add user details to Firestore
        await _firestore.collection('users').doc(user.uid).set({
          // ── Name ──
          'firstName': firstName,
          'middleName': middleName,
          'lastName': lastName,
          'suffix': suffix,
          'displayName': '$firstName $lastName'.trim(),

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
          'isVerified': false,
          'isAppraiser': isAppraiser,
          'isBusiness': isAppraiser,
          'accountType': isAppraiser ? 'appraiser' : 'standard',
          'businessName': businessName ?? '',
          'licenseNumber': licenseNumber ?? '',
          'specialization': specialization ?? '',
          'joinedAt': FieldValue.serverTimestamp(),

          // ── Location (default lat/lng/geohash — updated when user grants GPS permission) ──
          'location': {
            'lat': 0.0,
            'lng': 0.0,
            'geohash': '', // populated when geo-radius feature is activated
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
          user.email != 'admin-portal@lendly.internal') {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['isBlocked'] == true) {
          await _auth.signOut(); // Sign them back out immediately
          throw Exception(
            'Your account has been blocked. Please contact support.'
          );
        }
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
