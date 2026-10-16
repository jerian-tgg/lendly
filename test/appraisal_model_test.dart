import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/features/appraisal/domain/models/appraisal_model.dart';

void main() {
  group('AppraisalModel Tests', () {
    test('Calculates Mint / Like New for high function and cosmetic scores', () {
      final grade = AppraisalModel.calculateConditionGrade(10, 10);
      expect(grade, 'Mint / Like New');

      final grade2 = AppraisalModel.calculateConditionGrade(9, 10);
      expect(grade2, 'Mint / Like New');
    });

    test('Calculates Excellent for scores around 8', () {
      final grade = AppraisalModel.calculateConditionGrade(8, 8);
      expect(grade, 'Excellent (Minor Wear)');

      final grade2 = AppraisalModel.calculateConditionGrade(7, 9);
      expect(grade2, 'Excellent (Minor Wear)');
    });

    test('Calculates Good for scores around 6 to 7', () {
      final grade = AppraisalModel.calculateConditionGrade(6, 6);
      expect(grade, 'Good (Fully Functional)');

      final grade2 = AppraisalModel.calculateConditionGrade(5, 7);
      expect(grade2, 'Good (Fully Functional)');
    });

    test('Calculates Fair for scores around 4 to 5', () {
      final grade = AppraisalModel.calculateConditionGrade(4, 5);
      expect(grade, 'Fair (Visible Wear)');
    });

    test('Forces Poor / Needs Repair if function score is critical (<= 3)', () {
      // Even if cosmetic is 10, if it does not work, it is Poor / Needs Repair
      final grade = AppraisalModel.calculateConditionGrade(2, 10);
      expect(grade, 'Poor / Needs Repair');

      final grade2 = AppraisalModel.calculateConditionGrade(3, 9);
      expect(grade2, 'Poor / Needs Repair');
    });

    test('Calculates overall score accurately', () {
      expect(AppraisalModel.calculateOverallScore(8, 10), 9.0);
      expect(AppraisalModel.calculateOverallScore(7, 8), 7.5);
    });

    test('Returns appropriate rubric descriptions', () {
      expect(AppraisalModel.getFunctionRubric(10).contains('Flawless'), isTrue);
      expect(AppraisalModel.getFunctionRubric(1).contains('Inoperable'), isTrue);

      expect(AppraisalModel.getCosmeticRubric(10).contains('Pristine'), isTrue);
      expect(AppraisalModel.getCosmeticRubric(1).contains('Severely Damaged'), isTrue);
    });

    test('toMap serializes properly with private_owner_only visibility', () {
      final model = AppraisalModel(
        functionScore: 9,
        cosmeticScore: 8,
        overallScore: 8.5,
        conditionGrade: 'Excellent (Minor Wear)',
        estimatedValue: 15000.0,
        certificateId: 'CERT-12345',
        appraiserId: 'appraiser-1',
        appraiserBusinessName: 'Gadget Valuation Pros',
        appraiserLicense: 'LIC-777',
      );

      final map = model.toMap();
      expect(map['functionScore'], 9);
      expect(map['cosmeticScore'], 8);
      expect(map['overallScore'], 8.5);
      expect(map['conditionGrade'], 'Excellent (Minor Wear)');
      expect(map['appraisalValue'], 15000.0);
      expect(map['appraisalVisibility'], 'private_owner_only');
      expect(map['appraisalStatus'], 'certified');
      expect(map['certifiedByAppraiserId'], 'appraiser-1');
    });
  });
}
