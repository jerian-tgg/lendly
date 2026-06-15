import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/features/payments/domain/usecases/payment_use_case.dart';

class PayButton extends StatelessWidget {
  final String itemId;

  const PayButton({super.key, required this.itemId});

  Future<double> fetchPrice() async {
    final doc = await FirebaseFirestore.instance
        .collection('items')
        .doc(itemId)
        .get();
    return (doc.data()?['price'] ?? 0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final price = await fetchPrice();
        final useCase = PaymentUseCase();
        try {
          await useCase.makePayment(price);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment Successful')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: $e')),
          );
        }
      },
      child: const Text('Pay Now'),
    );
  }
}
