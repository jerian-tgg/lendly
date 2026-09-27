import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/core/config/didit_config.dart';
import 'package:lendly/core/services/didit/didit_verification_service.dart';

void main() {
  group('Didit Verification Integration Tests', () {
    test('DiditAppConfig exposes correct workflow ID and function name', () {
      expect(DiditAppConfig.workflowId, equals('99c79fd1-9b53-4c2d-a1b7-341b4a893c3b'));
      expect(DiditAppConfig.createSessionFunctionName, equals('createDiditVerificationSession'));
      expect(DiditAppConfig.getSessionFunctionName, equals('getDiditVerificationSession'));
    });

    test('DiditVerificationCallbacks instantiates properly', () {
      bool calledSuccess = false;
      final callbacks = DiditVerificationCallbacks(
        onSuccess: (sessionId) {
          calledSuccess = true;
          expect(sessionId, 'test_session_123');
        },
      );

      callbacks.onSuccess?.call('test_session_123');
      expect(calledSuccess, isTrue);
    });
  });
}
