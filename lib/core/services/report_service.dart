import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lendly/core/services/document_upload_service.dart';

/// Handles submitting user/item violation reports and streaming/updating them
/// in the Admin Dashboard.
class ReportService {
  static const List<String> validStatuses = ['pending', 'reviewed', 'dismissed'];

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Resolves a human-readable reporter name from Firestore profile fields
  /// with safe fallbacks to Firebase Auth metadata.
  static String resolveReporterName(
    Map<String, dynamic>? userData, {
    String? authDisplayName,
    String? authEmail,
  }) {
    if (userData != null) {
      final first = userData['firstName']?.toString().trim() ?? '';
      final last = userData['lastName']?.toString().trim() ?? '';
      final fullName = '$first $last'.trim();
      if (fullName.isNotEmpty) return fullName;

      final display = userData['displayName']?.toString().trim() ?? '';
      if (display.isNotEmpty) return display;

      final username = userData['username']?.toString().trim() ?? '';
      if (username.isNotEmpty) return username;
    }

    if (authDisplayName != null && authDisplayName.trim().isNotEmpty) {
      return authDisplayName.trim();
    }
    if (authEmail != null && authEmail.trim().isNotEmpty) {
      return authEmail.trim();
    }
    return 'Anonymous';
  }

  /// Builds the normalized Firestore payload for a newly submitted report.
  static Map<String, dynamic> buildReportData({
    required String targetId,
    required String targetType,
    required String targetName,
    required String reporterId,
    required String reporterName,
    required String reporterEmail,
    required String reason,
    required String explanation,
    List<String> mediaUrls = const [],
    Object? createdAt,
  }) {
    return {
      'targetId': targetId.trim(),
      'targetType': targetType.trim(),
      'targetName': targetName.trim().isNotEmpty ? targetName.trim() : 'Unknown',
      'reporterId': reporterId,
      'reporterName': reporterName.trim().isNotEmpty ? reporterName.trim() : 'Anonymous',
      'reporterEmail': reporterEmail.trim(),
      'reason': reason.trim(),
      'explanation': explanation.trim(),
      'mediaUrls': mediaUrls,
      'status': 'pending',
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'adminNote': null,
    };
  }

  /// Sorts report items newest-first. Items with a pending (null) server
  /// timestamp are placed at the top so newly submitted reports appear immediately.
  static List<T> sortByCreatedAtDesc<T>(
    Iterable<T> items,
    DateTime? Function(T item) getCreatedAt,
  ) {
    final sorted = items.toList();
    sorted.sort((a, b) {
      final aDate = getCreatedAt(a);
      final bDate = getCreatedAt(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return -1;
      if (bDate == null) return 1;
      return bDate.compareTo(aDate);
    });
    return sorted;
  }

  /// Submits a report to Firestore `reports` (uploading optional media to Cloudinary)
  /// so it immediately enters the Admin Reports queue with `status: 'pending'`.
  Future<String> submitReport({
    required String targetId,
    required String targetType,
    required String targetName,
    required String reason,
    required String explanation,
    List<XFile> mediaFiles = const [],
  }) async {
    final reporter = _auth.currentUser;
    if (reporter == null) {
      throw Exception('Please log in to submit a report.');
    }

    final mediaUrls = <String>[];
    for (final file in mediaFiles) {
      final url = await DocumentUploadService.uploadMediaXFile(file);
      mediaUrls.add(url);
    }

    Map<String, dynamic>? userData;
    try {
      final userDoc = await _firestore.collection('users').doc(reporter.uid).get();
      if (userDoc.exists) {
        userData = userDoc.data();
      }
    } catch (_) {
      // Fallback to FirebaseAuth user metadata if profile lookup fails.
    }

    final reporterName = resolveReporterName(
      userData,
      authDisplayName: reporter.displayName,
      authEmail: reporter.email,
    );

    final payload = buildReportData(
      targetId: targetId,
      targetType: targetType,
      targetName: targetName,
      reporterId: reporter.uid,
      reporterName: reporterName,
      reporterEmail: reporter.email ?? '',
      reason: reason,
      explanation: explanation,
      mediaUrls: mediaUrls,
    );

    final docRef = await _firestore.collection('reports').add(payload);
    return docRef.id;
  }

  /// Streams reports filtered by [status] and sorted newest-first client-side,
  /// avoiding composite index failures in Firestore.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamReportsByStatus(
    String status,
  ) {
    return _firestore
        .collection('reports')
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snap) {
      return sortByCreatedAtDesc(snap.docs, (doc) {
        final ts = doc.data()['createdAt'];
        return ts is Timestamp ? ts.toDate() : null;
      });
    });
  }

  /// Streams the count of pending reports for admin dashboard badges.
  Stream<int> streamPendingReportCount() {
    return _firestore
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Updates a report's review status and admin note from the Admin Dashboard.
  Future<void> updateReportStatus({
    required String docId,
    required String status,
    required String adminNote,
  }) async {
    final reviewer = _auth.currentUser;
    await _firestore.collection('reports').doc(docId).update({
      'status': status,
      'adminNote': adminNote.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      if (reviewer != null) 'reviewedBy': reviewer.uid,
    });
  }
}
