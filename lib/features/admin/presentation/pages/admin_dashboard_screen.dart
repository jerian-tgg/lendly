import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lendly/features/business/data/repositories/business_application_repository.dart';
import 'package:lendly/features/business/domain/entities/business_application.dart';
import 'package:lendly/features/admin/presentation/widgets/document_viewer_dialog.dart';
import 'package:lendly/features/profile/presentation/pages/profile_page.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final BusinessApplicationRepository _repository = BusinessApplicationRepository();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showApproveDialog(BuildContext context, BusinessApplication application) {
    final notesController = TextEditingController(text: 'BIR permits and registration papers verified.');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Accept & Verify Business',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to approve "${application.businessName}"?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Applicant: ${application.applicantName} (${application.userEmail})\nTIN / License: ${application.licenseNumber}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This user will receive full verified appraiser & business badges across Lendly.',
                      style: TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Verification Notes (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final currentAdminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

              try {
                await _repository.approveApplication(
                  applicationId: application.id,
                  userId: application.userId,
                  adminId: currentAdminUid,
                  businessName: application.businessName,
                  licenseNumber: application.licenseNumber,
                  specialization: application.specialization,
                  adminNotes: notesController.text.trim(),
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Approved "${application.businessName}" successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to approve: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('Confirm Accept', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, BusinessApplication application) {
    final reasonController = TextEditingController();
    String selectedReasonChip = 'Blurry / Unreadable BIR Permit';

    final presetReasons = [
      'Blurry / Unreadable BIR Permit',
      'Missing BIR 2303 / Permit details',
      'Name on permit does not match applicant',
      'Expired business registration document',
      'Invalid TIN / License Number',
      'Incomplete registration requirements',
    ];

    reasonController.text = selectedReasonChip;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.cancel, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reject Verification Request',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reject application for "${application.businessName}"?',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Please select or enter a rejection reason so the applicant knows what to correct:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetReasons.map((chipText) {
                    final isSelected = selectedReasonChip == chipText;
                    return ChoiceChip(
                      label: Text(chipText, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
                      selected: isSelected,
                      selectedColor: Colors.redAccent,
                      backgroundColor: Colors.grey[200],
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() {
                            selectedReasonChip = chipText;
                            reasonController.text = chipText;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Rejection Reason / Notes to Applicant *',
                    hintText: 'Describe what needs to be fixed...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please specify a reason for rejection')),
                  );
                  return;
                }

                Navigator.pop(dialogCtx);
                final currentAdminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

                try {
                  await _repository.rejectApplication(
                    applicationId: application.id,
                    userId: application.userId,
                    adminId: currentAdminUid,
                    reason: reason,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Application for "${application.businessName}" rejected.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to reject: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('Confirm Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Appraiser Applications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF007799),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<BusinessApplication>>(
        stream: _repository.streamAllApplications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF7B40B5)));
          }

          final allApplications = snapshot.data ?? [];
          final pendingApps = allApplications.where((a) => a.isPending).toList();
          final approvedApps = allApplications.where((a) => a.isApproved).toList();
          final rejectedApps = allApplications.where((a) => a.isRejected).toList();

          return Column(
            children: [
              // Statistics Overview Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                color: Colors.white,
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildStatBox(
                          title: 'Pending',
                          count: pendingApps.length,
                          color: Colors.amber.shade800,
                          icon: Icons.pending_actions,
                        ),
                        const SizedBox(width: 10),
                        _buildStatBox(
                          title: 'Approved',
                          count: approvedApps.length,
                          color: Colors.green.shade700,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(width: 10),
                        _buildStatBox(
                          title: 'Rejected',
                          count: rejectedApps.length,
                          color: Colors.redAccent,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(width: 10),
                        _buildStatBox(
                          title: 'Total',
                          count: allApplications.length,
                          color: const Color(0xFF7B40B5),
                          icon: Icons.receipt_long,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by business name, TIN, email, or spec...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim().toLowerCase());
                      },
                    ),
                  ],
                ),
              ),

              // Filter Tabs
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF7B40B5),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF7B40B5),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Pending'),
                          if (pendingApps.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${pendingApps.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(text: 'Approved (${approvedApps.length})'),
                    Tab(text: 'Rejected (${rejectedApps.length})'),
                    Tab(text: 'All (${allApplications.length})'),
                  ],
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildApplicationsList(pendingApps),
                    _buildApplicationsList(approvedApps),
                    _buildApplicationsList(rejectedApps),
                    _buildApplicationsList(allApplications),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationsList(List<BusinessApplication> applications) {
    var filtered = applications;
    if (_searchQuery.isNotEmpty) {
      filtered = applications.where((app) {
        final bName = app.businessName.toLowerCase();
        final aName = app.applicantName.toLowerCase();
        final email = app.userEmail.toLowerCase();
        final lic = app.licenseNumber.toLowerCase();
        final spec = app.specialization.toLowerCase();
        return bName.contains(_searchQuery) ||
            aName.contains(_searchQuery) ||
            email.contains(_searchQuery) ||
            lic.contains(_searchQuery) ||
            spec.contains(_searchQuery);
      }).toList();
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No applications match "$_searchQuery"'
                  : 'No applications found in this category',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final app = filtered[index];
        return _buildApplicationCard(app);
      },
    );
  }

  Widget _buildApplicationCard(BusinessApplication app) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (app.isApproved) {
      statusColor = Colors.green;
      statusLabel = 'Approved / Verified';
      statusIcon = Icons.verified;
    } else if (app.isRejected) {
      statusColor = Colors.redAccent;
      statusLabel = 'Rejected';
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.amber.shade800;
      statusLabel = 'Pending Review';
      statusIcon = Icons.hourglass_top;
    }

    final dateFormatted = DateFormat('MMM dd, yyyy • hh:mm a').format(app.submittedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Business Name & Status Pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFEFE8FA),
                  radius: 24,
                  child: const Icon(Icons.business, color: Color(0xFF7B40B5), size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.businessName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Applicant: ${app.applicantName}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                      ),
                      Text(
                        app.userEmail,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Details Grid
            _buildInfoRow('TIN / License No:', app.licenseNumber, isBold: true),
            const SizedBox(height: 6),
            _buildInfoRow('Document Type:', app.permitType),
            const SizedBox(height: 6),
            _buildInfoRow('Specialization:', app.specialization),
            const SizedBox(height: 6),
            _buildInfoRow('Contact Phone:', app.phone.isNotEmpty ? app.phone : 'Not provided'),
            const SizedBox(height: 6),
            _buildInfoRow('Business Address:', app.address.isNotEmpty ? app.address : 'Not provided'),
            const SizedBox(height: 6),
            _buildInfoRow('Submitted At:', dateFormatted),

            if (app.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Applicant Note: "${app.notes}"',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[800]),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Attached Documents / BIR Permits Section
            Row(
              children: [
                const Icon(Icons.photo_library_outlined, color: Color(0xFF7B40B5), size: 18),
                const SizedBox(width: 6),
                Text(
                  'Attached BIR & Registration Papers (${app.documentUrls.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const Spacer(),
                const Text(
                  '(Tap photo to zoom in)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (app.documentUrls.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '⚠️ No document photos attached by applicant.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ] else ...[
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: app.documentUrls.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, docIdx) {
                    final imgUrl = app.documentUrls[docIdx];
                    return GestureDetector(
                      onTap: () {
                        DocumentViewerDialog.show(
                          context,
                          imageUrls: app.documentUrls,
                          initialIndex: docIdx,
                          title: '${app.businessName} - Document #${docIdx + 1}',
                          subtitle: app.permitType,
                        );
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF7B40B5), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.network(
                                imgUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                },
                                errorBuilder: (_, _, _) => Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#${docIdx + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            // Rejection reason banner if rejected
            if (app.isRejected && app.rejectionReason != null && app.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rejection Reason:',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            app.rejectionReason!,
                            style: const TextStyle(color: Colors.black87, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Approval notes if approved
            if (app.isApproved && app.adminNotes != null && app.adminNotes!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin Note: ${app.adminNotes!}',
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons: Accept / Reject / View Profile
            Row(
              children: [
                // View Applicant Profile Button
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfilePage(userId: app.userId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('View Profile', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7B40B5),
                    side: const BorderSide(color: Color(0xFF7B40B5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),

                // Reject Button
                if (!app.isRejected) ...[
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context, app),
                    icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                    label: const Text('Reject', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Accept Button
                if (!app.isApproved) ...[
                  ElevatedButton.icon(
                    onPressed: () => _showApproveDialog(context, app),
                    icon: const Icon(Icons.check, color: Colors.white, size: 16),
                    label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.black87 : Colors.grey[900],
            ),
          ),
        ),
      ],
    );
  }
}
