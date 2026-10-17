import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/business/domain/entities/business_application.dart';

class BusinessApplicationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _applicationsCollection =>
      _firestore.collection('business_applications');

  CollectionReference get _usersCollection =>
      _firestore.collection('users');

  /// Submit a new business / appraiser verification application
  Future<String> submitApplication({
    required String userId,
    required String userEmail,
    required String applicantName,
    required String businessName,
    required String licenseNumber,
    required String permitType,
    required String specialization,
    required String phone,
    required String address,
    required List<String> documentUrls,
    String notes = '',
  }) async {
    final applicationData = {
      'userId': userId,
      'userEmail': userEmail,
      'applicantName': applicantName,
      'businessName': businessName,
      'licenseNumber': licenseNumber,
      'permitType': permitType,
      'specialization': specialization,
      'phone': phone,
      'address': address,
      'documentUrls': documentUrls,
      'notes': notes,
      'status': 'pending',
      'submittedAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewedBy': null,
      'rejectionReason': null,
      'adminNotes': null,
    };

    final docRef = await _applicationsCollection.add(applicationData);

    // Update user document
    await _usersCollection.doc(userId).set({
      'businessVerificationStatus': 'pending',
      'businessApplicationId': docRef.id,
      'businessName': businessName,
      'licenseNumber': licenseNumber,
      'specialization': specialization,
      'businessPermitType': permitType,
      'businessPermitUrls': documentUrls,
      'businessRejectionReason': null,
      'businessVerificationSubmittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  /// Real-time stream of latest application for a user
  Stream<BusinessApplication?> streamUserApplication(String userId) {
    return _applicationsCollection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>?)?['submittedAt'];
          final bTime = (b.data() as Map<String, dynamic>?)?['submittedAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });
      return BusinessApplication.fromFirestore(sortedDocs.first);
    });
  }

  /// Real-time stream of all applications for the admin dashboard
  Stream<List<BusinessApplication>> streamAllApplications({String? statusFilter}) {
    Query query = _applicationsCollection;
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
      query = query.where('status', isEqualTo: statusFilter);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => BusinessApplication.fromFirestore(doc))
          .toList();

      // Sort newest first
      list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list;
    });
  }

  /// Admin Manual Verification: Accept / Approve
  Future<void> approveApplication({
    required String applicationId,
    required String userId,
    required String adminId,
    required String businessName,
    required String licenseNumber,
    required String specialization,
    String? adminNotes,
  }) async {
    final batch = _firestore.batch();

    final appRef = _applicationsCollection.doc(applicationId);
    batch.update(appRef, {
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminId,
      'rejectionReason': null,
      'adminNotes': adminNotes ?? 'Application and BIR permits verified.',
    });

    final userRef = _usersCollection.doc(userId);
    batch.set(userRef, {
      'isAppraiser': true,
      'isBusiness': true,
      'accountType': 'appraiser',
      'businessVerificationStatus': 'approved',
      'businessName': businessName,
      'licenseNumber': licenseNumber,
      'specialization': specialization,
      'businessApprovedAt': FieldValue.serverTimestamp(),
      'businessRejectionReason': null,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Admin Manual Verification: Reject
  Future<void> rejectApplication({
    required String applicationId,
    required String userId,
    required String adminId,
    required String reason,
  }) async {
    final batch = _firestore.batch();

    final appRef = _applicationsCollection.doc(applicationId);
    batch.update(appRef, {
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminId,
      'rejectionReason': reason,
    });

    final userRef = _usersCollection.doc(userId);
    batch.set(userRef, {
      'isAppraiser': false,
      'businessVerificationStatus': 'rejected',
      'businessRejectionReason': reason,
      'businessRejectedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
