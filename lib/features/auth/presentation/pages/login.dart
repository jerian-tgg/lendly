import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:lendly/features/auth/data/datasources/firebase_auth_service.dart';
import 'package:lendly/features/auth/presentation/pages/signup.dart';
import 'package:lendly/features/items/presentation/pages/home_screen.dart';
import 'package:lendly/features/admin/presentation/pages/admin_login_page.dart';

class LoginPage extends StatefulWidget {
  final String? initialEmail;
  final bool showVerificationMessage;

  const LoginPage({
    super.key,
    this.initialEmail,
    this.showVerificationMessage = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _obscureText = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      emailController.text = widget.initialEmail!;
    }
    if (widget.showVerificationMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your email first. Check your inbox.'),
            duration: Duration(seconds: 5),
          ),
        );
      });
    }
  }

  void _togglePasswordView() => setState(() => _obscureText = !_obscureText);

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    setState(() => isLoading = true);
    try {
      final user = await _authService.login(
        email: email,
        password: password,
      );

      if (user != null) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;

        if (!mounted) return;

        if (refreshedUser != null && refreshedUser.emailVerified) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please verify your email first. Check your inbox.'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: ${e.toString()}")),
      );
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen(isGuest: true)),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                    label: const Text('Skip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                ),
                const Text('Welcome to', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const Text('Lendly', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF90E0F3))),
                const SizedBox(height: 32),

                TextField(
                  controller: emailController,
                  decoration: _inputDecoration('Email', Icons.email),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: passwordController,
                  obscureText: _obscureText,
                  decoration: _inputDecoration('Password', Icons.lock).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                      onPressed: _togglePasswordView,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _login,
                    style: _buttonStyle(),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 24),

                RichText(
                  text: TextSpan(
                    text: "Don't have an account? ",
                    style: const TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: 'Sign Up',
                        style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()..onTap = () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpPage()));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen(isGuest: true)),
                    );
                  },
                  child: const Text(
                    'Explore as Visitor',
                    style: TextStyle(
                      color: Color(0xFF007799),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                // Admin Login Button
                TextButton(
                  onPressed: () {
                    // Navigate to admin login page
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => AdminLoginPage()),
                    );
                  },
                  child: const Text(
                    'Admin Login',
                    style: TextStyle(
                      color: Color(0xFFAA0000),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon),
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF90E0F3),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}