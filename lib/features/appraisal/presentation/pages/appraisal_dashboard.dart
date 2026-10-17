import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/appraisal/presentation/widgets/appraisal_form_dialog.dart';
import 'package:lendly/features/appraisal/domain/models/appraisal_model.dart';
import 'package:lendly/features/items/presentation/pages/item_detail_screen.dart';

class AppraisalDashboard extends StatefulWidget {
  const AppraisalDashboard({super.key});

  @override
  State<AppraisalDashboard> createState() => _AppraisalDashboardState();
}

class _AppraisalDashboardState extends State<AppraisalDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _filterType = 'all'; // 'all', 'needs_appraisal', 'requested', 'certified'

  final List<String> _categories = [
    'All',
    'Electronics',
    'Cameras',
    'Tools',
    'Outdoor',
    'Musical Instruments',
    'Vehicles',
    'Sports',
    'Home',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openAppraisalModal(BuildContext context, Map<String, dynamic> itemData, String itemId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppraisalFormDialog(itemData: itemData, itemId: itemId),
    );
    if (result == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Professional Appraisal Portal',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: uid.isNotEmpty
            ? FirebaseFirestore.instance.collection('users').doc(uid).get()
            : null,
        builder: (context, userSnapshot) {
          final userData = (userSnapshot.data?.data() as Map<String, dynamic>?) ?? {};
          final businessName = userData['businessName'] is String && (userData['businessName'] as String).isNotEmpty
              ? userData['businessName']
              : 'Certified Valuation Agency';
          final licenseNo = userData['licenseNumber'] is String && (userData['licenseNumber'] as String).isNotEmpty
              ? userData['licenseNumber']
              : 'APP-2026-VERIFIED';
          final specialization = userData['specialization'] ?? 'General Marketplace';

          return Column(
            children: [
              // Top Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A1A7E), Color(0xFF7B40B5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_outlined, color: Colors.amber, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                businessName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.shield, color: Colors.greenAccent, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'License #: $licenseNo',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'PRO APPRAISER',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildHeaderStat('SPECIALTY', specialization),
                        Container(width: 1, height: 26, color: Colors.white24),
                        _buildHeaderStat('STATUS', 'VERIFIED'),
                        Container(width: 1, height: 26, color: Colors.white24),
                        _buildHeaderStat('RATING SYSTEM', 'Function & Cosmetic (1-10)'),
                      ],
                    ),
                  ],
                ),
              ),

              // Search Bar & Filter Controls
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search items, owners, or keywords to appraise...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF7B40B5)),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Filter Status Chips (All, Needs Appraisal, Requested, Certified)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All Marketplace Items', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Needs Appraisal', 'needs_appraisal'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Owner Requested', 'requested'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Already Certified', 'certified'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Category Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(cat, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
                              selected: isSelected,
                              selectedColor: const Color(0xFF7B40B5),
                              backgroundColor: Colors.grey.shade100,
                              onSelected: (val) {
                                if (val) setState(() => _selectedCategory = cat);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab Bar
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF7B40B5),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF7B40B5),
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(text: 'Browse & Rate Items'),
                    Tab(text: 'My Certified Appraisals'),
                  ],
                ),
              ),

              // Tab Bar View
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBrowseAndRateTab(uid),
                    _buildCertifiedHistoryTab(uid),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _filterType == type;
    return InkWell(
      onTap: () => setState(() => _filterType = type),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7B40B5).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF7B40B5) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF7B40B5) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String title, String val) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBrowseAndRateTab(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
        }

        final allDocs = snapshot.data?.docs ?? [];
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isCertified = data['appraisalStatus'] == 'certified';
          final isRequested = data['appraisalRequested'] == true;
          final category = (data['category'] ?? '').toString();
          final title = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
          final owner = (data['ownerName'] ?? '').toString().toLowerCase();

          // Category filter
          if (_selectedCategory != 'All' && !category.toLowerCase().contains(_selectedCategory.toLowerCase())) {
            return false;
          }

          // Search query filter
          if (_searchQuery.isNotEmpty && !title.contains(_searchQuery) && !owner.contains(_searchQuery)) {
            return false;
          }

          // Status filter
          if (_filterType == 'needs_appraisal' && isCertified) return false;
          if (_filterType == 'requested' && !isRequested) return false;
          if (_filterType == 'certified' && !isCertified) return false;

          return true;
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off_rounded, size: 55, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  'No items found matching criteria',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try adjusting your search query or filters above.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final doc = filteredDocs[index];
            final itemData = doc.data() as Map<String, dynamic>;
            final title = itemData['name'] ?? itemData['title'] ?? 'Unnamed Item';
            final ownerName = itemData['ownerName'] ?? 'Lender';
            final price = '₱${itemData['price'] ?? 0}/day';
            final category = itemData['category'] ?? 'General';
            final isCertified = itemData['appraisalStatus'] == 'certified';
            final isRequested = itemData['appraisalRequested'] == true;

            final fnScore = itemData['functionScore'];
            final cosScore = itemData['cosmeticScore'];
            final condition = itemData['conditionGrade'] ?? itemData['condition'];

            List<String> imgs = [];
            if (itemData['imageUrls'] is List && (itemData['imageUrls'] as List).isNotEmpty) {
              imgs = List<String>.from(itemData['imageUrls']);
            } else if (itemData['imageUrl'] is String && (itemData['imageUrl'] as String).isNotEmpty) {
              imgs = [itemData['imageUrl']];
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: imgs.isNotEmpty
                              ? Image.network(
                                  imgs[0],
                                  width: 75,
                                  height: 75,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(width: 75, height: 75, color: Colors.grey[200]),
                                )
                              : Container(width: 75, height: 75, color: Colors.grey[200], child: const Icon(Icons.inventory_2)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCertified)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified, size: 10, color: Colors.green),
                                          SizedBox(width: 2),
                                          Text(
                                            'CERTIFIED',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isRequested)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'OWNER REQUESTED',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('Category: $category • Owner: $ownerName', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    price,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5), fontSize: 13),
                                  ),
                                  if (isCertified && condition != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppraisalModel.getConditionColor(condition.toString()).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        condition.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppraisalModel.getConditionColor(condition.toString()),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Appraisal Rating breakdown if already certified
                    if (isCertified && fnScore != null && cosScore != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Function: $fnScore/10', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5))),
                            Text('Cosmetic: $cosScore/10', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                            if (itemData['appraisalValue'] != null)
                              Text('Est. Value: ₱${itemData['appraisalValue']} (Private)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Action Buttons (Rate Item & View Item)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ItemDetailScreen(itemData: itemData, itemId: doc.id),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility_outlined, size: 15),
                            label: const Text('View Item', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade800,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openAppraisalModal(context, itemData, doc.id),
                            icon: const Icon(Icons.star_rate_rounded, size: 16),
                            label: Text(
                              isCertified ? 'Re-Appraise' : 'Rate & Appraise',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B40B5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCertifiedHistoryTab(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('certifiedByAppraiserId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_toggle_off, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('No Certified Appraisals Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Browse marketplace items and submit your Function & Cosmetic ratings!', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final itemData = doc.data() as Map<String, dynamic>;
            final title = itemData['name'] ?? itemData['title'] ?? 'Unnamed Item';
            final certId = itemData['appraisalCertificateId'] ?? 'CERT-UNKNOWN';
            final appValue = (itemData['appraisalValue'] as num?)?.toDouble() ?? 0.0;
            final condition = itemData['conditionGrade'] ?? 'Certified';
            final fnScore = itemData['functionScore'] ?? '-';
            final cosScore = itemData['cosmeticScore'] ?? '-';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFE8FA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified, color: Color(0xFF7B40B5)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('Certificate ID: $certId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₱${appValue.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF059669)),
                            ),
                            const Text('Estimated Value (Private)', style: TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Function: $fnScore/10', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7B40B5))),
                        Text('Cosmetic: $cosScore/10', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppraisalModel.getConditionColor(condition.toString()).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            condition.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppraisalModel.getConditionColor(condition.toString()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ItemDetailScreen(itemData: itemData, itemId: doc.id),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility_outlined, size: 14),
                            label: const Text('View Certificate & Item', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade800,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openAppraisalModal(context, itemData, doc.id),
                            icon: const Icon(Icons.edit_note, size: 16),
                            label: const Text('Edit Valuation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B40B5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
