import 'package:flutter/material.dart';
import 'package:lendly/core/services/review_service.dart';

class ReviewDialog extends StatefulWidget {
  final String revieweeId;
  final String targetName;
  final String? itemId;
  final String? itemTitle;

  const ReviewDialog({
    super.key,
    required this.revieweeId,
    required this.targetName,
    this.itemId,
    this.itemTitle,
  });

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _commentController = TextEditingController();
  double _selectedRating = 5.0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _getRatingLabel(double rating) {
    if (rating >= 5.0) return '⭐⭐⭐⭐⭐ Outstanding (5/5)';
    if (rating >= 4.0) return '⭐⭐⭐⭐ Very Good (4/5)';
    if (rating >= 3.0) return '⭐⭐⭐ Good / Average (3/5)';
    if (rating >= 2.0) return '⭐⭐ Fair / Minor Issues (2/5)';
    return '⭐ Poor / Disappointed (1/5)';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await ReviewService().submitReview(
        revieweeId: widget.revieweeId,
        itemId: widget.itemId,
        itemTitle: widget.itemTitle,
        rating: _selectedRating,
        comment: _commentController.text.trim(),
        reviewType: widget.itemId != null ? 'item' : 'user',
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Thank you! Your ${_selectedRating.toInt()}-star review has been posted and ratings updated.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF7B40B5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isItemReview = widget.itemId != null && widget.itemId!.isNotEmpty;
    final subject = isItemReview ? (widget.itemTitle ?? 'Item') : widget.targetName;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isItemReview ? 'Rate & Review Item' : 'Rate & Review Lender',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87),
                          ),
                          Text(
                            'Sharing feedback for "$subject"',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Interactive Star Rating Selector
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Tap stars to select rating',
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final starValue = index + 1.0;
                          final isFilled = starValue <= _selectedRating;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedRating = starValue);
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Icon(
                                isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 38,
                                color: isFilled ? Colors.amber[700] : Colors.grey.shade400,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Text(
                          _getRatingLabel(_selectedRating),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Review Comment Input
                const Text(
                  'Write your review',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _commentController,
                  maxLines: 4,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a short review comment.';
                    }
                    if (val.trim().length < 5) {
                      return 'Review comment must be at least 5 characters.';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: isItemReview
                        ? 'Describe condition, ease of use, and overall experience with this item...'
                        : 'Describe communication, punctuality, and overall lending experience...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF7B40B5)),
                    const SizedBox(width: 4),
                    Text(
                      'Your review helps update this ${isItemReview ? 'item' : 'lender'}\'s rating in Firebase.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isSubmitting ? 'Posting Review...' : 'Submit Review & Rating',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B40B5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
