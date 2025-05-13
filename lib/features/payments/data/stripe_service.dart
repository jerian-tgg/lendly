import 'package:cloud_functions/cloud_functions.dart';

class StripeService {
  final _functions = FirebaseFunctions.instance;

  Future<String> createPaymentIntent(double amount, String currency) async {
    final result = await _functions.httpsCallable('createPaymentIntent').call({
      'amount': (amount * 100).toInt(), // convert dollars to cents
      'currency': currency,
    });

    return result.data['clientSecret'];
  }
}
