import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lendly/core/services/document_upload_service.dart';
import 'package:lendly/core/services/trust_score_service.dart';
import 'package:lendly/core/utils/image_utils.dart';

/// Normalized metadata & image URLs for a reported item listing,
/// resolved either from the live `items/{id}` document or a stored snapshot.
class ReportedItemDetails {
  final bool exists;
  final String title;
  final String? description;
  final String? category;
  final double? price;
  final String pricePer;
  final String? condition;
  final String? location;
  final String? ownerId;
  final String? ownerName;
  final List<String> imageUrls;

  const ReportedItemDetails({
    required this.exists,
    required this.title,
    this.description,
    this.category,
    this.price,
    this.pricePer = 'day',
    this.condition,
    this.location,
    this.ownerId,
    this.ownerName,
    this.imageUrls = const [],
  });

  bool get hasDetails =>
      (description != null && description!.isNotEmpty) ||
      (category != null && category!.isNotEmpty) ||
      price != null ||
      (condition != null && condition!.isNotEmpty) ||
      imageUrls.isNotEmpty;
}

/// Live context resolved for a report target before an admin applies moderation.
class ReportModerationContext {
  final String targetType;
  final String targetId;
  final bool listingExists;
  final String? listingTitle;
  final ReportedItemDetails? itemDetails;
  final String? reportedUserId;
  final String? reportedUserName;
  final String? reportedUserEmail;
  final int? currentTrustScore;
  final int existingViolations;

  const ReportModerationContext({
    required this.targetType,
    required this.targetId,
    required this.listingExists,
    this.listingTitle,
    this.itemDetails,
    this.reportedUserId,
    this.reportedUserName,
    this.reportedUserEmail,
    this.currentTrustScore,
    this.existingViolations = 0,
  });
}

/// Summary returned after an admin confirms a valid report and runs moderation.
class ModerationResult {
  final bool listingRemoved;
  final bool trustScoreLowered;
  final String? reportedUserId;
  final String? reportedUserName;
  final int? previousTrustScore;
  final int? newTrustScore;
  final int penaltyApplied;
  final ReportSeverity severity;
  final String summary;

  const ModerationResult({
    required this.listingRemoved,
    required this.trustScoreLowered,
    this.reportedUserId,
    this.reportedUserName,
    this.previousTrustScore,
    this.newTrustScore,
    required this.penaltyApplied,
    this.severity = ReportSeverity.moderate,
    required this.summary,
  });
}

/// Handles submitting user/item violation reports and streaming/updating/moderating
/// them in the Admin Dashboard.
class ReportService {
  static const List<String> validStatuses = ['pending', 'reviewed', 'dismissed'];

  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;

  ReportService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _injectedFirestore = firestore,
        _injectedAuth = auth;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  /// Resolves a human-readable user/reporter name from Firestore profile fields
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

  /// Extracts a normalized list of valid item image URLs from a Firestore item map.
  static List<String> extractItemImageUrls(Map<String, dynamic>? itemData) {
    if (itemData == null) return const [];
    final urls = <String>[];
    final rawList = itemData['imageUrls'];
    if (rawList is List) {
      for (final entry in rawList) {
        final s = entry?.toString().trim();
        if (isValidImageUrl(s) && !urls.contains(s)) {
          urls.add(s!);
        }
      }
    }
    final single = itemData['imageUrl']?.toString().trim();
    if (isValidImageUrl(single) && !urls.contains(single)) {
      urls.add(single!);
    }
    return urls;
  }

  /// Extracts a compact item snapshot map for storing on a report document
  /// so item details and images remain visible even if the listing is deleted.
  static Map<String, dynamic>? extractItemSnapshot(
    Map<String, dynamic>? itemData,
  ) {
    if (itemData == null || itemData.isEmpty) return null;
    final title = (itemData['name'] ?? itemData['title'])?.toString().trim();
    final description = itemData['description']?.toString().trim();
    final category = itemData['category']?.toString().trim();
    final price = (itemData['price'] as num?)?.toDouble();
    final pricePer = itemData['pricePer']?.toString().trim();
    final condition =
        (itemData['conditionGrade'] ?? itemData['condition'])?.toString().trim();
    final location = (itemData['location'] ?? itemData['city'] ?? itemData['address'])
        ?.toString()
        .trim();
    final ownerId = itemData['ownerId']?.toString().trim();
    final ownerName = itemData['ownerName']?.toString().trim();
    final imageUrls = extractItemImageUrls(itemData);

    return {
      if (title != null && title.isNotEmpty) 'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (category != null && category.isNotEmpty) 'category': category,
      'price': ?price,
      if (pricePer != null && pricePer.isNotEmpty) 'pricePer': pricePer,
      if (condition != null && condition.isNotEmpty) 'condition': condition,
      if (location != null && location.isNotEmpty) 'location': location,
      if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
      if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
    };
  }

