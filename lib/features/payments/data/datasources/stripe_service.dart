import 'package:cloud_functions/cloud_functions.dart';

class StripeService {
  final _functions = FirebaseFunctions.instance;

  Future<String> createPaymentIntent(double amount, [String currency = 'php']) async {
    final result = await _functions.httpsCallable('createPaymentIntent').call({
      'amount': (amount * 100).round(), // convert PHP to centavos
      'currency': currency,
    });

    return result.data['clientSecret'] as String;
  }

  /// Initiates a Stripe Checkout Cash-In session for the authenticated user.
  /// Rate: ₱1 = 1 ORC. Returns session details and payment client secret.
  Future<Map<String, dynamic>> createCashInSession(double amount) async {
    final result = await _functions.httpsCallable('createStripeCashInSession').call({
      'amount': amount,
    });

    return Map<String, dynamic>.from(result.data as Map);
  }
}
