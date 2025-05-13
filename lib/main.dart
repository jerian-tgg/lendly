import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lendly/features/auth/presentation/auth_wrapper.dart';
import 'package:lendly/features/items/presentation/home_screen.dart';
import 'firebase_options.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Stripe.publishableKey = 'pk_test_51RMuEjP8rCIii99H8RwG1VqDyhoL7RujlwAo7kBLGKNEDArTIPPd8in2MW6nxjy5jE4ACMLhXYZYggiVZ8vQ6Ed300g8BOxzrx';
  await Stripe.instance.applySettings();
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