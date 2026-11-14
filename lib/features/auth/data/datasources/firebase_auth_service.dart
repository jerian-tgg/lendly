import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lendly/core/utils/location_helper.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const String defaultAdminEmail = 'admin@orchid.com';
  static const String legacyAdminEmail = 'admin@lendly.com';
  static const String defaultAdminPassword = 'AdminPassword123!';

  static bool isSystemAdminEmail(String? email) {
    if (email == null) return false;
    final lower = email.trim().toLowerCase();
    return lower == defaultAdminEmail || lower == legacyAdminEmail;
  }

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
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        final bool isSystemAdmin = isSystemAdminEmail(email);

        // Send email verification (unless system admin)
        if (!isSystemAdmin) {
          await user.sendEmailVerification();
        }

        // Resolve coordinates from pinned location, city/province, or default Philippines location
        final GeoLocation resolvedLoc = () {
          if (latitude != null && longitude != null && LocationHelper.isWithinPhilippines(latitude, longitude)) {
            return GeoLocation(
              latitude: latitude,
              longitude: longitude,
              name: (locationName != null && locationName.isNotEmpty)
                  ? locationName
                  : (city.isNotEmpty ? '$city${province.isNotEmpty ? ', $province' : ''}' : LocationHelper.defaultLocation.name),
            );
          }
          final parsedFromCity = LocationHelper.parseCoordinates('$city, $province') ??
              LocationHelper.parseCoordinates(city);
          if (parsedFromCity != null) {
            return GeoLocation(
              latitude: parsedFromCity.latitude,
              longitude: parsedFromCity.longitude,
              name: city.isNotEmpty ? '$city${province.isNotEmpty ? ', $province' : ''}' : parsedFromCity.name,
            );
          }
          return GeoLocation(
            latitude: LocationHelper.defaultLocation.latitude,
            longitude: LocationHelper.defaultLocation.longitude,
            name: city.isNotEmpty ? '$city${province.isNotEmpty ? ', $province' : ''}' : LocationHelper.defaultLocation.name,
          );
        }();

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
          'isAppraiser': isAppraiser,
          'isBusiness': isAppraiser,
          'accountType': isAppraiser ? 'appraiser' : 'standard',
          'businessVerificationStatus': 'none',
          'businessName': businessName ?? '',
          'licenseNumber': licenseNumber ?? '',
          'specialization': specialization ?? '',
          'joinedAt': FieldValue.serverTimestamp(),

          // ── Location ──
          'location': {
            'lat': resolvedLoc.latitude,
            'lng': resolvedLoc.longitude,
            'name': resolvedLoc.name ?? (city.isNotEmpty ? city : 'Bacolod / Visayas Area'),
            'geohash': '',
          },
          'latitude': resolvedLoc.latitude,
          'longitude': resolvedLoc.longitude,
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
          !isSystemAdminEmail(user.email)) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['isBlocked'] == true) {
          await _auth.signOut(); // Sign them back out immediately
          throw Exception(
            'Your account has been blocked. Please contact support.'
          );
        }
      }

      if (user != null && isSystemAdminEmail(email)) {
        await _firestore.collection('users').doc(user.uid).set({
          'isAdmin': true,
          'role': 'admin',
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
          'firstName': 'Orchid',
          'lastName': 'Admin',
          'username': 'admin',
          'email': user.email,
          'photoURL': '',
          'isAdmin': true,
          'role': 'admin',
          'isVerified': true,
          'isAppraiser': false,
          'isBusiness': false,
          'accountType': 'standard',
          'businessVerificationStatus': 'none',
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
          final deviceLoc = await LocationHelper.getDeviceLocation();
          // If not, create user document with detected/default PH coordinates
          await _firestore.collection('users').doc(user.uid).set({
            'firstName': user.displayName?.split(' ').first ?? 'Jerian', // Handle first name
            'lastName': user.displayName?.split(' ').last ?? 'Josh',    // Handle last name
            'email': user.email,
            'photoURL': user.photoURL ?? '',
            'isVerified': user.emailVerified,
            'joinedAt': FieldValue.serverTimestamp(),
            'location': {
              'lat': deviceLoc.latitude,
              'lng': deviceLoc.longitude,
              'name': deviceLoc.name ?? LocationHelper.defaultLocation.name,
              'geohash': '',
            },
            'latitude': deviceLoc.latitude,
            'longitude': deviceLoc.longitude,
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

  // Send Password Reset Email
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Please enter your email address.');
    }
    try {
      await _auth.sendPasswordResetEmail(email: trimmedEmail);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          throw Exception('Please enter a valid email address.');
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'too-many-requests':
          throw Exception('Too many requests. Please try again later.');
        default:
          throw Exception(e.message ?? 'Failed to send password reset email.');
      }
    }
  }

  // Log out
  Future<void> logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
