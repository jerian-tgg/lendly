import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a Didit session directly via Didit REST API and opens the hosted ID + liveness page.
  ///
  /// This eliminates the need for Firebase Cloud Functions / Blaze plan.
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
      if (hostedUrl == null || hostedUrl.isEmpty) {
        callbacks.onFailure?.call(
          'Didit did not return a valid verification URL. Please try again.',
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

  /// Confirms the session decision directly from Didit API.
  Future<void> refreshSessionStatus({
    required String sessionId,
    required DiditVerificationCallbacks callbacks,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${DiditAppConfig.apiBaseUrl}/session/$sessionId/decision/'),
        headers: {
          'x-api-key': DiditAppConfig.apiKey,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? '';
        developer.log(
          'Didit session decision: status=$status',
          name: 'DiditVerificationService',
        );

        // Update Firestore user document if status is known
        final uid = _auth.currentUser?.uid;
        if (uid != null && status.isNotEmpty) {
          await _applyStatusToFirestore(uid, sessionId, status);
        }

        _dispatchStatus(status, sessionId, callbacks);
      } else {
        developer.log(
          'Didit decision fetch failed: ${response.statusCode} ${response.body}',
          name: 'DiditVerificationService',
        );
      }
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
    final response = await http.post(
      Uri.parse('${DiditAppConfig.apiBaseUrl}/session/'),
      headers: {
        'x-api-key': DiditAppConfig.apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'workflow_id': DiditAppConfig.workflowId,
        'vendor_data': userId,
        'callback': 'https://lendly.app/verify/done',
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to create Didit session (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = (data['sessionId'] ?? data['session_id']) as String? ?? '';
    final sessionToken = (data['sessionToken'] ?? data['session_token']) as String?;
    final url = (data['url'] ?? data['verificationUrl'] ?? data['session_url']) as String?;

    final hostedUrl = (url != null && url.isNotEmpty)
        ? url
        : (sessionToken != null && sessionToken.isNotEmpty)
            ? '${DiditAppConfig.hostedSessionBaseUrl}/$sessionToken'
            : null;

    return _DiditSessionLaunch(sessionId: sessionId, hostedUrl: hostedUrl);
  }

  Future<void> _applyStatusToFirestore(
    String userId,
    String sessionId,
    String status,
  ) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final updates = <String, dynamic>{
        'verificationStatus': status,
        'verificationSessionId': sessionId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'Approved') {
        updates['isVerified'] = true;
        updates['verifiedAt'] = FieldValue.serverTimestamp();
        updates['isVerificationPending'] = false;
      } else if (status == 'Declined') {
        updates['isVerified'] = false;
        updates['isVerificationPending'] = false;
      } else if (status == 'In Review') {
        updates['isVerificationPending'] = true;
      }

      await userRef.set(updates, SetOptions(merge: true));
    } catch (e) {
      developer.log(
        'Error syncing Didit status to Firestore: $e',
        name: 'DiditVerificationService',
      );
    }
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

  String _readableError(Object e) {
    final msg = e.toString();
    if (msg.startsWith('Exception: ')) {
      return msg.substring(11);
    }
    return msg;
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
