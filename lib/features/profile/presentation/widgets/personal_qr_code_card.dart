import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PersonalQrCodeCard extends StatelessWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final bool isSelf;

  const PersonalQrCodeCard({
    super.key,
    required this.userId,
    required this.userName,
    this.userEmail = '',
    this.isSelf = true,
  });

  String get _qrPayload {
    final payload = {
      'type': 'lendly_user_qr',
      'userId': userId,
      'name': userName,
      'email': userEmail,
      'version': 1,
    };
    return jsonEncode(payload);
  }

  void _showExpandedQrDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Color(0xFF7B40B5),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSelf ? 'My Personal QR Code' : '$userName\'s QR Code',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const Text(
                              'Lendly Identity & Transactions',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: QrImageView(
                    data: _qrPayload,
                    version: QrVersions.auto,
                    size: 220.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF7B40B5),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1E293B),
                    ),
                    errorStateBuilder: (cxt, err) {
                      return const Center(
                        child: Text(
                          'Error loading QR code',
                          style: TextStyle(color: Colors.red),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  userName.isNotEmpty ? userName : 'Lendly User',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: userId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User ID copied to clipboard!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID: ${userId.length > 16 ? "${userId.substring(0, 16)}..." : userId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 13, color: Color(0xFF7B40B5)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Color(0xFF7B40B5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isSelf
                              ? 'Show this to the borrower/lender to verify identity and record handovers.'
                              : 'Scan this code to confirm transactions and verify user details.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5A2A94),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B40B5).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF7B40B5).withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.qr_code_2_rounded,
                  color: Color(0xFF7B40B5),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSelf ? 'My Personal QR Code' : 'User Personal QR Code',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A2A94),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B40B5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: Colors.white, size: 12),
                      SizedBox(width: 2),
                      Text(
                        'Ready',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Card Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // QR Preview Thumbnail
                GestureDetector(
                  onTap: () => _showExpandedQrDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: _qrPayload,
                          version: QrVersions.auto,
                          size: 90.0,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF7B40B5),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF7B40B5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Description & Actions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSelf
                            ? 'Your unique transaction & handover identity code.'
                            : 'Scan to verify this user during handovers.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[800],
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Copy ID button
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: userId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User ID copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ID: ${userId.length > 10 ? "${userId.substring(0, 10)}..." : userId}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.copy, size: 12, color: Color(0xFF7B40B5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Enlarge Button
                      OutlinedButton.icon(
                        onPressed: () => _showExpandedQrDialog(context),
                        icon: const Icon(Icons.fullscreen, size: 16),
                        label: const Text(
                          'View Full QR',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7B40B5),
                          side: const BorderSide(color: Color(0xFF7B40B5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
