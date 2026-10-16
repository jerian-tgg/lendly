import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessApplication {
  final String id;
  final String userId;
  final String userEmail;
  final String applicantName;
  final String businessName;
  final String licenseNumber;
  final String permitType;
  final String specialization;
  final String phone;
  final String address;
  final List<String> documentUrls;
  final String notes;
  final String status; // 'pending' | 'approved' | 'rejected'
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final String? adminNotes;

  const BusinessApplication({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.applicantName,
    required this.businessName,
    required this.licenseNumber,
    required this.permitType,
    required this.specialization,
    required this.phone,
    required this.address,
    required this.documentUrls,
    this.notes = '',
    this.status = 'pending',
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.adminNotes,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  Map<String, dynamic> toMap() {
    return {
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
      'status': status,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewedBy': reviewedBy,
      'rejectionReason': rejectionReason,
      'adminNotes': adminNotes,
    };
  }

  factory BusinessApplication.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    DateTime parsedSubmittedAt;
    final subRaw = data['submittedAt'];
    if (subRaw is Timestamp) {
      parsedSubmittedAt = subRaw.toDate();
    } else if (subRaw is DateTime) {
      parsedSubmittedAt = subRaw;
    } else {
      parsedSubmittedAt = DateTime.now();
    }

    DateTime? parsedReviewedAt;
    final revRaw = data['reviewedAt'];
    if (revRaw is Timestamp) {
      parsedReviewedAt = revRaw.toDate();
    } else if (revRaw is DateTime) {
      parsedReviewedAt = revRaw;
    }

    List<String> docList = [];
    if (data['documentUrls'] is List) {
      docList = List<String>.from(data['documentUrls']);
    } else if (data['permitUrls'] is List) {
      docList = List<String>.from(data['permitUrls']);
    }

    return BusinessApplication(
      id: doc.id,
      userId: data['userId'] ?? '',
      userEmail: data['userEmail'] ?? '',
      applicantName: data['applicantName'] ?? '',
      businessName: data['businessName'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      permitType: data['permitType'] ?? 'BIR Permit / Registration Document',
      specialization: data['specialization'] ?? 'General Merchandise',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      documentUrls: docList,
      notes: data['notes'] ?? '',
      status: data['status'] ?? 'pending',
      submittedAt: parsedSubmittedAt,
      reviewedAt: parsedReviewedAt,
      reviewedBy: data['reviewedBy'],
      rejectionReason: data['rejectionReason'],
      adminNotes: data['adminNotes'],
    );
  }
}
