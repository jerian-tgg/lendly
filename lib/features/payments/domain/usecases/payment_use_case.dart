import 'package:flutter_stripe/flutter_stripe.dart';
import '../../data/datasources/stripe_service.dart';
import '../../data/config/stripe_keys.dart';

class PaymentUseCase {
  final StripeService _service = StripeService();

  Future<void> makePayment(double amount) async {
    try {
      final clientSecret = await _service.createPaymentIntent(
        amount,
        StripeKeys.currency,
      );

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Lendly',
        ),
      );

      await Stripe.instance.presentPaymentSheet();
    } catch (e) {
      throw Exception('Payment failed: $e');
    }
  }
}
