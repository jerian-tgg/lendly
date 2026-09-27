import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lendly/features/appraisal/presentation/widgets/appraisal_form_dialog.dart';
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
          'Appraiser Portal',
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
              : 'Professional Valuation Agency';
          final licenseNo = userData['licenseNumber'] is String && (userData['licenseNumber'] as String).isNotEmpty
              ? userData['licenseNumber']
              : 'APP-2026-VERIFIED';
          final specialization = userData['specialization'] ?? 'General Marketplace Goods';

          return Column(
            children: [
              // Top Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5A2A94), Color(0xFF7B40B5)],
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
                          child: const Icon(Icons.verified_outlined, color: Colors.amber, size: 30),
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
                                  fontSize: 20,
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
                        Container(width: 1, height: 30, color: Colors.white24),
                        _buildHeaderStat('STATUS', 'ACTIVE VERIFIED'),
                        Container(width: 1, height: 30, color: Colors.white24),
                        _buildHeaderStat('RATING', '5.0 ⭐⭐⭐⭐⭐'),
                      ],
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search items or lenders for appraisal...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF7B40B5)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
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
                    Tab(text: 'Pending Requests'),
                    Tab(text: 'My Certified Appraisals'),
                  ],
                ),
              ),

              // Tab Bar View
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingRequestsTab(uid),
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

  Widget _buildHeaderStat(String title, String val) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPendingRequestsTab(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
        }

        final allDocs = snapshot.data?.docs ?? [];
        final pendingDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isCertified = data['appraisalStatus'] == 'certified';
          final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();

          if (isCertified) return false;
          if (_searchQuery.isNotEmpty && !name.contains(_searchQuery)) return false;
          return true;
        }).toList();

        if (pendingDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                const SizedBox(height: 12),
                const Text(
                  'No Pending Appraisal Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'All items currently in the marketplace are appraised!',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: pendingDocs.length,
          itemBuilder: (context, index) {
            final doc = pendingDocs[index];
            final itemData = doc.data() as Map<String, dynamic>;
            final title = itemData['name'] ?? itemData['title'] ?? 'Unnamed Item';
            final ownerName = itemData['ownerName'] ?? 'Lender';
            final price = '₱${itemData['price'] ?? 0}/day';
            final category = itemData['category'] ?? 'General';
            final isRequested = itemData['appraisalRequested'] == true;

            List<String> imgs = [];
            if (itemData['imageUrls'] is List && (itemData['imageUrls'] as List).isNotEmpty) {
              imgs = List<String>.from(itemData['imageUrls']);
            } else if (itemData['imageUrl'] is String && (itemData['imageUrl'] as String).isNotEmpty) {
              imgs = [itemData['imageUrl']];
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: imgs.isNotEmpty
                          ? Image.network(
                              imgs[0],
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(width: 70, height: 70, color: Colors.grey[200]),
                            )
                          : Container(width: 70, height: 70, color: Colors.grey[200], child: const Icon(Icons.inventory_2)),
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
                                ),
                              ),
                              if (isRequested)
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
                          Text('Listed Price: $price', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7B40B5), fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _openAppraisalModal(context, itemData, doc.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B40B5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Appraise', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                Text('Appraise pending items to issue certificates!', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFE8FA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified, color: Color(0xFF7B40B5)),
                ),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Certificate ID: $certId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                    Text('Condition: $condition', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${appValue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                    const Text('Appraised Value', style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(itemData: itemData, itemId: doc.id),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
