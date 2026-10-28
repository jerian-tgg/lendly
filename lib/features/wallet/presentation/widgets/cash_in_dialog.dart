import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repositories/wallet_repository.dart';

class CashInDialog extends StatefulWidget {
  const CashInDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CashInDialog(),
    );
  }

  @override
  State<CashInDialog> createState() => _CashInDialogState();
}

class _CashInDialogState extends State<CashInDialog> {
  final WalletRepository _repository = WalletRepository();
  final TextEditingController _amountController = TextEditingController(text: '250');
  double _selectedAmount = 250.0;
  bool _loading = false;
  String? _errorMessage;

  final List<double> _presetAmounts = const [100, 250, 500, 1000, 2500];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onPresetSelected(double amount) {
    setState(() {
      _selectedAmount = amount;
      _amountController.text = amount.toStringAsFixed(0);
      _errorMessage = null;
    });
  }

  Future<void> _processCashIn() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount < 20.0) {
      setState(() {
        _errorMessage = 'Minimum cash-in amount is ₱20 PHP (Stripe minimum).';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final sessionData = await _repository.createCashInSession(amount);
      final sessionUrl = sessionData['sessionUrl'] as String?;
      final clientSecret = sessionData['clientSecret'] as String?;

      // On Mobile / Supported platforms, try native PaymentSheet first if clientSecret is available
      bool paymentSuccess = false;

      if (!kIsWeb && clientSecret != null && clientSecret.isNotEmpty) {
        try {
          await Stripe.instance.initPaymentSheet(
            paymentSheetParameters: SetupPaymentSheetParameters(
              paymentIntentClientSecret: clientSecret,
              merchantDisplayName: 'Lendly ORC Wallet',
              style: ThemeMode.light,
            ),
          );
          await Stripe.instance.presentPaymentSheet();
          paymentSuccess = true;
        } catch (sheetError) {
          // If user cancelled PaymentSheet or platform unsupported, fallback to Stripe Checkout URL
          if (sheetError.toString().contains('canceled') ||
              sheetError.toString().contains('Canceled')) {
            if (mounted) {
              setState(() => _loading = false);
            }
            return;
          }
          // Fallback to web checkout URL
          if (sessionUrl != null) {
            final uri = Uri.parse(sessionUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              paymentSuccess = true;
            }
          }
        }
      } else if (sessionUrl != null) {
        // Web or Checkout URL fallback
        final uri = Uri.parse(sessionUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          paymentSuccess = true;
        } else {
          throw Exception('Unable to open Stripe Checkout page.');
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);

      if (paymentSuccess) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2ECC71),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cash-in initiated for ₱${amount.toStringAsFixed(0)}! ORC credits will be added upon webhook confirmation.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Color(0xFF7B40B5),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash In to ORC Wallet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Powered by Stripe (Test Mode)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Conversion rate banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFE8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF7B40B5).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.currency_exchange, color: Color(0xFF7B40B5), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Conversion Rate: ₱1 PHP = 1 ORC Credit\nNo hidden charges. Instant wallet credit.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B32A8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Select Amount (PHP)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),

            // Preset Amount Pills
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetAmounts.map((amt) {
                final isSelected = _selectedAmount == amt &&
                    _amountController.text == amt.toStringAsFixed(0);
                return ChoiceChip(
                  label: Text('₱${amt.toStringAsFixed(0)}'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _onPresetSelected(amt);
                  },
                  selectedColor: const Color(0xFF7B40B5),
                  backgroundColor: const Color(0xFFF0F4F8),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Custom Amount Input Field
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (val) {
                final parsed = double.tryParse(val) ?? 0;
                setState(() {
                  _selectedAmount = parsed;
                  _errorMessage = null;
                });
              },
              decoration: InputDecoration(
                prefixText: '₱ ',
                prefixStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF7B40B5),
                ),
                labelText: 'Custom Amount (Min. ₱20)',
                hintText: 'Enter amount in PHP',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 2),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],

            const SizedBox(height: 20),

            // Pay Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _processCashIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B40B5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.payment, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Pay with Stripe (₱${_selectedAmount.toStringAsFixed(0)})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
