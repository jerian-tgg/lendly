import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Sign Up with Email and Password
  Future<User?> signUp({
    required String email,
    required String password,
    required DateTime birthdate,
    required String firstName, // Added first name
    required String lastName,  // Added last name
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
          'firstName': firstName,  // Save first name
          'lastName': lastName,    // Save last name
          'email': user.email,
          'photoURL': 'https://...', // Placeholder, update later
          'isVerified': false,
          'joinedAt': FieldValue.serverTimestamp(),
          'location': {
            'lat': 10.123,
            'lng': 122.345,
          },
          'birthdate': Timestamp.fromDate(birthdate), // Birthdate
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
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // user cancelled
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
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
            'photoURL': user.photoURL ?? 'https://...',
            'isVerified': user.emailVerified,
            'joinedAt': FieldValue.serverTimestamp(),
            'location': {
              'lat': 10.123,
              'lng': 122.345,
            },
            'birthdate': Timestamp.fromDate(DateTime(2004, 12, 28)), // Default for Google sign in
          });
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
