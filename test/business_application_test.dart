import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/business/domain/entities/business_application.dart';

void main() {
  group('BusinessApplication Entity Tests', () {
    test('toMap converts properties accurately', () {
      final now = DateTime(2026, 10, 17, 12, 0, 0);
      final app = BusinessApplication(
        id: 'test_id',
        userId: 'user_123',
        userEmail: 'business@example.com',
        applicantName: 'Juan Dela Cruz',
        businessName: 'Juan Appraisals & Lending',
        licenseNumber: 'TIN-123-456-789',
        permitType: 'BIR Certificate of Registration (Form 2303)',
        specialization: 'Electronics & Technology',
        phone: '+63 917 123 4567',
        address: 'Manila, Philippines',
        documentUrls: [
          'https://res.cloudinary.com/dpnsayn8m/image/upload/bir_2303.jpg'
        ],
        notes: 'Main branch located in Manila',
        status: 'pending',
        submittedAt: now,
      );

      final map = app.toMap();

      expect(map['userId'], 'user_123');
      expect(map['userEmail'], 'business@example.com');
      expect(map['applicantName'], 'Juan Dela Cruz');
      expect(map['businessName'], 'Juan Appraisals & Lending');
      expect(map['licenseNumber'], 'TIN-123-456-789');
      expect(map['permitType'], 'BIR Certificate of Registration (Form 2303)');
      expect(map['specialization'], 'Electronics & Technology');
      expect(map['phone'], '+63 917 123 4567');
      expect(map['address'], 'Manila, Philippines');
      expect(map['documentUrls'], hasLength(1));
      expect(map['notes'], 'Main branch located in Manila');
      expect(map['status'], 'pending');
      expect(map['submittedAt'], isA<Timestamp>());
      expect(app.isPending, isTrue);
      expect(app.isApproved, isFalse);
      expect(app.isRejected, isFalse);
    });

    test('Status getters reflect status string correctly', () {
      final now = DateTime.now();
      final approvedApp = BusinessApplication(
        id: 'app_1',
        userId: 'user_1',
        userEmail: 'user1@test.com',
        applicantName: 'User One',
        businessName: 'Business One',
        licenseNumber: 'APP-111',
        permitType: 'BIR Form 2303',
        specialization: 'Tools',
        phone: '123',
        address: 'City',
        documentUrls: [],
        status: 'approved',
        submittedAt: now,
      );
      expect(approvedApp.isApproved, isTrue);
      expect(approvedApp.isPending, isFalse);

      final rejectedApp = BusinessApplication(
        id: 'app_2',
        userId: 'user_2',
        userEmail: 'user2@test.com',
        applicantName: 'User Two',
        businessName: 'Business Two',
        licenseNumber: 'APP-222',
        permitType: 'BIR Form 2303',
        specialization: 'Tools',
        phone: '123',
        address: 'City',
        documentUrls: [],
        status: 'rejected',
        submittedAt: now,
      );
      expect(rejectedApp.isRejected, isTrue);
      expect(rejectedApp.isApproved, isFalse);
    });
  });
}
