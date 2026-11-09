import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lendly/core/services/cloudinary/cloudinary_service.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/items/presentation/widgets/location_picker_map_dialog.dart';
import 'package:lendly/features/profile/data/datasources/firebase_user_service.dart';
import 'package:lendly/core/utils/image_utils.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String? _uploadedImageUrl;
  bool _isLoading = false;
  bool _isDetectingGps = false;
  bool _isResettingPassword = false;
  GeoLocation? _selectedGeoLocation;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final data = await FirebaseUserService().getUserProfile();
    if (!mounted) return;
    setState(() {
      _firstNameController.text = data['firstName'] ?? '';
      _lastNameController.text = data['lastName'] ?? '';
      _usernameController.text = data['username'] ?? '';
      _emailController.text = data['email'] ?? '';
      _phoneController.text = data['phone'] ?? '';

      final parsedLoc = LocationHelper.parseCoordinates(data['location']) ??
          LocationHelper.parseCoordinates({
            'lat': data['latitude'],
            'lng': data['longitude'],
            'name': data['locationName'],
          });
      if (parsedLoc != null) {
        _selectedGeoLocation = parsedLoc;
        _locationController.text = parsedLoc.name ??
            '${parsedLoc.latitude.toStringAsFixed(4)}, ${parsedLoc.longitude.toStringAsFixed(4)}';
      } else if (data['location'] is String) {
        _locationController.text = data['location'];
      }
      _uploadedImageUrl = data['profilePictureUrl'];
    });
  }

  Future<void> _openMapLocationPicker() async {
    final initial = _selectedGeoLocation ??
        LocationHelper.parseCoordinates(_locationController.text.trim()) ??
        LocationHelper.defaultLocation;

    final result = await LocationPickerMapDialog.show(
      context,
      initialLocation: initial,
      title: 'Change Default Location',
      showRadiusSelector: false,
    );

    if (result != null && mounted) {
      setState(() {
        _selectedGeoLocation = result.location;
        _locationController.text = result.location.name ??
            '${result.location.latitude.toStringAsFixed(4)}, ${result.location.longitude.toStringAsFixed(4)}';
      });
    }
  }

  Future<void> _detectCurrentGpsLocation() async {
    if (_isDetectingGps) return;
    setState(() => _isDetectingGps = true);
    try {
      final loc = await LocationHelper.getDeviceLocation();
      if (!mounted) return;
      final safeLoc = LocationHelper.sanitizeToPhilippines(loc);
      setState(() {
        _selectedGeoLocation = safeLoc;
        _locationController.text = safeLoc.name ??
            '${safeLoc.latitude.toStringAsFixed(4)}, ${safeLoc.longitude.toStringAsFixed(4)}';
        _isDetectingGps = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isDetectingGps = false);
      }
    }
  }

  Future<void> _pickProfilePicture() async {
    try {
      final imageUrl = await CloudinaryService.uploadImage();
      if (imageUrl != null) {
        setState(() {
          _uploadedImageUrl = imageUrl;
        });
      } else {
        throw Exception('Image upload failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: ${e.toString()}')),
      );
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);

    try {
      final locationText = _locationController.text.trim();
      final parsed = LocationHelper.parseCoordinates(locationText) ?? _selectedGeoLocation;
      final Map<String, dynamic>? locationMap = parsed != null
          ? {
              'lat': parsed.latitude,
              'lng': parsed.longitude,
              'name': locationText.isNotEmpty
                  ? locationText
                  : (parsed.name ?? '${parsed.latitude.toStringAsFixed(3)}, ${parsed.longitude.toStringAsFixed(3)}'),
              'geohash': '',
            }
          : null;

      await FirebaseUserService().updateUserProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        location: locationMap,
        photoURL: _uploadedImageUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile & default location updated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : FirebaseAuth.instance.currentUser?.email ?? '';

    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an email address to send the password reset link.')),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Color(0xFF7B40B5)),
            SizedBox(width: 8),
            Text('Reset Password'),
          ],
        ),
        content: Text(
          'A secure password reset email will be sent to:\n\n$email\n\nWould you like to send it now?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B40B5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isResettingPassword = true);
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Password reset link sent to $email. Please check your inbox.'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send reset link: ${e.toString()}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isResettingPassword = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  height: 200,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF74CBE6), Color(0xFFB6E0F5)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  left: 16,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: 100,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Stack(
                          alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: isValidImageUrl(_uploadedImageUrl)
                                ? NetworkImage(_uploadedImageUrl!)
                                : const AssetImage('assets/images/Profile.jpg') as ImageProvider,
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: _pickProfilePicture,
                              child: const CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.edit, size: 16, color: Colors.blue),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Edit Profile", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _buildTextField(label: "First Name", controller: _firstNameController),
                    const SizedBox(height: 12),
                    _buildTextField(label: "Last Name", controller: _lastNameController),
                    const SizedBox(height: 12),
                    _buildTextField(label: "Username", controller: _usernameController),
                    const SizedBox(height: 12),
                    _buildEmailField(),
                    const SizedBox(height: 12),
                    _buildPhoneField(),
                    const SizedBox(height: 12),
                    _buildLocationField(),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B40B5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isLoading ? null : _saveProfile,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          _isLoading ? "Saving..." : "Save Changes",
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7B40B5),
                          side: const BorderSide(color: Color(0xFF7B40B5), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isResettingPassword ? null : _handleResetPassword,
                        icon: _isResettingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF7B40B5),
                                ),
                              )
                            : const Icon(Icons.lock_reset, size: 20),
                        label: Text(
                          _isResettingPassword ? "Sending Reset Link..." : "Reset Password",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
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

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Default Discovery Location",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (_selectedGeoLocation != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_selectedGeoLocation!.latitude.toStringAsFixed(3)}, ${_selectedGeoLocation!.longitude.toStringAsFixed(3)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7B40B5),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _locationController,
          onChanged: (val) {
            final parsed = LocationHelper.parseCoordinates(val);
            if (parsed != null) {
              setState(() => _selectedGeoLocation = parsed);
            }
          },
          decoration: InputDecoration(
            hintText: 'e.g. Bacolod City or 10.67, 122.95',
            prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF7B40B5)),
            suffixIcon: PopupMenuButton<GeoLocation>(
              icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Color(0xFF7B40B5)),
              tooltip: 'Choose Preset City',
              onSelected: (loc) {
                setState(() {
                  _selectedGeoLocation = loc;
                  _locationController.text =
                      (loc.name ?? '${loc.latitude}, ${loc.longitude}').split('(').first.trim();
                });
              },
              itemBuilder: (context) {
                return LocationHelper.presetLocations.map((loc) {
                  return PopupMenuItem<GeoLocation>(
                    value: loc,
                    child: Text(
                      loc.name ?? '${loc.latitude}, ${loc.longitude}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList();
              },
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isDetectingGps ? null : _detectCurrentGpsLocation,
                icon: _isDetectingGps
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF7B40B5),
                        ),
                      )
                    : const Icon(Icons.my_location, size: 16),
                label: const Text('Use Current GPS', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B40B5),
                  side: const BorderSide(color: Color(0xFF7B40B5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openMapLocationPicker,
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Pin on Map', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B40B5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Email", style: TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          decoration: InputDecoration(
            hintText: "your email address",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Phone Number", style: TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: "e.g. +639123456789",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
