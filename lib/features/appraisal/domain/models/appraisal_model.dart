import 'package:flutter/material.dart';

class AppraisalModel {
  final int functionScore; // 1 - 10
  final int cosmeticScore; // 1 - 10
  final double overallScore; // Calculated 1.0 - 10.0
  final String conditionGrade;
  final double estimatedValue;
  final double? suggestedDailyRate;
  final String? certificateId;
  final String? appraiserId;
  final String? appraiserBusinessName;
  final String? appraiserLicense;
  final String? notes;
  final DateTime? appraisedAt;
  final bool isSerialVerified;
  final bool isCleanWorking;
  final bool isDepositRecommended;

  const AppraisalModel({
    required this.functionScore,
    required this.cosmeticScore,
    required this.overallScore,
    required this.conditionGrade,
    required this.estimatedValue,
    this.suggestedDailyRate,
    this.certificateId,
    this.appraiserId,
    this.appraiserBusinessName,
    this.appraiserLicense,
    this.notes,
    this.appraisedAt,
    this.isSerialVerified = true,
    this.isCleanWorking = true,
    this.isDepositRecommended = true,
  });

  /// Derive the certified condition grade from Function (1-10) and Cosmetic (1-10) scores.
  static String calculateConditionGrade(int function, int cosmetic) {
    // If functionality is critically broken (<= 3), the item must be graded Poor / Needs Repair
    if (function <= 3) {
      return 'Poor / Needs Repair';
    }

    final double avg = (function + cosmetic) / 2.0;

    if (avg >= 9.0 && function >= 9 && cosmetic >= 9) {
      return 'Mint / Like New';
    } else if (avg >= 7.5 && function >= 7) {
      return 'Excellent (Minor Wear)';
    } else if (avg >= 6.0 && function >= 5) {
      return 'Good (Fully Functional)';
    } else if (avg >= 4.0) {
      return 'Fair (Visible Wear)';
    } else {
      return 'Poor / Needs Repair';
    }
  }

  /// Calculates the overall score (1.0 - 10.0)
  static double calculateOverallScore(int function, int cosmetic) {
    return (function + cosmetic) / 2.0;
  }

  /// Rubric descriptions for Function score (1 - 10)
  static String getFunctionRubric(int score) {
    switch (score) {
      case 10:
        return '10/10 - Flawless Operation (Performs like brand new)';
      case 9:
        return '9/10 - Near Perfect (Smooth, highly responsive, zero lag)';
      case 8:
        return '8/10 - Excellent (Fully functional, all features work properly)';
      case 7:
        return '7/10 - Very Good (Normal response, reliable for daily use)';
      case 6:
        return '6/10 - Good (Operational with slight aging or minor quirks)';
      case 5:
        return '5/10 - Fair (Operational, noticeable delay or minor quirks)';
      case 4:
        return '4/10 - Below Average (Operable, secondary features restricted)';
      case 3:
        return '3/10 - Substandard (Major mechanical/electrical issues)';
      case 2:
        return '2/10 - Defective (Barely operates, needs immediate repair)';
      case 1:
      default:
        return '1/10 - Inoperable / Broken (Parts only, non-functional)';
    }
  }

  /// Rubric descriptions for Cosmetic score (1 - 10)
  static String getCosmeticRubric(int score) {
    switch (score) {
      case 10:
        return '10/10 - Pristine / Unblemished (Zero scratches or handling signs)';
      case 9:
        return '9/10 - Near Mint (Pristine body, negligible micro-scuffs)';
      case 8:
        return '8/10 - Excellent (Minor superficial scuffs, clean appearance)';
      case 7:
        return '7/10 - Very Good (Normal cosmetic signs of light use)';
      case 6:
        return '6/10 - Good (Noticeable scratches/scuffs, no cracks or dents)';
      case 5:
        return '5/10 - Fair (Visible surface wear, paint fade or light chips)';
      case 4:
        return '4/10 - Heavy Wear (Noticeable scratches, chips or slight dings)';
      case 3:
        return '3/10 - Poor (Deep scratches, chipped corners, aesthetic damage)';
      case 2:
        return '2/10 - Bad (Cracked casing, heavy weathering or rust)';
      case 1:
      default:
        return '1/10 - Severely Damaged (Broken exterior casing, structural wear)';
    }
  }

  /// Color associated with a given condition grade
  static Color getConditionColor(String grade) {
    if (grade.startsWith('Mint')) {
      return const Color(0xFF059669); // Emerald
    } else if (grade.startsWith('Excellent')) {
      return const Color(0xFF0284C7); // Sky/Blue
    } else if (grade.startsWith('Good')) {
      return const Color(0xFF7B40B5); // Lendly Purple
    } else if (grade.startsWith('Fair')) {
      return const Color(0xFFD97706); // Amber/Orange
    } else {
      return const Color(0xFFDC2626); // Red
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'functionScore': functionScore,
      'cosmeticScore': cosmeticScore,
      'overallScore': overallScore,
      'conditionGrade': conditionGrade,
      'condition': conditionGrade,
      'appraisedCondition': conditionGrade,
      'appraisalValue': estimatedValue,
      'appraisal': estimatedValue,
      'appraisalVisibility': 'private_owner_only',
      'appraisalStatus': 'certified',
      'appraisalRequested': false,
      'certifiedByAppraiserId': appraiserId,
      'certifiedByBusinessName': appraiserBusinessName,
      'certifiedByLicense': appraiserLicense,
      'appraisalCertificateId': certificateId,
      'appraiserNotes': notes,
      'isSerialVerified': isSerialVerified,
      'isCleanWorking': isCleanWorking,
      'isDepositRecommended': isDepositRecommended,
    };
  }
}
