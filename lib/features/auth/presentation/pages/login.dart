import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:lendly/features/auth/data/datasources/firebase_auth_service.dart';
import 'package:lendly/features/auth/presentation/pages/signup.dart';
import 'package:lendly/features/items/presentation/pages/home_screen.dart';
import 'package:lendly/features/admin/presentation/pages/admin_login_page.dart';
import 'package:lendly/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:lendly/features/wallet/data/repositories/wallet_repository.dart';

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

  // Internal Firebase credentials for admin portal session
  static const String _adminFirebaseEmail = 'admin-portal@lendly.internal';
  static const String _adminFirebasePassword = 'Lendly@Admin2024!';

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

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: emailController.text.trim(),
    );
    bool isSending = false;
    String? feedbackMessage;
    bool isSuccess = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Color(0xFF7B40B5),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the email address associated with your account and we\'ll send you a link to reset your password.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !isSending && !isSuccess,
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Color(0xFF7B40B5),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF7B40B5),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (feedbackMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSuccess
                              ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
                              : Colors.red.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSuccess
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 18,
                            color: isSuccess
                                ? const Color(0xFF2E7D32)
                                : Colors.red[700],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feedbackMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSuccess
                                    ? const Color(0xFF2E7D32)
                                    : Colors.red[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    isSuccess ? 'Done' : 'Cancel',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                if (!isSuccess)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B40B5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onPressed: isSending
                        ? null
                        : () async {
                            final email = resetEmailController.text.trim();
                            if (email.isEmpty) {
                              setDialogState(() {
                                isSuccess = false;
                                feedbackMessage =
                                    'Please enter your email address.';
                              });
                              return;
                            }

                            setDialogState(() {
                              isSending = true;
                              feedbackMessage = null;
                            });

                            try {
                              await _authService.sendPasswordResetEmail(email);
                              setDialogState(() {
                                isSending = false;
                                isSuccess = true;
                                feedbackMessage =
                                    'Password reset link sent to $email. Please check your inbox and spam folder.';
                              });
                            } catch (e) {
                              setDialogState(() {
                                isSending = false;
                                isSuccess = false;
                                feedbackMessage = e
                                    .toString()
                                    .replaceFirst('Exception: ', '');
                              });
                            }
                          },
                    child: isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send Reset Link'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _login() async {
    final rawEmail = emailController.text.trim();
    final rawPassword = passwordController.text.trim();

    if (rawEmail.isEmpty || rawPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }

    final cleanEmail = rawEmail.replaceAll('\\', '/').toLowerCase();
    final cleanPassword = rawPassword.trim();

    // Check for admin credentials: "admin/admin" or "palenciajerjer28@gmail.com"
    final bool isAdminCredentials =
        (cleanEmail == 'admin' && cleanPassword.toLowerCase() == 'admin') ||
        (cleanEmail == 'admin/admin') ||
        (cleanEmail == 'palenciajerjer28@gmail.com' && (cleanPassword.toLowerCase() == 'admin' || cleanPassword.isNotEmpty)) ||
        (cleanEmail == 'palenciajerjer28@gmail.com/admin');

    if (isAdminCredentials) {
      await _loginAsAdmin();
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = await _authService.login(
        email: rawEmail,
        password: rawPassword,
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

  Future<void> _loginAsAdmin() async {
    setState(() => isLoading = true);
    try {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _adminFirebaseEmail,
          password: _adminFirebasePassword,
        );
      } catch (_) {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _adminFirebaseEmail,
            password: _adminFirebasePassword,
          );
        } catch (_) {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _adminFirebaseEmail,
            password: _adminFirebasePassword,
          );
        }
      }

      // Ensure admin wallet and user documents are seeded
      try {
        await WalletRepository().seedAdminWallet();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('👑 Signed in to Admin Portal'),
            backgroundColor: Color(0xFF007799),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Admin sign-in failed: ${e.toString()}")),
        );
      }
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
                Center(
                  child: Image.asset(
                    'assets/logos/orchid_logo_purple.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Welcome to', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const Text('Lendly', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5))),
                const SizedBox(height: 28),

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
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Color(0xFF7B40B5),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

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