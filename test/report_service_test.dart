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
  });
}
