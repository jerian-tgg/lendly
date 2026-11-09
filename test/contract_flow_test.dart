import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Contract Signing & QR Handoff Progression Tests', () {
    bool resolveContractSigned(Map<String, dynamic> convo) {
      final lenderSigned = convo['contractLenderSigned'] == true;
      final borrowerSigned = convo['contractBorrowerSigned'] == true;
      return convo['contractSigned'] == true || (lenderSigned && borrowerSigned);
    }

    String resolveLenderId(Map<String, dynamic> convo, Map<String, dynamic> item) {
      return convo['itemOwnerId'] ??
          convo['ownerId'] ??
          convo['lenderId'] ??
          item['ownerId'] ??
          '';
    }

    test('Both parties signed resolves contractSigned = true even when DB field is missing or false', () {
      final convoStuckState = {
        'contractLenderSigned': true,
        'contractBorrowerSigned': true,
        'contractSigned': false, // Was previously stuck here
      };

      expect(resolveContractSigned(convoStuckState), isTrue);
    });

    test('Single party sign keeps contractSigned = false', () {
      final lenderOnly = {
        'contractLenderSigned': true,
        'contractBorrowerSigned': false,
        'contractSigned': false,
      };
      final borrowerOnly = {
        'contractLenderSigned': false,
        'contractBorrowerSigned': true,
        'contractSigned': false,
      };

      expect(resolveContractSigned(lenderOnly), isFalse);
      expect(resolveContractSigned(borrowerOnly), isFalse);
    });

    test('Lender ID resolution fallbacks work across itemOwnerId, ownerId, lenderId, and item data', () {
      expect(resolveLenderId({'itemOwnerId': 'u1'}, {}), 'u1');
      expect(resolveLenderId({'ownerId': 'u2'}, {}), 'u2');
      expect(resolveLenderId({'lenderId': 'u3'}, {}), 'u3');
      expect(resolveLenderId({}, {'ownerId': 'u4'}), 'u4');
      expect(resolveLenderId({}, {}), '');
    });

    test('Flow transition logic correctly shows QR action panel when contract is signed', () {
      final isApproved = true;
      final isFullyDone = false;

      final convoSigned = {
        'contractLenderSigned': true,
        'contractBorrowerSigned': true,
      };

      final contractSigned = resolveContractSigned(convoSigned);

      final showContractSigningPanel = isApproved && !isFullyDone && !contractSigned;
      final showQrActionPanel = isApproved && !isFullyDone && contractSigned;

      expect(showContractSigningPanel, isFalse);
      expect(showQrActionPanel, isTrue);
    });
  });
}

