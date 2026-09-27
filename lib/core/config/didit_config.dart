/// Didit Identity Verification configuration.
class DiditAppConfig {
  /// Workflow ID for the "Free KYC" workflow configured in Didit Console.
  /// This is per-session configuration and not a secret.
  static const String workflowId = '99c79fd1-9b53-4c2d-a1b7-341b4a893c3b';

  /// Cloud function name to create a Didit verification session.
  static const String createSessionFunctionName = 'createDiditVerificationSession';

  /// Cloud function name to retrieve a Didit session decision.
  static const String getSessionFunctionName = 'getDiditVerificationSession';

  /// Hosted verification base URL. Session token is appended as the last path segment.
  static const String hostedSessionBaseUrl = 'https://verify.didit.me/session';
}
