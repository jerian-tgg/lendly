import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/core/config/didit_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Callbacks for Didit ID verification outcomes.
class DiditVerificationCallbacks {
  final void Function(String sessionId)? onOpened;
  final void Function(String sessionId)? onSuccess;
  final void Function(String sessionId)? onPending;
  final void Function(String sessionId)? onDeclined;
  final void Function()? onCancelled;
  final void Function(String errorMessage)? onFailure;

  const DiditVerificationCallbacks({
    this.onOpened,
    this.onSuccess,
    this.onPending,
    this.onDeclined,
    this.onCancelled,
    this.onFailure,
  });
}

class DiditVerificationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Creates a Didit session and opens the hosted ID + liveness page.
  ///
  /// The native Didit SDK only runs on iOS/Android. Waiting on it from web or
  /// desktop leaves the UI stuck on "Verifying..." forever. The hosted URL is
  /// the same verification flow Didit documents for redirect integrations.
  Future<void> startVerificationFlow({
    required DiditVerificationCallbacks callbacks,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      callbacks.onFailure?.call('You must be logged in to verify your identity.');
      return;
    }

    try {
      final session = await _createSession(user.uid);
      final hostedUrl = session.hostedUrl;
      if (hostedUrl == null) {
        callbacks.onFailure?.call(
          'Didit did not return a verification URL. Check that the Cloud Function is deployed and DIDIT_API_KEY is set.',
        );
        return;
      }

      final uri = Uri.parse(hostedUrl);
      var launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!launched) {
        callbacks.onFailure?.call('Could not open the Didit verification page.');
        return;
      }

      developer.log(
        'Opened Didit hosted verification: $hostedUrl (session=${session.sessionId})',
        name: 'DiditVerificationService',
      );
      callbacks.onOpened?.call(session.sessionId);
    } catch (e, stack) {
      developer.log(
        'Unexpected error during Didit verification: $e',
        error: e,
        stackTrace: stack,
        name: 'DiditVerificationService',
      );
      callbacks.onFailure?.call(_readableError(e));
    }
  }

  /// Confirms the session decision on the backend after the user returns.
  Future<void> refreshSessionStatus({
    required String sessionId,
    required DiditVerificationCallbacks callbacks,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        DiditAppConfig.getSessionFunctionName,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      final result = await callable.call({'sessionId': sessionId});
      final data = _asStringMap(result.data);
      final status = (data['status'] as String?) ?? '';
      _dispatchStatus(status, sessionId, callbacks);
    } catch (e, stack) {
      developer.log(
        'Failed to refresh Didit session status: $e',
        error: e,
        stackTrace: stack,
        name: 'DiditVerificationService',
      );
    }
  }

  Future<_DiditSessionLaunch> _createSession(String userId) async {
    final callable = _functions.httpsCallable(
      DiditAppConfig.createSessionFunctionName,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final result = await callable.call({'vendorData': userId});
    final data = _asStringMap(result.data);

    final sessionId = (data['sessionId'] ?? data['session_id']) as String? ?? '';
    final sessionToken = (data['sessionToken'] ?? data['session_token']) as String?;
    final url = (data['url'] ?? data['verificationUrl']) as String?;

    final hostedUrl = (url != null && url.isNotEmpty)
        ? url
        : (sessionToken != null && sessionToken.isNotEmpty)
            ? '${DiditAppConfig.hostedSessionBaseUrl}/$sessionToken'
            : null;

    return _DiditSessionLaunch(sessionId: sessionId, hostedUrl: hostedUrl);
  }

  void _dispatchStatus(
    String status,
    String sessionId,
    DiditVerificationCallbacks callbacks,
  ) {
    switch (status) {
      case 'Approved':
        callbacks.onSuccess?.call(sessionId);
        break;
      case 'In Review':
        callbacks.onPending?.call(sessionId);
        break;
      case 'Declined':
        callbacks.onDeclined?.call(sessionId);
        break;
      default:
        break;
    }
  }

  Map<String, dynamic> _asStringMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  String _readableError(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? e.code;
    }
    return e.toString();
  }
}

class _DiditSessionLaunch {
  final String sessionId;
  final String? hostedUrl;

  const _DiditSessionLaunch({
    required this.sessionId,
    required this.hostedUrl,
  });
}