  /// Parses [ReportedItemDetails] from live item data and/or a stored report snapshot.
  static ReportedItemDetails parseItemDetails({
    Map<String, dynamic>? liveItemData,
    Map<String, dynamic>? snapshotData,
    String? fallbackTitle,
  }) {
    final bool exists = liveItemData != null;
    final source = liveItemData ?? snapshotData ?? const <String, dynamic>{};

    final rawTitle =
        (source['name'] ?? source['title'])?.toString().trim() ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : ((fallbackTitle != null && fallbackTitle.trim().isNotEmpty)
            ? fallbackTitle.trim()
            : 'Unknown Listing');

    final description = source['description']?.toString().trim();
    final category = source['category']?.toString().trim();
    final price = (source['price'] as num?)?.toDouble();
    final rawPricePer = source['pricePer']?.toString().trim();
    final pricePer =
        (rawPricePer != null && rawPricePer.isNotEmpty) ? rawPricePer : 'day';
    final condition =
        (source['conditionGrade'] ?? source['condition'])?.toString().trim();
    final location =
        (source['location'] ?? source['city'] ?? source['address'])
            ?.toString()
            .trim();
    final ownerId = source['ownerId']?.toString().trim();
    final ownerName = source['ownerName']?.toString().trim();
    final imageUrls = extractItemImageUrls(source);

    return ReportedItemDetails(
      exists: exists,
      title: title,
      description:
          (description != null && description.isNotEmpty) ? description : null,
      category: (category != null && category.isNotEmpty) ? category : null,
      price: price,
      pricePer: pricePer,
      condition:
          (condition != null && condition.isNotEmpty) ? condition : null,
      location: (location != null && location.isNotEmpty) ? location : null,
      ownerId: (ownerId != null && ownerId.isNotEmpty) ? ownerId : null,
      ownerName:
          (ownerName != null && ownerName.isNotEmpty) ? ownerName : null,
      imageUrls: imageUrls,
    );
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
    String? targetOwnerId,
    String? targetOwnerName,
    Map<String, dynamic>? targetItemSnapshot,
  }) {
    final normalizedType = targetType.trim();
    final normalizedTargetId = targetId.trim();
    final normalizedTargetName =
        targetName.trim().isNotEmpty ? targetName.trim() : 'Unknown';

    final resolvedOwnerId = (targetOwnerId != null && targetOwnerId.trim().isNotEmpty)
        ? targetOwnerId.trim()
        : (normalizedType == 'user' ? normalizedTargetId : null);
    final resolvedOwnerName =
        (targetOwnerName != null && targetOwnerName.trim().isNotEmpty)
            ? targetOwnerName.trim()
            : (normalizedType == 'user' ? normalizedTargetName : null);

    return {
      'targetId': normalizedTargetId,
      'targetType': normalizedType,
      'targetName': normalizedTargetName,
      'targetOwnerId': ?resolvedOwnerId,
      'reportedUserId': ?resolvedOwnerId,
      'targetOwnerName': ?resolvedOwnerName,
      'targetItemSnapshot': ?targetItemSnapshot,
      'reporterId': reporterId,
      'reporterName':
          reporterName.trim().isNotEmpty ? reporterName.trim() : 'Anonymous',
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

  /// Formats a human-readable summary of moderation actions taken on a report.
  static String buildModerationActionSummary({
    required String targetType,
    required bool listingRemoved,
    required int trustScorePenalty,
    String? severityLabel,
  }) {
    final parts = <String>[];
    if (targetType == 'item' && listingRemoved) {
      parts.add('Listing removed');
    }
    if (trustScorePenalty > 0) {
      final prefix = (severityLabel != null && severityLabel.trim().isNotEmpty)
          ? '$severityLabel: '
          : '';
      parts.add('${prefix}Trust score -$trustScorePenalty pts');
    }
    if (parts.isEmpty) {
      return 'Marked reviewed';
    }
    return parts.join(' • ');
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
    String? targetOwnerId,
    String? targetOwnerName,
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
      final userDoc =
          await _firestore.collection('users').doc(reporter.uid).get();
      if (userDoc.exists) {
        userData = userDoc.data();
      }
    } catch (_) {
      // Fallback to FirebaseAuth user metadata if profile lookup fails.
    }

    String? resolvedOwnerId = targetOwnerId;
    String? resolvedOwnerName = targetOwnerName;
    Map<String, dynamic>? itemSnapshot;
    if (targetType.trim() == 'item' && targetId.trim().isNotEmpty) {
      try {
        final itemDoc =
            await _firestore.collection('items').doc(targetId.trim()).get();
        if (itemDoc.exists) {
          final itemData = itemDoc.data();
          itemSnapshot = extractItemSnapshot(itemData);
          if (resolvedOwnerId == null || resolvedOwnerId.trim().isEmpty) {
            resolvedOwnerId = itemData?['ownerId']?.toString();
          }
          if (resolvedOwnerName == null || resolvedOwnerName.trim().isEmpty) {
            resolvedOwnerName = itemData?['ownerName']?.toString();
          }
        }
      } catch (_) {
        // Non-fatal: admin review will also attempt to resolve details from items/{targetId}.
      }
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
      targetOwnerId: resolvedOwnerId,
      targetOwnerName: resolvedOwnerName,
      targetItemSnapshot: itemSnapshot,
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

  /// Fetches live listing details (falling back to stored snapshot) for a report card.
  Future<ReportedItemDetails?> fetchItemDetailsForReport(
    Map<String, dynamic> reportData,
  ) async {
    final targetType = (reportData['targetType'] ?? 'item').toString().trim();
    if (targetType != 'item') return null;

    final targetId = (reportData['targetId'] ?? '').toString().trim();
    final snapshotMap = reportData['targetItemSnapshot'] is Map
        ? Map<String, dynamic>.from(reportData['targetItemSnapshot'] as Map)
        : null;

    Map<String, dynamic>? liveItemData;
    if (targetId.isNotEmpty) {
      try {
        final itemDoc =
            await _firestore.collection('items').doc(targetId).get();
        if (itemDoc.exists) {
          liveItemData = itemDoc.data();
        }
      } catch (_) {}
    }

    return parseItemDetails(
      liveItemData: liveItemData,
      snapshotData: snapshotMap,
      fallbackTitle: reportData['targetName']?.toString(),
    );
  }

  /// Fetches live listing and reported-user details for the admin moderation sheet.
  Future<ReportModerationContext> fetchModerationContext(
    Map<String, dynamic> reportData,
  ) async {
    final targetType = (reportData['targetType'] ?? 'item').toString().trim();
    final targetId = (reportData['targetId'] ?? '').toString().trim();

    bool listingExists = false;
    String? listingTitle = reportData['targetName']?.toString();
    ReportedItemDetails? itemDetails;
    String? reportedUserId = (reportData['reportedUserId'] ??
            reportData['targetOwnerId'])
        ?.toString()
        .trim();
    String? reportedUserName = reportData['targetOwnerName']?.toString().trim();
    String? reportedUserEmail;

    if (targetType == 'item' && targetId.isNotEmpty) {
      itemDetails = await fetchItemDetailsForReport(reportData);
      listingExists = itemDetails?.exists ?? false;
      if (itemDetails != null) {
        listingTitle = itemDetails.title;
        if (itemDetails.ownerId != null && itemDetails.ownerId!.isNotEmpty) {
          reportedUserId = itemDetails.ownerId;
        }
        if (itemDetails.ownerName != null &&
            itemDetails.ownerName!.isNotEmpty) {
          reportedUserName = itemDetails.ownerName;
        }
      }
    } else if (targetType == 'user' && targetId.isNotEmpty) {
      reportedUserId = targetId;
      if (reportedUserName == null || reportedUserName.isEmpty) {
        reportedUserName = reportData['targetName']?.toString().trim();
      }
    }

    int? currentTrustScore;
    int existingViolations = 0;

    if (reportedUserId != null && reportedUserId.isNotEmpty) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(reportedUserId).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          currentTrustScore =
              TrustScoreService.resolveEffectiveTrustScore(userData);
          existingViolations =
              (userData?['confirmedReportViolations'] as num?)?.toInt() ?? 0;
          reportedUserEmail = userData?['email']?.toString().trim();
          final resolvedName = resolveReporterName(
            userData,
            authEmail: reportedUserEmail,
          );
          if (resolvedName != 'Anonymous') {
            reportedUserName = resolvedName;
          }
        }
      } catch (_) {}
    }

    return ReportModerationContext(
      targetType: targetType,
      targetId: targetId,
      listingExists: listingExists,
      listingTitle: listingTitle,
      itemDetails: itemDetails,
      reportedUserId:
          (reportedUserId != null && reportedUserId.isNotEmpty) ? reportedUserId : null,
      reportedUserName: reportedUserName,
      reportedUserEmail: reportedUserEmail,
      currentTrustScore: currentTrustScore,
      existingViolations: existingViolations,
    );
  }

  /// Confirms a report is valid and atomically applies admin moderation actions:
  /// - Removes the reported listing (when [targetType == 'item'] and [removeListing] is true)
  /// - Automatically lowers the reported user's trust score based on the report
  ///   reason's severity (or [trustScorePenalty] if explicitly overridden)
  /// - Marks the report as `'reviewed'` with an audit trail.
  Future<ModerationResult> confirmValidReport({
    required String docId,
    required String adminNote,
    bool removeListing = true,
    int? trustScorePenalty,
    String? fallbackReportedUserId,
  }) async {
    final reviewer = _auth.currentUser;

    return _firestore.runTransaction((tx) async {
      // ── Phase 1: All reads first ──────────────────────────────────
      final reportRef = _firestore.collection('reports').doc(docId);
      final reportDoc = await tx.get(reportRef);
      if (!reportDoc.exists) {
        throw Exception('Report not found.');
      }

      final reportData = reportDoc.data() ?? <String, dynamic>{};
      final currentStatus = reportData['status']?.toString() ?? 'pending';
      if (currentStatus != 'pending' || reportData['moderationApplied'] == true) {
        throw Exception('This report has already been processed.');
      }

      final severity = TrustScoreService.severityForReason(
        reportData['reason']?.toString(),
      );
      final rawPenalty = trustScorePenalty ?? severity.penaltyPoints;
      final sanitizedPenalty = rawPenalty < 0 ? 0 : rawPenalty;

      final targetType =
          (reportData['targetType'] ?? 'item').toString().trim();
      final targetId = (reportData['targetId'] ?? '').toString().trim();

      DocumentReference<Map<String, dynamic>>? itemRef;
      DocumentSnapshot<Map<String, dynamic>>? itemDoc;
      if (targetType == 'item' && targetId.isNotEmpty) {
        itemRef = _firestore.collection('items').doc(targetId);
        itemDoc = await tx.get(itemRef);
      }

      final bool itemExists = itemDoc != null && itemDoc.exists;
      final Map<String, dynamic>? itemData = itemExists ? itemDoc.data() : null;

      String? reportedUserId;
      if (targetType == 'user' && targetId.isNotEmpty) {
        reportedUserId = targetId;
      } else {
        final candidates = [
          itemData?['ownerId']?.toString(),
          reportData['reportedUserId']?.toString(),
          reportData['targetOwnerId']?.toString(),
          fallbackReportedUserId,
        ];
        for (final c in candidates) {
          if (c != null && c.trim().isNotEmpty) {
            reportedUserId = c.trim();
            break;
          }
        }
      }

      DocumentReference<Map<String, dynamic>>? userRef;
      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      if (reportedUserId != null && reportedUserId.isNotEmpty) {
        userRef = _firestore.collection('users').doc(reportedUserId);
        userDoc = await tx.get(userRef);
      }

      final bool shouldRemoveListing =
          targetType == 'item' && removeListing && itemExists && itemRef != null;
      final bool shouldPenalizeUser =
          userRef != null && sanitizedPenalty > 0;

      int? previousScore;
      int? newScore;
      int newTotalPenalty = 0;
      int newViolations = 0;
      String? reportedUserName = itemData?['ownerName']?.toString().trim() ??
          reportData['targetOwnerName']?.toString().trim();
      Map<String, dynamic> existingStats = <String, dynamic>{};

      if (shouldPenalizeUser) {
        final userData = userDoc != null && userDoc.exists ? userDoc.data() : null;
        previousScore = TrustScoreService.resolveEffectiveTrustScore(userData);
        newScore = TrustScoreService.applyPenalty(
          previousScore,
          penaltyPoints: sanitizedPenalty,
        );
        final currentPenalty =
            (userData?['trustScorePenalty'] as num?)?.toInt() ?? 0;
        newTotalPenalty = currentPenalty + sanitizedPenalty;
        final currentViolations =
            (userData?['confirmedReportViolations'] as num?)?.toInt() ?? 0;
        newViolations = currentViolations + 1;

        if (userData != null) {
          final resolved = resolveReporterName(
            userData,
            authEmail: userData['email']?.toString(),
          );
          if (resolved != 'Anonymous') {
            reportedUserName = resolved;
          }
          if (userData['trustScoreStats'] is Map) {
            existingStats = Map<String, dynamic>.from(
              userData['trustScoreStats'] as Map,
            );
          }
        }
      }

      final summary = buildModerationActionSummary(
        targetType: targetType,
        listingRemoved: shouldRemoveListing,
        trustScorePenalty: shouldPenalizeUser ? sanitizedPenalty : 0,
        severityLabel: severity.label,
      );

      // ── Phase 2: All writes ───────────────────────────────────────
      if (shouldRemoveListing) {
        tx.delete(itemRef);
      }

      if (shouldPenalizeUser) {
        final updatedStats = <String, dynamic>{
          ...existingStats,
          'reportPenalty': newTotalPenalty,
          'confirmedReportViolations': newViolations,
          'lastCalculatedAt': FieldValue.serverTimestamp(),
        };

        tx.set(
          userRef,
          {
            'trustScore': newScore,
            'trustScorePenalty': newTotalPenalty,
            'confirmedReportViolations': newViolations,
            'lastPenaltyReason':
                reportData['reason']?.toString() ?? 'Confirmed violation report',
            'lastPenalizedAt': FieldValue.serverTimestamp(),
            'trustScoreStats': updatedStats,
          },
          SetOptions(merge: true),
        );
      }

      tx.update(reportRef, {
        'status': 'reviewed',
        'adminNote': adminNote.trim(),
        'reviewedAt': FieldValue.serverTimestamp(),
        if (reviewer != null) 'reviewedBy': reviewer.uid,
        'moderationApplied': true,
        'listingRemoved': shouldRemoveListing,
        'reportSeverity': severity.label,
        if (reportedUserId != null && reportedUserId.isNotEmpty)
          'reportedUserId': reportedUserId,
        if (reportedUserName != null && reportedUserName.isNotEmpty)
          'reportedUserName': reportedUserName,
        if (shouldPenalizeUser) ...{
          'trustScorePenaltyApplied': sanitizedPenalty,
          'previousTrustScore': previousScore,
          'newTrustScore': newScore,
        },
        'moderationAction': summary,
      });

      return ModerationResult(
        listingRemoved: shouldRemoveListing,
        trustScoreLowered: shouldPenalizeUser,
        reportedUserId: reportedUserId,
        reportedUserName: reportedUserName,
        previousTrustScore: previousScore,
        newTrustScore: newScore,
        penaltyApplied: shouldPenalizeUser ? sanitizedPenalty : 0,
        severity: severity,
        summary: summary,
      );
    });
  }

  /// Dismisses an invalid report without removing any listing or penalizing trust score.
  Future<void> dismissReport({
    required String docId,
    required String adminNote,
  }) {
    return updateReportStatus(
      docId: docId,
      status: 'dismissed',
      adminNote: adminNote,
    );
  }

  /// Updates a report's review status and admin note from the Admin Dashboard.
  Future<void> updateReportStatus({
    required String docId,
    required String status,
    required String adminNote,
  }) async {
    final reviewer = _auth.currentUser;
    final updates = <String, dynamic>{
      'status': status,
      'adminNote': adminNote.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      if (reviewer != null) 'reviewedBy': reviewer.uid,
    };

    if (status == 'dismissed') {
      updates['moderationApplied'] = false;
      updates['listingRemoved'] = false;
      updates['moderationAction'] = 'Dismissed (invalid report)';
    }

    await _firestore.collection('reports').doc(docId).update(updates);
  }
}
