import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/core/services/report_service.dart';

void main() {
  group('ReportService Tests', () {
    test('resolveReporterName prefers Firestore profile name over auth metadata', () {
      expect(
        ReportService.resolveReporterName(
          {'firstName': 'Juan', 'lastName': 'Dela Cruz'},
          authDisplayName: 'Auth Name',
          authEmail: 'juan@example.com',
        ),
        'Juan Dela Cruz',
      );

      expect(
        ReportService.resolveReporterName(
          {'displayName': 'Maria Clara'},
          authDisplayName: 'Auth Name',
          authEmail: 'maria@example.com',
        ),
        'Maria Clara',
      );

      expect(
        ReportService.resolveReporterName(
          {'username': 'mariac'},
          authDisplayName: null,
          authEmail: 'maria@example.com',
        ),
        'mariac',
      );
    });

    test('resolveReporterName falls back cleanly to auth metadata or Anonymous', () {
      expect(
        ReportService.resolveReporterName(
          null,
          authDisplayName: 'Auth User',
          authEmail: 'user@example.com',
        ),
        'Auth User',
      );

      expect(
        ReportService.resolveReporterName(
          {},
          authDisplayName: '',
          authEmail: 'user@example.com',
        ),
        'user@example.com',
      );

      expect(
        ReportService.resolveReporterName(null),
        'Anonymous',
      );
    });

    test('buildReportData produces normalized pending report payload for Admin Dashboard', () {
      final ts = Timestamp.fromDate(DateTime(2026, 11, 16, 21, 30));
      final payload = ReportService.buildReportData(
        targetId: ' item_123 ',
        targetType: 'item',
        targetName: ' Mirrorless Camera ',
        reporterId: 'user_456',
        reporterName: 'Juan Dela Cruz',
        reporterEmail: ' juan@example.com ',
        reason: 'Fraudulent listing',
        explanation: '  The seller listed fake specifications and stock photos.  ',
        mediaUrls: ['https://res.cloudinary.com/dpnsayn8m/image/upload/v1/evidence.jpg'],
        createdAt: ts,
      );

      expect(payload['targetId'], 'item_123');
      expect(payload['targetType'], 'item');
      expect(payload['targetName'], 'Mirrorless Camera');
      expect(payload['reporterId'], 'user_456');
      expect(payload['reporterName'], 'Juan Dela Cruz');
      expect(payload['reporterEmail'], 'juan@example.com');
      expect(payload['reason'], 'Fraudulent listing');
      expect(payload['explanation'], 'The seller listed fake specifications and stock photos.');
      expect(payload['mediaUrls'], hasLength(1));
      expect(payload['status'], 'pending');
      expect(payload['createdAt'], ts);
      expect(payload['reviewedAt'], isNull);
      expect(payload['adminNote'], isNull);
    });

    test('sortByCreatedAtDesc puts pending null timestamps first then newest to oldest', () {
      final older = DateTime(2026, 11, 15, 10, 0);
      final newer = DateTime(2026, 11, 16, 12, 0);
      final items = <Map<String, dynamic>>[
        {'id': 'older', 'createdAt': older},
        {'id': 'newer', 'createdAt': newer},
        {'id': 'pending_server_ts', 'createdAt': null},
      ];

      final sorted = ReportService.sortByCreatedAtDesc(
        items,
        (item) => item['createdAt'] as DateTime?,
      );

      expect(sorted.map((e) => e['id']).toList(), [
        'pending_server_ts',
        'newer',
        'older',
      ]);
    });

    test('buildReportData includes targetOwnerId/reportedUserId for item and user reports', () {
      final itemPayload = ReportService.buildReportData(
        targetId: 'item_abc',
        targetType: 'item',
        targetName: 'Drill',
        reporterId: 'reporter_1',
        reporterName: 'Alex',
        reporterEmail: 'alex@example.com',
        reason: 'Counterfeit item',
        explanation: 'This item appears counterfeit with mismatched labels.',
        targetOwnerId: 'owner_99',
        targetOwnerName: 'Bad Seller',
      );

      expect(itemPayload['targetOwnerId'], 'owner_99');
      expect(itemPayload['reportedUserId'], 'owner_99');
      expect(itemPayload['targetOwnerName'], 'Bad Seller');

      final userPayload = ReportService.buildReportData(
        targetId: 'user_77',
        targetType: 'user',
        targetName: 'John Doe',
        reporterId: 'reporter_1',
        reporterName: 'Alex',
        reporterEmail: 'alex@example.com',
        reason: 'Harassment or abuse',
        explanation: 'Sent abusive messages during handoff.',
      );

      expect(userPayload['targetOwnerId'], 'user_77');
      expect(userPayload['reportedUserId'], 'user_77');
      expect(userPayload['targetOwnerName'], 'John Doe');
    });

    test('buildModerationActionSummary formats listing removal and trust score penalty cleanly', () {
      expect(
        ReportService.buildModerationActionSummary(
          targetType: 'item',
          listingRemoved: true,
          trustScorePenalty: 15,
        ),
        'Listing removed • Trust score -15 pts',
      );

      expect(
        ReportService.buildModerationActionSummary(
          targetType: 'item',
          listingRemoved: false,
          trustScorePenalty: 15,
        ),
        'Trust score -15 pts',
      );

      expect(
        ReportService.buildModerationActionSummary(
          targetType: 'user',
          listingRemoved: false,
          trustScorePenalty: 15,
        ),
        'Trust score -15 pts',
      );

      expect(
        ReportService.buildModerationActionSummary(
          targetType: 'item',
          listingRemoved: true,
          trustScorePenalty: 25,
          severityLabel: 'Critical',
        ),
        'Listing removed • Critical: Trust score -25 pts',
      );

      expect(
        ReportService.buildModerationActionSummary(
          targetType: 'item',
          listingRemoved: false,
          trustScorePenalty: 0,
        ),
        'Marked reviewed',
      );
    });

    test('extractItemSnapshot and parseItemDetails preserve listing details and valid images', () {
      final rawItem = {
        'name': 'Sony A7 III',
        'description': 'Full-frame mirrorless camera with 28-70mm lens.',
        'category': 'Cameras',
        'price': 1500,
        'pricePer': 'day',
        'conditionGrade': 'Mint',
        'location': 'Makati City',
        'ownerId': 'owner_1',
        'ownerName': 'Maria Santos',
        'imageUrls': [
          'https://res.cloudinary.com/demo/image/upload/cam1.jpg',
          'invalid-url',
          'https://res.cloudinary.com/demo/image/upload/cam2.jpg',
        ],
        'imageUrl': 'https://res.cloudinary.com/demo/image/upload/cam1.jpg',
      };

      final snapshot = ReportService.extractItemSnapshot(rawItem);
      expect(snapshot, isNotNull);
      expect(snapshot!['title'], 'Sony A7 III');
      expect(snapshot['category'], 'Cameras');
      expect(snapshot['price'], 1500.0);
      expect(snapshot['condition'], 'Mint');
      expect(snapshot['imageUrls'], [
        'https://res.cloudinary.com/demo/image/upload/cam1.jpg',
        'https://res.cloudinary.com/demo/image/upload/cam2.jpg',
      ]);

      // Live item details
      final liveParsed = ReportService.parseItemDetails(liveItemData: rawItem);
      expect(liveParsed.exists, isTrue);
      expect(liveParsed.title, 'Sony A7 III');
      expect(liveParsed.description, 'Full-frame mirrorless camera with 28-70mm lens.');
      expect(liveParsed.imageUrls, hasLength(2));

      // Snapshot fallback when live listing was removed
      final removedParsed = ReportService.parseItemDetails(
        liveItemData: null,
        snapshotData: snapshot,
        fallbackTitle: 'Fallback',
      );
      expect(removedParsed.exists, isFalse);
      expect(removedParsed.title, 'Sony A7 III');
      expect(removedParsed.price, 1500.0);
      expect(removedParsed.imageUrls, hasLength(2));
    });
  });
}
