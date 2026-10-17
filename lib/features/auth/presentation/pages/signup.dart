import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/auth/data/datasources/firebase_auth_service.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // Step tracking
  int _currentStep = 0;

  // Form keys per step
  final _step0Key = GlobalKey<FormState>();
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();

  // ── Personal Info ──
  final _firstNameController    = TextEditingController();
  final _middleNameController   = TextEditingController();
  final _lastNameController     = TextEditingController();
  final _suffixController       = TextEditingController();
  final _birthdateController    = TextEditingController();
  String _sex = 'Male';
  String _civilStatus = 'Single';

  // ── Contact ──
  final _emailController    = TextEditingController();
  final _phoneController    = TextEditingController();
  final _altPhoneController = TextEditingController();

  // ── Address ──
  final _streetController   = TextEditingController();
  final _barangayController = TextEditingController();
  final _cityController     = TextEditingController();
  final _provinceController = TextEditingController();
  final _zipController      = TextEditingController();

  // ── Occupation / Emergency Contact ──
  final _occupationController        = TextEditingController();
  final _employerController          = TextEditingController();
  final _emergencyNameController     = TextEditingController();
  final _emergencyPhoneController    = TextEditingController();
  final _emergencyRelationController = TextEditingController();

  // ── Account ──
  final _passwordController       = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword        = true;
  bool _obscureConfirmPassword = true;

  // ── Appraiser ──
  bool   _isAppraiser    = false;
  String _specialization = 'Electronics & Technology';
  final _businessNameController  = TextEditingController();
  final _licenseNumberController = TextEditingController();

  bool _isLoading = false;

  final _emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');

  final List<String> _sexOptions         = ['Male', 'Female', 'Prefer not to say'];
  final List<String> _civilStatusOptions = ['Single', 'Married', 'Widowed', 'Separated'];
  final List<String> _specializations    = [
    'Electronics & Technology',
    'Industrial Tools & Equipment',
    'Jewelry & Luxury Goods',
    'Vehicles & Transport',
    'Musical Instruments',
    'General Merchandise',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _suffixController.dispose();
    _birthdateController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _zipController.dispose();
    _occupationController.dispose();
    _employerController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }

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

  GlobalKey<FormState> get _currentFormKey {
    switch (_currentStep) {
      case 0: return _step0Key;
      case 1: return _step1Key;
      case 2: return _step2Key;
      default: return _step3Key;
    }
  }

  void _continue() {
    if (_currentFormKey.currentState!.validate()) {
      if (_currentStep < 3) {
        setState(() => _currentStep++);
      } else {
        _signUp();
      }
    }
  }

  void _cancel() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      final user = await FirebaseAuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        suffix: _suffixController.text.trim(),
        birthdate: DateFormat('yyyy-MM-dd').parse(_birthdateController.text),
        sex: _sex,
        civilStatus: _civilStatus,
        phone: _phoneController.text.trim(),
        altPhone: _altPhoneController.text.trim(),
        street: _streetController.text.trim(),
        barangay: _barangayController.text.trim(),
        city: _cityController.text.trim(),
        province: _provinceController.text.trim(),
        zip: _zipController.text.trim(),
        occupation: _occupationController.text.trim(),
        employer: _employerController.text.trim(),
        emergencyName: _emergencyNameController.text.trim(),
        emergencyPhone: _emergencyPhoneController.text.trim(),
        emergencyRelation: _emergencyRelationController.text.trim(),
        isAppraiser: _isAppraiser,
        businessName: _isAppraiser ? _businessNameController.text.trim() : null,
        licenseNumber: _isAppraiser ? _licenseNumberController.text.trim() : null,
        specialization: _isAppraiser ? _specialization : null,
      );

      if (user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Check your email to verify.'),
            duration: Duration(seconds: 5),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage(initialEmail: user.email)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign up failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Create Account',
          style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
        ),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A2E)),
                onPressed: _cancel,
              )
            : null,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _buildCurrentStep(),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Personal', 'Contact', 'Address', 'Account'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive    = i == _currentStep;
          final isCompleted = i < _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? const Color(0xFF7B40B5)
                              : isActive
                                  ? const Color(0xFF90E0F3)
                                  : Colors.grey[200],
                          border: isActive
                              ? Border.all(color: const Color(0xFF7B40B5), width: 2)
                              : null,
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? const Color(0xFF7B40B5) : Colors.grey,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? const Color(0xFF7B40B5) : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: isCompleted ? const Color(0xFF7B40B5) : Colors.grey[300],
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildPersonalStep();
      case 1: return _buildContactStep();
      case 2: return _buildAddressStep();
      default: return _buildAccountStep();
    }
  }

  // ══════════════════════════════════════════
  // STEP 0 – Personal Information
  // ══════════════════════════════════════════
  Widget _buildPersonalStep() {
    return Form(
      key: _step0Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Personal Information'),
          const SizedBox(height: 16),
          _buildField(controller: _firstNameController,  hint: 'First Name *',             icon: Icons.person,         validator: _required),
          const SizedBox(height: 12),
          _buildField(controller: _middleNameController, hint: 'Middle Name',              icon: Icons.person_outline),
          const SizedBox(height: 12),
          _buildField(controller: _lastNameController,   hint: 'Last Name *',              icon: Icons.person,         validator: _required),
          const SizedBox(height: 12),
          _buildField(controller: _suffixController,     hint: 'Suffix (e.g. Jr., III)',   icon: Icons.short_text),
          const SizedBox(height: 12),
          _buildField(
            controller: _birthdateController,
            hint: 'Birthdate *',
            icon: Icons.calendar_today,
            readOnly: true,
            onTap: _selectBirthdate,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              try {
                final bd  = DateFormat('yyyy-MM-dd').parse(v);
                final age = DateTime.now().year - bd.year;
                if (age < 18) return 'Must be at least 18 years old';
              } catch (_) {
                return 'Invalid date';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Sex *',
            icon: Icons.wc,
            value: _sex,
            items: _sexOptions,
            onChanged: (v) => setState(() => _sex = v!),
          ),
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Civil Status *',
            icon: Icons.favorite,
            value: _civilStatus,
            items: _civilStatusOptions,
            onChanged: (v) => setState(() => _civilStatus = v!),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // STEP 1 – Contact Information
  // ══════════════════════════════════════════
  Widget _buildContactStep() {
    return Form(
      key: _step1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Contact Information'),
          const SizedBox(height: 16),
          _buildField(
            controller: _emailController,
            hint: 'Email Address *',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => !_emailRegex.hasMatch(v ?? '') ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _phoneController,
            hint: 'Mobile Number * (e.g. 09XXXXXXXXX)',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!RegExp(r'^09\d{9}$').hasMatch(v)) return 'Enter a valid PH mobile number';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _altPhoneController,
            hint: 'Alternate Phone / Landline',
            icon: Icons.phone_in_talk,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          _sectionTitle('Emergency Contact'),
          const SizedBox(height: 16),
          _buildField(
            controller: _emergencyNameController,
            hint: 'Emergency Contact Name *',
            icon: Icons.contact_emergency,
            validator: _required,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _emergencyPhoneController,
            hint: 'Emergency Contact Number *',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            validator: _required,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _emergencyRelationController,
            hint: 'Relationship (e.g. Mother, Spouse)',
            icon: Icons.people,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // STEP 2 – Address & Occupation
  // ══════════════════════════════════════════
  Widget _buildAddressStep() {
    return Form(
      key: _step2Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Home Address'),
          const SizedBox(height: 16),
          _buildField(controller: _streetController,   hint: 'Street / Unit No., Building *', icon: Icons.home,          validator: _required),
          const SizedBox(height: 12),
          _buildField(controller: _barangayController, hint: 'Barangay *',                     icon: Icons.location_city, validator: _required),
          const SizedBox(height: 12),
          _buildField(controller: _cityController,     hint: 'City / Municipality *',           icon: Icons.location_city, validator: _required),
          const SizedBox(height: 12),
          _buildField(controller: _provinceController, hint: 'Province *',                     icon: Icons.map,            validator: _required),
          const SizedBox(height: 12),
          _buildField(
            controller: _zipController,
            hint: 'ZIP Code *',
            icon: Icons.pin,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            validator: (v) => (v == null || v.length != 4) ? 'Enter a valid 4-digit ZIP code' : null,
          ),
          const SizedBox(height: 24),
          _sectionTitle('Occupation'),
          const SizedBox(height: 16),
          _buildField(controller: _occupationController, hint: 'Occupation / Profession',   icon: Icons.work),
          const SizedBox(height: 12),
          _buildField(controller: _employerController,   hint: 'Employer / Company Name', icon: Icons.business),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // STEP 3 – Account Setup
  // ══════════════════════════════════════════
  Widget _buildAccountStep() {
    return Form(
      key: _step3Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Account Setup'),
          const SizedBox(height: 16),
          _buildField(
            controller: _passwordController,
            hint: 'Password *',
            icon: Icons.lock,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _confirmPasswordController,
            hint: 'Confirm Password *',
            icon: Icons.lock_outline,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 24),

          // ── Appraiser Toggle ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isAppraiser
                  ? const Color(0xFF7B40B5).withValues(alpha: 0.08)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isAppraiser ? const Color(0xFF7B40B5) : Colors.grey[300]!,
                width: _isAppraiser ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFF7B40B5),
                  title: const Text(
                    'Register as Business / Professional Appraiser',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B40B5),
                    ),
                  ),
                  subtitle: const Text(
                    'Offer certified item valuations & official appraisals',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  value: _isAppraiser,
                  onChanged: (val) => setState(() => _isAppraiser = val),
                ),
                if (_isAppraiser) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Color(0xFF7B40B5)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Manual Verification: You will submit photos of your BIR permits or business registration papers from your profile for admin verification before appraiser status is activated.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF5A2A94), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _businessNameController,
                    hint: 'Business / Agency Name *',
                    icon: Icons.business,
                    validator: (v) => _isAppraiser && (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _licenseNumberController,
                    hint: 'License / Accreditation No. (e.g. APP-2026-XXXX)',
                    icon: Icons.verified_user,
                    validator: (v) => _isAppraiser && (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Specialization Category',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _specialization,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.category),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _specializations.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)));
                    }).toList(),
                    onChanged: (val) { if (val != null) setState(() => _specialization = val); },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          TextButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
            child: const Text('Already have an account? Login'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Bottom action bar ──
  Widget _buildBottomBar() {
    final isLastStep = _currentStep == 3;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF7B40B5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Back', style: TextStyle(color: Color(0xFF7B40B5))),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B40B5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      isLastStep ? 'Create Account' : 'Continue',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──
  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
  );

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onTap: onTap,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF7B40B5)),
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 1.5),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF7B40B5)),
        labelText: label,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7B40B5), width: 1.5),
        ),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}