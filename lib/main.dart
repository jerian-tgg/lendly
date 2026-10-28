import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  // Connect to local Cloud Functions emulator in debug mode
  if (kDebugMode) {
    try {
      const bool isEmulator = bool.fromEnvironment('USE_LOCAL_FUNCTIONS', defaultValue: true);
      if (isEmulator) {
        final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? '10.0.2.2'
            : 'localhost';
        FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
        debugPrint('FirebaseFunctions configured to use local emulator at $host:5001');
      }
    } catch (e) {
      debugPrint('Cloud Functions emulator setup error: $e');
    }
  }

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
      title: 'Lendly',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}
