import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/location_helper.dart';
import 'package:lendly/features/auth/presentation/pages/login.dart';
import 'package:lendly/features/chat/presentation/pages/conversation_screen.dart';
import 'package:lendly/features/items/presentation/pages/transactions_page.dart';
import 'package:lendly/features/items/presentation/pages/search_screen.dart';
import 'package:lendly/features/items/presentation/widgets/add_item_dialog.dart';
import 'package:lendly/features/items/presentation/widgets/item_card.dart';
import 'package:lendly/features/profile/presentation/pages/profile_page.dart';
import 'package:lendly/core/utils/image_utils.dart';
import 'package:lendly/features/appraisal/presentation/pages/appraisal_dashboard.dart';
import 'package:lendly/features/auth/data/datasources/firebase_auth_service.dart';
import 'package:lendly/features/items/presentation/widgets/location_picker_map_dialog.dart';
import 'package:lendly/features/wallet/presentation/pages/orc_wallet_screen.dart';
import 'package:lendly/features/wallet/presentation/widgets/cash_in_dialog.dart';

class HomeScreen extends StatefulWidget {
  final bool isGuest;

  const HomeScreen({super.key, this.isGuest = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  bool get isVisitor =>
      widget.isGuest || FirebaseAuth.instance.currentUser == null;

  List<Widget> get _screens => isVisitor
      ? const [
          ItemListScreen(),
          SearchScreen(),
        ]
      : [
          const ItemListScreen(),
          const SearchScreen(),
          const TransactionsPage(),
          ConversationScreen(),
          const UserProfilePage(),
        ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _showLogoutConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Log Out', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: _selectedIndex == 0
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 1,
              titleSpacing: 16,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFE8FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_florist,
                      color: Color(0xFF7B40B5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ORCHID',
                    style: TextStyle(
                      color: Color(0xFF7B40B5),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Lendly',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (isVisitor) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Visitor',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7B40B5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (isVisitor)
                  TextButton.icon(
                    icon: const Icon(Icons.login, color: Color(0xFF7B40B5)),
                    label: const Text(
                      'Log In',
                      style: TextStyle(
                        color: Color(0xFF7B40B5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                  )
                else ...[
                  // Admin & Appraiser quick-access buttons
                  StreamBuilder<DocumentSnapshot>(
                    stream: user != null
                        ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
                        : null,
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data() as Map<String, dynamic>?;
                      final isAppraiser = data?['isAppraiser'] == true &&
                          data?['businessVerificationStatus'] == 'approved';

                      if (!isAppraiser) {
                        return const SizedBox.shrink();
                      }

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.assessment_outlined, color: Color(0xFF7B40B5)),
                            tooltip: 'Professional Appraisal Portal',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AppraisalDashboard()),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_none_outlined,
                      color: Colors.black54,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No new notifications')),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: user != null
                          ? FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .snapshots()
                          : null,
                      builder: (context, snapshot) {
                        String? photoUrl;
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          photoUrl =
                              data?['photoURL'] ?? data?['profilePictureUrl'];
                        }

                        return GestureDetector(
                          onTap: () => _onItemTapped(4),
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: const Color(0xFF90E0F3),
                            backgroundImage: isValidImageUrl(photoUrl)
                                ? NetworkImage(photoUrl!)
                                : null,
                            child: !isValidImageUrl(photoUrl)
                                ? const Icon(
                                    Icons.person,
                                    size: 20,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.grey),
                    tooltip: 'Logout',
                    onPressed: _showLogoutConfirmation,
                  ),
                ],
              ],
            )
          : null,
      body: _screens[_selectedIndex.clamp(0, _screens.length - 1)],
      floatingActionButton: (!isVisitor && _selectedIndex == 0)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF7B40B5),
              elevation: 4,
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AddItemDialog(),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Lend Item',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: isVisitor
            ? const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Browse',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_outlined),
                  activeIcon: Icon(Icons.search),
                  label: 'Search',
                ),
              ]
            : const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_outlined),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined),
                  activeIcon: Icon(Icons.receipt_long),
                  label: 'Transactions',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_outlined),
                  label: 'Messages',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outlined),
                  label: 'Profile',
                ),
              ],
        currentIndex: _selectedIndex.clamp(0, isVisitor ? 1 : 4),
        selectedItemColor: const Color(0xFF7B40B5),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class VisitorPromptView extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const VisitorPromptView({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6F9),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF90E0F3).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: const Color(0xFF007799)),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF90E0F3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: const Text(
                    'Log In / Sign Up',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedMode = 'All'; // All, Lend, Borrow, Nearby
  double _selectedRadiusKm =
      25.0; // Geographical radius filter (5, 10, 25, 50, 100=Any)
  bool _isGridView = true; // Two-column marketplace layout toggle

  GeoLocation _currentReferenceLocation = LocationHelper.defaultLocation;
  final Map<String, GeoLocation> _ownerLocationsCache = {};

  final List<String> _categories = [
    'All',
    'Electronics',
    'Appliances',
    'Tools',
    'Books',
    'Furniture',
    'Clothing',
    'Other',
  ];

  final List<double> _radiusOptions = [5.0, 10.0, 25.0, 50.0, 100.0];

  @override
  void initState() {
    super.initState();
    _loadUserReferenceLocation();
  }

  Future<void> _loadUserReferenceLocation() async {
    // 1. First attempt: retrieve real device location via GPS / device location service
    try {
      final deviceLoc = await LocationHelper.getDeviceLocation();
      if (deviceLoc != null && mounted) {
        setState(() {
          _currentReferenceLocation = deviceLoc;
        });
        return;
      }
    } catch (_) {}

    // 2. Second attempt: look up user's saved location in Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data();
          final loc = LocationHelper.parseCoordinates(data?['location']);
          if (loc != null) {
            setState(() {
              _currentReferenceLocation = loc;
            });
            return;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await LocationPickerMapDialog.show(
      context,
      initialLocation: _currentReferenceLocation,
      initialRadiusKm: _selectedRadiusKm,
      title: 'Set Location & Radius',
    );

    if (result != null && mounted) {
      setState(() {
        _currentReferenceLocation = result.location;
        _selectedRadiusKm = result.radiusKm;
      });

      // Persist to user profile if logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'location': '${result.location.latitude.toStringAsFixed(6)}, ${result.location.longitude.toStringAsFixed(6)}',
            'locationName': result.location.name,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
    }
  }

  Future<void> _fetchAndCacheOwnerLocation(String ownerId) async {
    if (_ownerLocationsCache.containsKey(ownerId)) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(ownerId).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        final loc = LocationHelper.parseCoordinates(data?['location']);
        if (loc != null) {
          setState(() {
            _ownerLocationsCache[ownerId] = loc;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, color: Color(0xFF7B40B5)),
                          SizedBox(width: 8),
                          Text(
                            'Marketplace Filters',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Reference Location Bar & Map Pin Picker (Geographical Radius Center!)
                  InkWell(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _openLocationPicker();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F5FE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B40B5).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.pin_drop, size: 20, color: Color(0xFF7B40B5)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Search Center / Location Pin',
                                  style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  _currentReferenceLocation.name ??
                                      '${_currentReferenceLocation.latitude.toStringAsFixed(4)}, ${_currentReferenceLocation.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Text(
                                  'Tap to open map & move pin manually',
                                  style: TextStyle(fontSize: 10, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B40B5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map, size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Map Pin',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Geographical Radius Filter (Feature 4!)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.location_searching,
                            size: 18,
                            color: Color(0xFF7B40B5),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Geographical Radius:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Text(
                        _selectedRadiusKm >= 100.0
                            ? 'Any distance'
                            : '${_selectedRadiusKm.toInt()} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B40B5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: _selectedRadiusKm,
                    min: 5.0,
                    max: 100.0,
                    divisions: 19,
                    activeColor: const Color(0xFF7B40B5),
                    inactiveColor: Colors.purple.shade50,
                    label: _selectedRadiusKm >= 100.0
                        ? 'Any'
                        : '${_selectedRadiusKm.toInt()} km',
                    onChanged: (val) {
                      setModalState(() {
                        _selectedRadiusKm = val;
                      });
                      setState(() {
                        _selectedRadiusKm = val;
                      });
                    },
                  ),
                  Wrap(
                    spacing: 6,
                    children: _radiusOptions.map((rad) {
                      final isSelected = _selectedRadiusKm == rad;
                      final label = rad >= 100.0
                          ? 'Any distance'
                          : '${rad.toInt()} km';
                      return ChoiceChip(
                        label: Text(
                          label,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFF7B40B5),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() => _selectedRadiusKm = rad);
                            setState(() => _selectedRadiusKm = rad);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedRadiusKm >= 100.0
                        ? 'Showing items across all locations'
                        : 'Filtering items within ${_selectedRadiusKm.toInt()} km of ${_currentReferenceLocation.name ?? 'current location'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),

                  const SizedBox(height: 16),

                  // Category Filter (Feature 3!)
                  const Text(
                    'Category:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: const Color(0xFF7B40B5),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() => _selectedCategory = cat);
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedCategory = 'All';
                              _selectedRadiusKm = 100.0;
                              _searchController.clear();
                              _searchQuery = '';
                            });
                            setState(() {
                              _selectedCategory = 'All';
                              _selectedRadiusKm = 100.0;
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                          child: const Text('Reset All'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B40B5),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Apply Filters'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Balance Box (for authenticated users) or Visitor Welcome Banner
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('wallets')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  double available = 0.0;
                  double escrow = 0.0;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      available = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
                      escrow = (data['escrowBalance'] as num?)?.toDouble() ?? 0.0;
                    }
                  }

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrcWalletScreen()),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B40B5).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Available Balance:',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₱ ${available.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (escrow > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.lock_clock, size: 12, color: Colors.amber[200]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Escrow: ₱${escrow.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: Colors.amber[200],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),

                          ElevatedButton.icon(
                            onPressed: () => CashInDialog.show(context),
                            icon: const Icon(
                              Icons.add_card,
                              size: 16,
                              color: Color(0xFF7B40B5),
                            ),
                            label: const Text(
                              'Cash In',
                              style: TextStyle(
                                color: Color(0xFF7B40B5),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8A56AC), Color(0xFF5B32A8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B40B5).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.explore_outlined, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Browsing as Visitor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Explore items & search available rentals. Log in anytime to borrow.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Enhanced Search Bar (Feature 3!)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase().trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search items, tools, camera, owner...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF7B40B5),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.grey,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                      IconButton(
                        icon: Stack(
                          children: [
                            const Icon(Icons.tune, color: Color(0xFF7B40B5)),
                            if (_selectedCategory != 'All' ||
                                _selectedRadiusKm < 100.0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.amber,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        tooltip: 'Filter options',
                        onPressed: _showFilterModal,
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          // Facebook Marketplace Location & Radius Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: InkWell(
              onTap: _openLocationPicker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.place,
                        size: 16,
                        color: Color(0xFF7B40B5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _currentReferenceLocation.name ??
                                      '${_currentReferenceLocation.latitude.toStringAsFixed(3)}, ${_currentReferenceLocation.longitude.toStringAsFixed(3)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF2D3748),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _selectedRadiusKm >= 100.0 ? 'Any distance' : 'Within ${_selectedRadiusKm.toInt()} km',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7B40B5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _selectedRadiusKm >= 100.0
                                ? 'Tap to drop map pin & filter distance'
                                : 'Showing items within ${_selectedRadiusKm.toInt()} km • Tap to adjust pin on map',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_location_alt, size: 14, color: Color(0xFF7B40B5)),
                          SizedBox(width: 4),
                          Text(
                            'Map Pin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7B40B5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Mode Filter Tabs (LEND, BORROW, NEARBY)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildModeChip('All', Icons.grid_view),
                const SizedBox(width: 8),
                _buildModeChip('Lend', Icons.volunteer_activism_outlined),
                const SizedBox(width: 8),
                _buildModeChip('Borrow', Icons.shopping_bag_outlined),
                const SizedBox(width: 8),
                _buildModeChip('Nearby', Icons.location_on_outlined),
              ],
            ),
          ),

          // Horizontal Category Filter Pills (Feature 3: Category search!)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: const Color(0xFF7B40B5),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF7B40B5)
                          : Colors.grey.shade300,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[800],
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = cat);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Active Radius & Search Filter Summary Chip Bar (Feature 4!)
          if (_selectedRadiusKm < 100.0 ||
              _searchQuery.isNotEmpty ||
              _selectedCategory != 'All')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Active:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  if (_selectedRadiusKm < 100.0)
                    Chip(
                      avatar: const Icon(Icons.location_on, size: 12, color: Color(0xFF7B40B5)),
                      label: Text(
                        'Radius: ${_selectedRadiusKm.toInt()} km (${_currentReferenceLocation.name?.split(' ').first ?? 'Custom'})',
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () =>
                          setState(() => _selectedRadiusKm = 100.0),
                    ),
                  if (_selectedCategory != 'All')
                    Chip(
                      label: Text(
                        'Category: $_selectedCategory',
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () =>
                          setState(() => _selectedCategory = 'All'),
                    ),
                  if (_searchQuery.isNotEmpty)
                    Chip(
                      label: Text(
                        'Query: "$_searchQuery"',
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // Feed Header with Two-Column Marketplace Grid Toggle (Feature 2!)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCategory == 'All'
                          ? 'Marketplace Feed'
                          : '$_selectedCategory Items',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      _selectedRadiusKm < 100.0
                          ? 'Showing items within ${_selectedRadiusKm.toInt()} km of ${_currentReferenceLocation.name ?? 'your location'}'
                          : 'Live items nearby',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),

                // Layout View Toggle Button (Two-Column Grid vs Single List)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _isGridView = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isGridView
                                ? const Color(0xFF7B40B5)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            size: 18,
                            color: _isGridView
                                ? Colors.white
                                : Colors.grey[700],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _isGridView = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: !_isGridView
                                ? const Color(0xFF7B40B5)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.view_list_rounded,
                            size: 18,
                            color: !_isGridView
                                ? Colors.white
                                : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Firestore Item Feed Stream (Two-Column Grid or List View!)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('items')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Error loading items: ${snapshot.error}'),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF7B40B5)),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              // Apply Search Query, Category Filter, and Geographical Radius Filter (Feature 3 & 4!)
              final filteredDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] ?? data['title'] ?? '')
                    .toString()
                    .toLowerCase();
                final category = (data['category'] ?? '')
                    .toString()
                    .toLowerCase();
                final description = (data['description'] ?? '')
                    .toString()
                    .toLowerCase();
                final ownerName = (data['ownerName'] ?? '')
                    .toString()
                    .toLowerCase();
                final condition = (data['condition'] ?? '')
                    .toString()
                    .toLowerCase();

                // Multi-field Search Matching
                final matchesSearch =
                    _searchQuery.isEmpty ||
                    name.contains(_searchQuery) ||
                    description.contains(_searchQuery) ||
                    category.contains(_searchQuery) ||
                    ownerName.contains(_searchQuery) ||
                    condition.contains(_searchQuery);

                // Category Matching
                final matchesCategory =
                    _selectedCategory == 'All' ||
                    category == _selectedCategory.toLowerCase();

                // Calculate Functional Geographical Distance (Haversine formula!)
                GeoLocation? itemCoords = LocationHelper.extractItemCoordinates(data);
                if (itemCoords == null && data['ownerId'] != null) {
                  itemCoords = _ownerLocationsCache[data['ownerId']];
                  if (itemCoords == null) {
                    _fetchAndCacheOwnerLocation(data['ownerId']);
                  }
                }

                final double distanceKm;
                if (itemCoords != null) {
                  distanceKm = LocationHelper.calculateDistance(
                    _currentReferenceLocation.latitude,
                    _currentReferenceLocation.longitude,
                    itemCoords.latitude,
                    itemCoords.longitude,
                  );
                } else {
                  // Fallback for items without explicit coordinates
                  distanceKm = (data['distanceKm'] as num?)?.toDouble() ??
                      LocationHelper.calculateDistance(
                        _currentReferenceLocation.latitude,
                        _currentReferenceLocation.longitude,
                        LocationHelper.defaultLocation.latitude,
                        LocationHelper.defaultLocation.longitude,
                      );
                }

                // Write computed distance and location to data map for ItemCard and ItemDetailScreen
                data['distanceKm'] = distanceKm;
                if (itemCoords?.name != null && (data['location'] == null || (data['location'] as String).isEmpty)) {
                  data['location'] = itemCoords!.name;
                }

                // Geographical Radius Filter Matching (Feature 4!)
                final matchesRadius = _selectedRadiusKm >= 100.0 || distanceKm <= _selectedRadiusKm;

                // Mode Matching ('Nearby' tab filters to <= 25km or selected radius)
                final matchesMode = _selectedMode == 'All' ||
                    (_selectedMode == 'Lend' && data['ownerId'] == user?.uid) ||
                    (_selectedMode == 'Borrow' && data['ownerId'] != user?.uid) ||
                    (_selectedMode == 'Nearby' && distanceKm <= (_selectedRadiusKm < 25.0 ? _selectedRadiusKm : 25.0));

                return matchesSearch &&
                    matchesCategory &&
                    matchesMode &&
                    matchesRadius;
              }).toList();

              // Proximity Sorting: Sort by closest distance when in Nearby mode or active radius filter
              if (_selectedMode == 'Nearby' || _selectedRadiusKm < 100.0) {
                filteredDocs.sort((a, b) {
                  final distA = ((a.data() as Map<String, dynamic>)['distanceKm'] as num?)?.toDouble() ?? double.infinity;
                  final distB = ((b.data() as Map<String, dynamic>)['distanceKm'] as num?)?.toDouble() ?? double.infinity;
                  return distA.compareTo(distB);
                });
              }

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No items found matching "$_searchQuery"'
                              : _selectedRadiusKm < 100.0
                                  ? 'No items found within ${_selectedRadiusKm.toInt()} km of ${_currentReferenceLocation.name ?? 'your location'}.'
                                  : 'No items found within your selected filters.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            if (_selectedRadiusKm < 100.0)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.zoom_out_map, size: 16),
                                label: const Text('Expand to Any Distance'),
                                onPressed: () => setState(() => _selectedRadiusKm = 100.0),
                              ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                  _selectedCategory = 'All';
                                  _selectedMode = 'All';
                                  _selectedRadiusKm = 100.0;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B40B5),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Reset All Filters'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Two-Column Grid Marketplace Layout (Feature 2!)
              if (_isGridView) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio:
                          0.65, // Ideal ratio for marketplace card with ribbon
                    ),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final itemData = doc.data() as Map<String, dynamic>;
                      final imageUrls =
                          itemData['imageUrls'] as List<dynamic>? ?? [];
                      final imagePath = imageUrls.isNotEmpty
                          ? imageUrls[0].toString()
                          : (itemData['imageUrl'] ?? '').toString();

                      return ItemCard(
                        itemId: doc.id,
                        itemData: itemData,
                        name:
                            itemData['name'] ?? itemData['title'] ?? 'No Name',
                        price: '₱${itemData['price'] ?? 0}',
                        imagePath: imagePath,
                        isOwner: itemData['ownerId'] == user?.uid,
                        isAvailable: itemData['isAvailable'] ?? true,
                        isGrid: true,
                        onEdit: () => setState(() {}),
                        onDelete: () => setState(() {}),
                      );
                    },
                  ),
                );
              }

              // Single Column List View Layout
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final itemData = doc.data() as Map<String, dynamic>;
                  final imageUrls =
                      itemData['imageUrls'] as List<dynamic>? ?? [];
                  final imagePath = imageUrls.isNotEmpty
                      ? imageUrls[0].toString()
                      : (itemData['imageUrl'] ?? '').toString();

                  return SizedBox(
                    height: 380,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ItemCard(
                        itemId: doc.id,
                        itemData: itemData,
                        name:
                            itemData['name'] ?? itemData['title'] ?? 'No Name',
                        price: '₱${itemData['price'] ?? 0}',
                        imagePath: imagePath,
                        isOwner: itemData['ownerId'] == user?.uid,
                        isAvailable: itemData['isAvailable'] ?? true,
                        isGrid: false,
                        onEdit: () => setState(() {}),
                        onDelete: () => setState(() {}),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 80), // Padding for FloatingActionButton
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, IconData icon) {
    final isSelected = _selectedMode == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMode = label;
            if (label == 'Nearby' && _selectedRadiusKm >= 100.0) {
              _selectedRadiusKm = 25.0; // Nearby defaults to 25 km radius
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFE8FA) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7B40B5)
                  : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF7B40B5) : Colors.grey[700],
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF7B40B5)
                      : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
