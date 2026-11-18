import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/auth/data/datasources/firebase_auth_service.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';
import 'package:lendly/features/items/presentation/pages/home_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _checkedStartupSession = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;

          if (!_checkedStartupSession) {
            _checkedStartupSession = true;
            if (user != null &&
                FirebaseAuthService.isAdminPortalEmail(user.email)) {
              // Clear any persisted internal admin portal session from a prior run
              // so the login page opens blank and visitor mode isn't authenticated as admin.
              FirebaseAuth.instance.signOut();
              return const LoginPage();
            }
          }

          if (user != null) {
            if (FirebaseAuthService.isAdminPortalEmail(user.email)) {
              return const LoginPage();
            }
            final isAdmin = FirebaseAuthService.isSystemAdminEmail(user.email);
            if (!user.emailVerified && !isAdmin) {
              return const LoginPage(
                showVerificationMessage: true,
              );
            }
            return const HomeScreen();
          }
          return const LoginPage();
        }
        if (snapshot.hasError) {
          return const LoginPage();
        }
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}