import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:lendly/core/config/firebase_options.dart';
import 'package:lendly/features/auth/presentation/pages/auth_wrapper.dart';
import 'package:lendly/features/payments/data/config/stripe_keys.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Stripe SDK safely
  try {
    Stripe.publishableKey = StripeKeys.publishableKey;
    await Stripe.instance.applySettings();
  } catch (e) {
    debugPrint('Stripe initialization failed: $e');
  }

  // Launch the app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orchid',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF98259A),
          primary: const Color(0xFF98259A),
        ),
        primaryColor: const Color(0xFF98259A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF98259A),
          foregroundColor: Colors.white,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}
