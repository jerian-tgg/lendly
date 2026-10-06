import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lendly/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  // Internal Firebase credentials for the admin session.
  // These are never shown to the user — the user only sees "admin/admin".
  static const String _adminFirebaseEmail = 'admin-portal@lendly.internal';
  static const String _adminFirebasePassword = 'Lendly@Admin2024!';

  Future<void> _login() async {
    final rawUser = _usernameController.text.trim();
    final rawPass = _passwordController.text.trim();

    final cleanUser = rawUser.replaceAll('\\', '/').toLowerCase();
    final cleanPass = rawPass.trim();

    // Check credentials:
    // Only 'admin' / 'admin' and 'palenciajerjer28@gmail.com' / 'admin' are allowed
    final bool isValidAdmin =
        (cleanUser == 'admin' && cleanPass.toLowerCase() == 'admin') ||
        (cleanUser == 'admin/admin') ||
        (cleanUser == 'palenciajerjer28@gmail.com' && cleanPass.toLowerCase() == 'admin') ||
        (cleanUser == 'palenciajerjer28@gmail.com/admin');

    if (!isValidAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid admin credentials. Use admin / admin'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Sign in with the Firebase admin credentials
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _adminFirebaseEmail,
          password: _adminFirebasePassword,
        );
      } catch (_) {
        // If signIn fails, attempt createUser in case it doesn't exist yet
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _adminFirebaseEmail,
            password: _adminFirebasePassword,
          );
        } catch (_) {
          // If creation fails (e.g. already exists), retry signIn once
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _adminFirebaseEmail,
            password: _adminFirebasePassword,
          );
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToRegularLogin() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Login'),
        backgroundColor: const Color(0xFF007799),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Regular Login',
          onPressed: _loading ? null : _navigateToRegularLogin,
        ),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings,
                    size: 56, color: Color(0xFF007799)),
                const SizedBox(height: 16),
                const Text('Admin Portal',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF007799))),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person),
                    hintText: 'Username',
                    filled: true,
                    fillColor: Color(0xFFEFF6F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock),
                    hintText: 'Password',
                    filled: true,
                    fillColor: const Color(0xFFEFF6F9),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007799),
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login',
                            style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _loading ? null : _navigateToRegularLogin,
                  icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF007799)),
                  label: const Text(
                    'Back to User Login',
                    style: TextStyle(
                      color: Color(0xFF007799),
                      fontWeight: FontWeight.w600,
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
}
