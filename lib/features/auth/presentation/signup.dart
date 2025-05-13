import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/auth/data/firebase_auth_service.dart';
import 'package:lendly/features/auth/presentation/login.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  Future<void> _selectBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _birthdateController.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = await FirebaseAuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        birthdate: DateFormat('yyyy-MM-dd').parse(_birthdateController.text),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      if (user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent! Please check your inbox.'),
            duration: Duration(seconds: 5),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage(initialEmail: user.email)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sign up failed: ${e.toString()}")),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(32),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  const Text('Create Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),

              _buildTextFormField(
                controller: _firstNameController,
                hint: 'First Name',
                icon: Icons.person,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              _buildTextFormField(
                controller: _lastNameController,
                hint: 'Last Name',
                icon: Icons.person_outline,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              _buildTextFormField(
                controller: _emailController,
                hint: 'Email',
                icon: Icons.email,
                validator: (value) =>
                !_emailRegex.hasMatch(value!) ? 'Invalid email' : null,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              _buildTextFormField(
                controller: _passwordController,
                hint: 'Password',
                icon: Icons.lock,
                obscureText: _obscurePassword,
                validator: (value) =>
                value!.length < 6 ? 'Minimum 6 characters' : null,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),

              _buildTextFormField(
                  controller: _confirmPasswordController,
                  hint: 'Confirm Password',
                  icon: Icons.lock,
                  obscureText: _obscureConfirmPassword,
                  validator: (value) =>
                  value != _passwordController.text ? 'Passwords do not match' : null,
              suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
          const SizedBox(height: 16),

          _buildTextFormField(
            controller: _birthdateController,
            hint: 'Birthdate',
            icon: Icons.calendar_today,
            readOnly: true,
            onTap: _selectBirthdate,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              try {
                final birthDate = DateFormat('yyyy-MM-dd').parse(value);
                final age = DateTime.now().year - birthDate.year;
                if (age < 18) return 'Must be 18+ years old';
              } catch (e) {
                return 'Invalid date';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF90E0F3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Sign Up', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 24),

          TextButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
            child: const Text('Already have an account? Login'),
          ),
          ],
        ),
      ),
    ),
    ),
    ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      keyboardType: keyboardType,
      validator: validator,
      onTap: onTap,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}