import 'package:flutter/material.dart';
import 'package:lendly/core/services/trust_score_service.dart';

/// A card widget displaying a user's Trust Score and its component breakdown.
/// Follows Orchid design system with clean card styling, progress gauges,
/// tier badges, and explanatory dialogs.
class TrustScoreCard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final bool isSelf;

  const TrustScoreCard({
    super.key,
    required this.userData,
    required this.userId,
    this.isSelf = false,
  });

  @override
  State<TrustScoreCard> createState() => _TrustScoreCardState();
}

class _TrustScoreCardState extends State<TrustScoreCard> {
  bool _isExpanded = false;
  bool _isRecalculating = false;

  @override
  Widget build(BuildContext context) {
    final stats = (widget.userData['trustScoreStats'] as Map?)?.cast<String, dynamic>();

    // User's raw ratings for fallback if stats not yet generated
    final actualRating = (widget.userData['rating'] as num?)?.toDouble() ?? 0.0;
    final totalRatings = (widget.userData['reviewCount'] as num?)?.toInt() ?? 0;

    // Retrieve or calculate fallback trust score
    int displayScore;
    if (widget.userData['trustScore'] is num) {
      displayScore = (widget.userData['trustScore'] as num).toInt();
    } else {
      // Fallback dynamic calculation if not yet synchronized
      displayScore = TrustScoreService.computeTrustScore(
        totalRatings: totalRatings,
        averageRating: actualRating,
        completedTransactions: stats?['completedTransactions'] ?? 0,
        eligibleTransactions: stats?['totalEligibleTransactions'] ?? 0,
      );
    }

    final tier = _getScoreTier(displayScore);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tier.color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: tier.color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header banner & main score row
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and info icon row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: tier.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.verified_user_rounded, color: tier.color, size: 20),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Community Trust Score',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded, size: 20, color: Colors.grey),
                          tooltip: 'How Trust Score Works',
                          onPressed: () => _showExplanationDialog(context),
                        ),
                        if (widget.isSelf)
                          IconButton(
                            icon: _isRecalculating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF7B40B5)),
                            tooltip: 'Recalculate Score',
                            onPressed: _isRecalculating ? null : _handleRecalculate,
                          ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Score dial & tier summary
                Row(
                  children: [
                    // Circular Dial
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 84,
                            height: 84,
                            child: CircularProgressIndicator(
                              value: (displayScore / 100.0).clamp(0.0, 1.0),
                              strokeWidth: 8,
                              backgroundColor: tier.color.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(tier.color),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$displayScore',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: tier.color,
                                  height: 1.0,
                                ),
                              ),
                              const Text(
                                '/ 100',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Tier Title & description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: tier.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(tier.icon, color: tier.color, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  tier.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: tier.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tier.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: Colors.grey.shade200),

          // Toggle Breakdown Button
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isExpanded ? Icons.tune_rounded : Icons.analytics_outlined,
                        size: 16,
                        color: const Color(0xFF7B40B5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isExpanded ? 'Hide Score Breakdown' : 'View Score Breakdown',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B40B5),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF7B40B5),
                  ),
                ],
              ),
            ),
          ),

          // Detailed Pillar Breakdown
          if (_isExpanded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              color: const Color(0xFFF8FAFC),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // 1. Bayesian Rating Factor (60%)
                  _buildPillarTile(
                    title: 'Ratings & Reviews',
                    weightLabel: '60% weight',
                    valueLabel: stats != null && stats['bayesianRating'] != null
                        ? '${(stats['bayesianRating'] as num).toStringAsFixed(1)} / 5.0'
                        : '${TrustScoreService.bayesianRating(totalRatings: totalRatings, averageRating: actualRating).toStringAsFixed(1)} / 5.0',
                    progressValue: (TrustScoreService.bayesianRating(
                              totalRatings: totalRatings,
                              averageRating: actualRating,
                            ) /
                            5.0)
                        .clamp(0.0, 1.0),
                    subtitle: totalRatings > 0
                        ? '$totalRatings valid reviews received (Raw avg: ${actualRating.toStringAsFixed(1)} ★)'
                        : 'No reviews yet. Bayesian prior applied for fairness.',
                    icon: Icons.star_rounded,
                    color: const Color(0xFFF59E0B),
                  ),

                  const SizedBox(height: 12),

                  // 2. Transaction Reliability Factor (30%)
                  _buildPillarTile(
                    title: 'Transaction Reliability',
                    weightLabel: '30% weight',
                    valueLabel: stats != null && stats['reliabilityPercentage'] != null
                        ? '${(stats['reliabilityPercentage'] as num).toInt()}%'
                        : '100%',
                    progressValue: stats != null && stats['reliabilityPercentage'] != null
                        ? ((stats['reliabilityPercentage'] as num).toDouble() / 100.0).clamp(0.0, 1.0)
                        : 1.0,
                    subtitle: stats != null && stats['completedTransactions'] != null
                        ? '${stats['completedTransactions']} completed of ${stats['totalEligibleTransactions'] ?? stats['completedTransactions']} eligible transactions'
                        : '100% baseline completion for reliable handoffs and returns',
                    icon: Icons.task_alt_rounded,
                    color: const Color(0xFF10B981),
                  ),

                  const SizedBox(height: 12),

                  // 3. Platform Experience Milestone (10%)
                  _buildPillarTile(
                    title: 'Platform Experience',
                    weightLabel: '10% weight',
                    valueLabel: stats != null && stats['completedTransactions'] != null
                        ? '${stats['completedTransactions']} / 20'
                        : '0 / 20',
                    progressValue: stats != null && stats['completedTransactions'] != null
                        ? ((stats['completedTransactions'] as num).toDouble() / 20.0).clamp(0.0, 1.0)
                        : 0.0,
                    subtitle: 'Milestone rewards members who complete up to 20 rentals',
                    icon: Icons.military_tech_rounded,
                    color: const Color(0xFF6366F1),
                  ),

                  const SizedBox(height: 12),

                  // Tamper-proof security disclaimer
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Verified and updated by Orchid Cloud Functions. Scores cannot be manually edited.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPillarTile({
    required String title,
    required String weightLabel,
    required String valueLabel,
    required double progressValue,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      weightLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  void _showExplanationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF7B40B5)),
            SizedBox(width: 8),
            Text('About Trust Score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Orchid Trust Score evaluates lender and borrower reliability fairly using a weighted reputation algorithm:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              _ExplainerBullet(
                title: 'Bayesian Ratings (60%)',
                body: 'Balances real user reviews with a prior average (4.0 baseline) so new users aren\'t punished or artificially inflated by single ratings.',
              ),
              SizedBox(height: 8),
              _ExplainerBullet(
                title: 'Transaction Reliability (30%)',
                body: 'Measures completion of rental handoffs and return confirmations. Unjustified lender denials negatively impact reliability.',
              ),
              SizedBox(height: 8),
              _ExplainerBullet(
                title: 'Community Experience (10%)',
                body: 'Rewards long-term members who regularly borrow and lend within Orchid.',
              ),
              SizedBox(height: 12),
              Text(
                'All computations are performed securely by Orchid backend services.',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Color(0xFF7B40B5), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRecalculate() async {
    setState(() => _isRecalculating = true);
    try {
      final res = await TrustScoreService().recalculateTrustScore(userId: widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res != null
                  ? 'Trust Score updated: ${res['trustScore']}/100'
                  : 'Trust score refreshed.',
            ),
            backgroundColor: const Color(0xFF7B40B5),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh score: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRecalculating = false);
      }
    }
  }

  _TrustScoreTier _getScoreTier(int score) {
    if (score >= 90) {
      return _TrustScoreTier(
        label: 'Excellent Standing',
        description: 'Highly dependable community member with consistent reviews and completed transactions.',
        color: const Color(0xFF10B981),
        icon: Icons.workspace_premium_rounded,
      );
    } else if (score >= 75) {
      return _TrustScoreTier(
        label: 'Very Good Standing',
        description: 'Trusted peer with solid transaction history and reliable communication.',
        color: const Color(0xFF7B40B5),
        icon: Icons.verified_rounded,
      );
    } else if (score >= 60) {
      return _TrustScoreTier(
        label: 'Good Standing',
        description: 'Active member with positive engagement across community listings.',
        color: const Color(0xFF0284C7),
        icon: Icons.thumb_up_alt_rounded,
      );
    } else if (score >= 40) {
      return _TrustScoreTier(
        label: 'Fair Standing',
        description: 'Building reputation through initial transactions and feedback.',
        color: const Color(0xFFD97706),
        icon: Icons.trending_up_rounded,
      );
    } else {
      return _TrustScoreTier(
        label: 'Developing Member',
        description: 'New to the Orchid community. Complete transactions to grow your reputation.',
        color: const Color(0xFF64748B),
        icon: Icons.person_outline_rounded,
      );
    }
  }
}

class _TrustScoreTier {
  final String label;
  final String description;
  final Color color;
  final IconData icon;

  _TrustScoreTier({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
  });
}

class _ExplainerBullet extends StatelessWidget {
  final String title;
  final String body;

  const _ExplainerBullet({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(Icons.circle, size: 6, color: Color(0xFF7B40B5)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
