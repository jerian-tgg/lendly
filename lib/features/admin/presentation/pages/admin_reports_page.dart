import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lendly/core/services/report_service.dart';
import 'package:lendly/core/services/trust_score_service.dart';

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
        backgroundColor: const Color(0xFF98259A),
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
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ReportService().streamReportsByStatus(status),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF98259A)));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load $status reports:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        final docs = snap.data ?? [];
        if (docs.isEmpty) {
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
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
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

class _ReportCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ReportCard({
    required this.docId,
    required this.data,
    required this.onTap,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  Future<ReportedItemDetails?>? _itemDetailsFuture;

  @override
  void initState() {
    super.initState();
    _initItemFuture();
  }

  @override
  void didUpdateWidget(covariant _ReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docId != widget.docId ||
        oldWidget.data['targetId'] != widget.data['targetId'] ||
        oldWidget.data['status'] != widget.data['status']) {
      _initItemFuture();
    }
  }

  void _initItemFuture() {
    if (widget.data['targetType'] == 'item') {
      _itemDetailsFuture = ReportService().fetchItemDetailsForReport(widget.data);
    } else {
      _itemDetailsFuture = null;
    }
  }

  Color get _statusColor {
    switch (widget.data['status']) {
      case 'reviewed':
        return const Color(0xFF2ECC71);
      case 'dismissed':
        return Colors.grey;
      default:
        return const Color(0xFFE74C3C);
    }
  }

  IconData get _typeIcon => widget.data['targetType'] == 'user'
      ? Icons.person_outline
      : Icons.inventory_2_outlined;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '—';
    final moderationAction = data['moderationAction']?.toString();
    final severity =
        TrustScoreService.severityForReason(data['reason']?.toString());
    final severityColor = _severityColor(severity);
    final isItemReport = data['targetType'] == 'item';

    final snapshotMap = data['targetItemSnapshot'] is Map
        ? Map<String, dynamic>.from(data['targetItemSnapshot'] as Map)
        : null;
    final snapshotDetails = isItemReport
        ? ReportService.parseItemDetails(
            snapshotData: snapshotMap,
            fallbackTitle: data['targetName']?.toString(),
          )
        : null;

    return FutureBuilder<ReportedItemDetails?>(
      future: _itemDetailsFuture,
      builder: (context, itemSnap) {
        final itemDetails = itemSnap.data ?? snapshotDetails;
        final itemImages = itemDetails?.imageUrls ?? const <String>[];
        final primaryImage = itemImages.isNotEmpty ? itemImages.first : null;
        final title = (itemDetails != null && itemDetails.title.isNotEmpty)
            ? itemDetails.title
            : (data['targetName'] ?? 'Unknown').toString();

        final metaParts = <String>[];
        if (itemDetails?.price != null) {
          metaParts.add(
            '₱${itemDetails!.price!.toStringAsFixed(0)}/${itemDetails.pricePer}',
          );
        }
        if (itemDetails?.category != null) {
          metaParts.add(itemDetails!.category!);
        }
        if (itemDetails?.condition != null) {
          metaParts.add(itemDetails!.condition!);
        }
        final ownerName = itemDetails?.ownerName ??
            data['targetOwnerName']?.toString().trim();

        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item photo thumbnail or type icon
                    if (isItemReport && primaryImage != null)
                      Stack(
                        children: [
                          _ItemImageThumb(
                            url: primaryImage,
                            size: 62,
                            borderRadius: 10,
                          ),
                          if (itemImages.length > 1)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+${itemImages.length - 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      Container(
                        width: isItemReport ? 56 : 42,
                        height: isItemReport ? 56 : 42,
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_typeIcon, color: _statusColor, size: 22),
                      ),
                    const SizedBox(width: 12),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF1A1A2E)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (data['status'] as String? ?? '')
                                      .toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: _statusColor,
                                      letterSpacing: 0.5),
                                ),
                              ),
                            ],
                          ),
                          if (isItemReport && metaParts.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              metaParts.join(' • '),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF98259A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (isItemReport &&
                              ownerName != null &&
                              ownerName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Owner: $ownerName',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (isItemReport &&
                              itemDetails?.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              itemDetails!.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  data['reason'] ?? 'No reason selected',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF444444)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${severity.label} (-${severity.penaltyPoints})',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: severityColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (moderationAction != null &&
                              moderationAction.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              moderationAction,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: data['status'] == 'reviewed'
                                    ? const Color(0xFF98259A)
                                    : Colors.blueGrey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Icon(Icons.chevron_right,
                          color: Colors.black26, size: 18),
                    ),
                  ],
                ),

                // Extra item photos strip when listing has multiple images
                if (isItemReport && itemImages.length > 1) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: itemImages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, idx) => _ItemImageThumb(
                        url: itemImages[idx],
                        size: 46,
                        borderRadius: 8,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Reported by: ${data['reporterName'] ?? 'Unknown'}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black38),
                    ),
                    if (isItemReport &&
                        itemSnap.connectionState == ConnectionState.done &&
                        itemSnap.data?.exists == false) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Listing removed',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(date,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
  final _reportService = ReportService();

  bool _saving = false;
  bool _loadingContext = true;
  bool _removeListing = true;
  ReportModerationContext? _context;

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.data['adminNote'] ?? '';
    _loadModerationContext();
  }

  Future<void> _loadModerationContext() async {
    final ctx = await _reportService.fetchModerationContext(widget.data);
    if (!mounted) return;
    setState(() {
      _context = ctx;
      _loadingContext = false;
      if (ctx.targetType == 'item' && !ctx.listingExists) {
        _removeListing = false;
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _confirmValidReport() async {
    final isItem = (widget.data['targetType'] ?? 'item') == 'item';
    final ctx = _context;
    final canRemoveListing = isItem && (ctx?.listingExists ?? false);
    final willRemoveListing = canRemoveListing && _removeListing;
    final reportedUserName = ctx?.reportedUserName ??
        widget.data['targetOwnerName']?.toString() ??
        (isItem ? 'Listing Owner' : (widget.data['targetName']?.toString() ?? 'Reported User'));
    final hasReportedUser = ctx?.reportedUserId != null && ctx!.reportedUserId!.isNotEmpty;
    final severity = TrustScoreService.severityForReason(
      widget.data['reason']?.toString(),
    );
    final penaltyPts = severity.penaltyPoints;
    final currentScore = ctx?.currentTrustScore;
    final projectedScore = currentScore != null
        ? TrustScoreService.applyPenalty(
            currentScore,
            penaltyPoints: penaltyPts,
          )
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Color(0xFFE74C3C)),
            SizedBox(width: 8),
            Expanded(child: Text('Confirm Valid Report')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirming this report as valid will perform the following moderation actions:',
              style: TextStyle(fontSize: 13, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 12),
            if (isItem)
              _ConfirmBullet(
                icon: willRemoveListing
                    ? Icons.delete_forever_rounded
                    : Icons.inventory_2_outlined,
                color: willRemoveListing
                    ? const Color(0xFFE74C3C)
                    : Colors.blueGrey,
                text: willRemoveListing
                    ? 'Remove listing "${ctx?.listingTitle ?? widget.data['targetName'] ?? 'Listing'}" from marketplace'
                    : (canRemoveListing
                        ? 'Keep listing in marketplace'
                        : 'Listing already removed from marketplace'),
              ),
            if (hasReportedUser)
              _ConfirmBullet(
                icon: Icons.trending_down_rounded,
                color: _severityColor(severity),
                text: currentScore != null && projectedScore != null
                    ? 'Lower $reportedUserName\'s trust score by $penaltyPts pts (${severity.label} severity: $currentScore → $projectedScore)'
                    : 'Lower $reportedUserName\'s trust score by $penaltyPts pts (${severity.label} severity)',
              )
            else
              const _ConfirmBullet(
                icon: Icons.info_outline_rounded,
                color: Colors.blueGrey,
                text: 'Reported user profile unavailable (no trust score change)',
              ),
            const _ConfirmBullet(
              icon: Icons.check_circle_outline_rounded,
              color: Color(0xFF2ECC71),
              text: 'Mark report status as REVIEWED',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirm & Apply'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await _reportService.confirmValidReport(
        docId: widget.docId,
        adminNote: _noteController.text.trim(),
        removeListing: willRemoveListing,
        fallbackReportedUserId: ctx?.reportedUserId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final details = <String>['Report marked as REVIEWED'];
      if (result.listingRemoved) {
        details.add('listing removed');
      }
      if (result.trustScoreLowered &&
          result.previousTrustScore != null &&
          result.newTrustScore != null) {
        details.add(
            'trust score ${result.previousTrustScore} → ${result.newTrustScore}');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${details.join(' • ')}.'),
          backgroundColor: const Color(0xFF2ECC71),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply moderation: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _dismissReport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Dismiss Report?'),
        content: const Text(
          'Mark this report as invalid/dismissed? No listing will be removed and no trust score penalty will be applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Dismiss Report'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _reportService.dismissReport(
        docId: widget.docId,
        adminNote: _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report dismissed (no moderation action taken).'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to dismiss report: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _saveAdminNoteOnly() async {
    setState(() => _saving = true);
    try {
      await _reportService.updateReportStatus(
        docId: widget.docId,
        status: widget.data['status'] ?? 'reviewed',
        adminNote: _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin note saved.'),
          backgroundColor: Color(0xFF98259A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save note: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final mediaUrls = List<String>.from(data['mediaUrls'] ?? []);
    final isPending = data['status'] == 'pending';
    final isItemReport = (data['targetType'] ?? 'item') == 'item';
    const accent = Color(0xFF98259A);

    final ctx = _context;
    final hasReportedUser =
        ctx?.reportedUserId != null && ctx!.reportedUserId!.isNotEmpty;
    final severity = TrustScoreService.severityForReason(
      data['reason']?.toString(),
    );
    final penaltyPts = severity.penaltyPoints;
    final severityColor = _severityColor(severity);
    final currentScore = ctx?.currentTrustScore;
    final projectedScore = currentScore != null
        ? TrustScoreService.applyPenalty(
            currentScore,
            penaltyPoints: penaltyPts,
          )
        : null;

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
            const Text(
              'Report Detail',
              style: TextStyle(
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
            _DetailRow(label: 'Target ID', value: data['targetId'] ?? '—'),
            _DetailRow(label: 'Reported By', value: data['reporterName'] ?? '—'),
            _DetailRow(
                label: 'Reporter Email', value: data['reporterEmail'] ?? '—'),
            _DetailRow(label: 'Reason', value: data['reason'] ?? '—'),
            _DetailRow(
              label: 'Severity',
              value: '${severity.label} (-$penaltyPts pts)',
            ),
            _DetailRow(
                label: 'Status',
                value: (data['status'] ?? '—').toString().toUpperCase()),

            const SizedBox(height: 14),

            // Target & Reported User Context Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _loadingContext
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Loading listing & user status...',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reported Target Status',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isItemReport) ...[
                          Row(
                            children: [
                              Icon(
                                ctx?.listingExists == true
                                    ? Icons.storefront_rounded
                                    : Icons.delete_sweep_rounded,
                                size: 16,
                                color: ctx?.listingExists == true
                                    ? const Color(0xFF2ECC71)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ctx?.listingExists == true
                                      ? 'Listing is currently active in marketplace'
                                      : 'Listing has already been removed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ctx?.listingExists == true
                                        ? const Color(0xFF16A34A)
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (ctx?.itemDetails != null) ...[
                            const SizedBox(height: 10),
                            _ReportedItemPreviewBlock(
                              details: ctx!.itemDetails!,
                              onImageTap: (url) =>
                                  _viewMedia(context, url, false),
                            ),
                          ],
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 16, color: accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasReportedUser
                                    ? '${isItemReport ? 'Listing Owner' : 'User'}: ${ctx.reportedUserName ?? ctx.reportedUserEmail ?? ctx.reportedUserId}'
                                    : 'Reported user profile not found',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF333333),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (currentScore != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Trust: $currentScore/100',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (ctx != null && ctx.existingViolations > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Prior confirmed violations: ${ctx.existingViolations}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB91C1C),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),

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
                            : Image.network(
                                url,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 110,
                                  height: 110,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                ),
                              ),
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
                  borderSide: const BorderSide(color: accent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),

            // Moderation actions (for pending reports)
            if (isPending) ...[
              const SizedBox(height: 20),
              const Text(
                'Moderation Actions (if report is valid)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 10),
              if (isItemReport)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (ctx?.listingExists == true && _removeListing)
                          ? const Color(0xFFE74C3C).withValues(alpha: 0.4)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: ctx?.listingExists == true ? _removeListing : false,
                    onChanged: (_saving || ctx?.listingExists != true)
                        ? null
                        : (val) =>
                            setState(() => _removeListing = val ?? true),
                    activeColor: const Color(0xFFE74C3C),
                    title: const Text(
                      'Remove listing from marketplace',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _loadingContext
                          ? 'Checking listing status...'
                          : (ctx?.listingExists == true
                              ? 'Deletes this item listing immediately.'
                              : 'This listing has already been removed.'),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: severityColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.trending_down_rounded,
                      color: severityColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasReportedUser
                            ? (currentScore != null && projectedScore != null
                                ? '${severity.label} severity (${data['reason'] ?? 'Violation'}): confirming valid automatically lowers trust score by $penaltyPts pts ($currentScore → $projectedScore).'
                                : '${severity.label} severity (${data['reason'] ?? 'Violation'}): confirming valid automatically lowers trust score by $penaltyPts pts.')
                            : 'Reported user could not be resolved; confirming valid will mark the report as reviewed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: severityColor,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _dismissReport,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Dismiss'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (_saving || _loadingContext)
                          ? null
                          : _confirmValidReport,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.gavel_rounded,
                              size: 16, color: Colors.white),
                      label: Text(
                        _saving
                            ? 'Applying...'
                            : (isItemReport &&
                                    ctx?.listingExists == true &&
                                    _removeListing)
                                ? 'Confirm & Remove'
                                : 'Confirm Valid',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE74C3C),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              if (data['moderationAction'] != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Moderation Outcome',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data['moderationAction'].toString(),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent),
                      ),
                      if (data['previousTrustScore'] != null &&
                          data['newTrustScore'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Trust Score adjusted: ${data['previousTrustScore']} → ${data['newTrustScore']}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAdminNoteOnly,
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
                      child: Text(
                          'Video preview not available in-app.\nUse URL to view.',
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

class _ItemImageThumb extends StatelessWidget {
  final String url;
  final double size;
  final double borderRadius;

  const _ItemImageThumb({
    required this.url,
    required this.size,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image_outlined,
              color: Colors.grey, size: 20),
        ),
      ),
    );
  }
}

class _ReportedItemPreviewBlock extends StatelessWidget {
  final ReportedItemDetails details;
  final void Function(String url) onImageTap;

  const _ReportedItemPreviewBlock({
    required this.details,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];
    if (details.price != null) {
      chips.add('₱${details.price!.toStringAsFixed(0)}/${details.pricePer}');
    }
    if (details.category != null) chips.add(details.category!);
    if (details.condition != null) chips.add(details.condition!);
    if (details.location != null) chips.add(details.location!);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.imageUrls.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: details.imageUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = details.imageUrls[i];
                  return GestureDetector(
                    onTap: () => onImageTap(url),
                    child: _ItemImageThumb(
                      url: url,
                      size: 76,
                      borderRadius: 8,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            details.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              chips.join(' • '),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF98259A),
              ),
            ),
          ],
          if (details.description != null) ...[
            const SizedBox(height: 4),
            Text(
              details.description!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _severityColor(ReportSeverity severity) {
  switch (severity) {
    case ReportSeverity.critical:
      return const Color(0xFFB91C1C);
    case ReportSeverity.high:
      return const Color(0xFFEA580C);
    case ReportSeverity.moderate:
      return const Color(0xFFD97706);
    case ReportSeverity.low:
      return const Color(0xFF0284C7);
  }
}

class _ConfirmBullet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _ConfirmBullet({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }
}

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
