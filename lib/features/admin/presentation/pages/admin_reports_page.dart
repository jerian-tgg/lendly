import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['Pending', 'Reviewed', 'Dismissed'];
  static const _statuses = ['pending', 'reviewed', 'dismissed'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF007799),
        title: const Text('Reports',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _statuses
            .map((status) => _ReportList(status: status))
            .toList(),
      ),
    );
  }
}

// ── Report List per tab ───────────────────────────────────────────

class _ReportList extends StatelessWidget {
  final String status;
  const _ReportList({required this.status});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF007799)));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No $status reports',
                  style: const TextStyle(
                      color: Colors.black38, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: snap.data!.docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = snap.data!.docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _ReportCard(
              docId: doc.id,
              data: data,
              onTap: () => _openDetail(context, doc.id, data),
            );
          },
        );
      },
    );
  }

  void _openDetail(
      BuildContext context, String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(docId: docId, data: data),
    );
  }
}

// ── Report Card ───────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ReportCard({
    required this.docId,
    required this.data,
    required this.onTap,
  });

  Color get _statusColor {
    switch (data['status']) {
      case 'reviewed':
        return const Color(0xFF2ECC71);
      case 'dismissed':
        return Colors.grey;
      default:
        return const Color(0xFFE74C3C);
    }
  }

  IconData get _typeIcon => data['targetType'] == 'user'
      ? Icons.person_outline
      : Icons.inventory_2_outlined;

  @override
  Widget build(BuildContext context) {
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '—';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon, color: _statusColor, size: 22),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['targetName'] ?? 'Unknown',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1A1A2E)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (data['status'] as String? ?? '').toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: _statusColor,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['reason'] ?? 'No reason selected',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF555555)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'By: ${data['reporterName'] ?? 'Unknown'}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38),
                      ),
                      const Spacer(),
                      Text(date,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Report Detail Sheet ───────────────────────────────────────────

class _ReportDetailSheet extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _ReportDetailSheet({required this.docId, required this.data});

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.data['adminNote'] ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.docId)
        .update({
      'status': status,
      'adminNote': _noteController.text.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final mediaUrls = List<String>.from(data['mediaUrls'] ?? []);
    final isPending = data['status'] == 'pending';
    final accent = const Color(0xFF007799);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Title
            Text(
              'Report Detail',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 4),
            Text('ID: ${widget.docId}',
                style: const TextStyle(fontSize: 10, color: Colors.black38)),

            const SizedBox(height: 20),

            // Target info
            _DetailRow(label: 'Type', value: data['targetType'] ?? '—'),
            _DetailRow(label: 'Target', value: data['targetName'] ?? '—'),
            _DetailRow(label: 'Reported By', value: data['reporterName'] ?? '—'),
            _DetailRow(label: 'Reporter Email', value: data['reporterEmail'] ?? '—'),
            _DetailRow(label: 'Reason', value: data['reason'] ?? '—'),
            _DetailRow(label: 'Status', value: (data['status'] ?? '—').toUpperCase()),

            const Divider(height: 28),

            // Explanation
            const Text('Explanation',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                data['explanation']?.toString().isNotEmpty == true
                    ? data['explanation']
                    : 'No explanation provided.',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF333333), height: 1.5),
              ),
            ),

            // Media
            if (mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Evidence',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 10),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaUrls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    final url = mediaUrls[i];
                    final isVideo = url.contains('.mp4') ||
                        url.contains('.mov') ||
                        url.contains('video');
                    return GestureDetector(
                      onTap: () => _viewMedia(ctx, url, isVideo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: isVideo
                            ? Container(
                                width: 110,
                                height: 110,
                                color: Colors.black12,
                                child: const Center(
                                    child: Icon(Icons.play_circle_outline,
                                        size: 40, color: Colors.grey)),
                              )
                            : Image.network(url,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            ],

            const Divider(height: 28),

            // Admin note
            const Text('Admin Note',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add an internal note about this report...',
                hintStyle:
                    const TextStyle(color: Colors.black38, fontSize: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),

            // Action buttons (only for pending)
            if (isPending) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _saving ? null : () => _updateStatus('dismissed'),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Dismiss'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _saving ? null : () => _updateStatus('reviewed'),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_rounded,
                              size: 16, color: Colors.white),
                      label: Text(_saving ? 'Saving...' : 'Mark Reviewed',
                          style: const TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2ECC71),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Already actioned — just allow note save
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _updateStatus(data['status']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Save Note'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewMedia(BuildContext context, String url, bool isVideo) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: isVideo
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Video preview not available in-app.\nUse URL to view.',
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center),
                    )
                  : InteractiveViewer(child: Image.network(url)),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }
}
