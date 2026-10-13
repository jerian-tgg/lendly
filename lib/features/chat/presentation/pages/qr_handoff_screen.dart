// qr_handoff_screen.dart
//
// Shown when both parties are physically present to confirm:
//   • Handoff  (borrower receives item from lender)
//   • Return   (lender receives item back from borrower)
//
// Flow:
//   1. User sees their own QR code (encodes: convoId|action|userId)
//   2. User taps "Scan Partner's QR" → camera opens
//   3. Scanner reads partner QR → validates convoId + action match
//   4. On success → Firestore updated → screen pops with result

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// [action] must be one of: 'handoff' | 'return'
class QrHandoffScreen extends StatefulWidget {
  final String convoId;
  final String currentUserId;
  final String currentUserName;
  final String itemName;
  final String action; // 'handoff' or 'return'

  const QrHandoffScreen({
    super.key,
    required this.convoId,
    required this.currentUserId,
    required this.currentUserName,
    required this.itemName,
    required this.action,
  });

  @override
  State<QrHandoffScreen> createState() => _QrHandoffScreenState();
}

class _QrHandoffScreenState extends State<QrHandoffScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _processing = false;
  String? _errorMessage;
  bool _confirmed = false;

  /// The QR data this user presents to their partner
  String get _myQrData => jsonEncode({
        'convoId': widget.convoId,
        'action': widget.action,
        'userId': widget.currentUserId,
        'userName': widget.currentUserName,
      });

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isHandoff() => widget.action == 'handoff';

  Color get _accentColor =>
      _isHandoff() ? const Color(0xFF3498DB) : const Color(0xFF7B40B5);

  String get _title =>
      _isHandoff() ? 'Item Handoff' : 'Item Return';

  String get _description => _isHandoff()
      ? 'The borrower scans the lender\'s QR — or the lender scans the borrower\'s — to confirm the item has changed hands.'
      : 'Both parties scan to confirm the item has been returned and the transaction is complete.';

  Future<void> _onQrDetected(String rawValue) async {
    if (_processing || _confirmed) return;

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      final data = jsonDecode(rawValue) as Map<String, dynamic>;

      // Validate: must match same conversation and action
      if (data['convoId'] != widget.convoId) {
        _fail('QR code is for a different transaction.');
        return;
      }
      if (data['action'] != widget.action) {
        _fail('This QR code is for a different step (${data['action']}).');
        return;
      }
      if (data['userId'] == widget.currentUserId) {
        _fail('You cannot scan your own QR code.');
        return;
      }

      // Write to Firestore
      final Map<String, dynamic> update = _isHandoff()
          ? {
              'isPaid': true,
              'isReceived': true,
              'handoffConfirmedAt': FieldValue.serverTimestamp(),
            }
          : {
              'isReturned': true,
              'isReturnConfirmed': true,
              'returnConfirmedAt': FieldValue.serverTimestamp(),
            };

      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.convoId)
          .update(update);

      setState(() {
        _confirmed = true;
        _processing = false;
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _fail('Invalid QR code. Please try again.');
    }
  }

  void _fail(String msg) {
    setState(() {
      _errorMessage = msg;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title,
                style: const TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(widget.itemName,
                style: const TextStyle(
                    color: Colors.black45, fontSize: 11)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accentColor,
          labelColor: _accentColor,
          unselectedLabelColor: Colors.black38,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2), text: 'My QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan Partner'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyQrTab(
            qrData: _myQrData,
            userName: widget.currentUserName,
            itemName: widget.itemName,
            action: widget.action,
            accentColor: _accentColor,
            description: _description,
          ),
          _ScanTab(
            active: !_confirmed,
            processing: _processing,
            confirmed: _confirmed,
            errorMessage: _errorMessage,
            accentColor: _accentColor,
            action: widget.action,
            onDetected: _onQrDetected,
            onClearError: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }
}

// ── My QR Code Tab ────────────────────────────────────────────────────────────

class _MyQrTab extends StatelessWidget {
  final String qrData;
  final String userName;
  final String itemName;
  final String action;
  final Color accentColor;
  final String description;

  const _MyQrTab({
    required this.qrData,
    required this.userName,
    required this.itemName,
    required this.action,
    required this.accentColor,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: accentColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Show this QR to your partner so they can scan it.',
                    style: TextStyle(
                        fontSize: 12,
                        color: accentColor,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // QR code card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Label strip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    action == 'handoff'
                        ? '📦  HANDOFF QR'
                        : '↩️  RETURN QR',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 20),

                // QR widget
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: accentColor,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  userName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 4),
                Text(
                  itemName,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

// ── Scanner Tab ───────────────────────────────────────────────────────────────

class _ScanTab extends StatefulWidget {
  final bool active;
  final bool processing;
  final bool confirmed;
  final String? errorMessage;
  final Color accentColor;
  final String action;
  final Future<void> Function(String) onDetected;
  final VoidCallback onClearError;

  const _ScanTab({
    required this.active,
    required this.processing,
    required this.confirmed,
    required this.errorMessage,
    required this.accentColor,
    required this.action,
    required this.onDetected,
    required this.onClearError,
  });

  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  MobileScannerController? _ctrl;
  bool _cameraStarted = false;

  void _startCamera() {
    setState(() {
      _ctrl = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      _cameraStarted = true;
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.confirmed) {
      return _SuccessView(accentColor: widget.accentColor, action: widget.action);
    }

    if (!_cameraStarted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.qr_code_scanner,
                  size: 48, color: widget.accentColor),
            ),
            const SizedBox(height: 20),
            const Text('Scan your partner\'s QR code',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text(
              widget.action == 'handoff'
                  ? 'Point your camera at the other person\'s handoff QR.'
                  : 'Point your camera at the other person\'s return QR.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _startCamera,
              icon: const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 18),
              label: const Text('Open Camera',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera feed
        MobileScanner(
          controller: _ctrl!,
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null) {
              widget.onDetected(barcode!.rawValue!);
            }
          },
        ),

        // Scan overlay
        _ScanOverlay(accentColor: widget.accentColor),

        // Processing / error state
        if (widget.processing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Verifying QR...',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ),

        if (widget.errorMessage != null)
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: GestureDetector(
              onTap: widget.onClearError,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red[700],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.errorMessage!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                    const Icon(Icons.close, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Scan Frame Overlay ────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  final Color accentColor;
  const _ScanOverlay({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(accentColor: accentColor),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Color accentColor;
  const _OverlayPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final dim = size.shortestSide * 0.65;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: dim, height: dim);

    // Dark overlay
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectXY(rect, 16, 16)),
      ),
      paint,
    );

    // Coloured corner brackets
    final cornerPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cs = 24.0; // corner size
    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;

    // TL
    canvas.drawLine(Offset(l, t + cs), Offset(l, t), cornerPaint);
    canvas.drawLine(Offset(l, t), Offset(l + cs, t), cornerPaint);
    // TR
    canvas.drawLine(Offset(r - cs, t), Offset(r, t), cornerPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cs), cornerPaint);
    // BL
    canvas.drawLine(Offset(l, b - cs), Offset(l, b), cornerPaint);
    canvas.drawLine(Offset(l, b), Offset(l + cs, b), cornerPaint);
    // BR
    canvas.drawLine(Offset(r - cs, b), Offset(r, b), cornerPaint);
    canvas.drawLine(Offset(r, b), Offset(r, b - cs), cornerPaint);

    // Centre label
    final tp = TextPainter(
      text: TextSpan(
        text: 'Align QR within frame',
        style: TextStyle(
            color: accentColor.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(cx - tp.width / 2, rect.bottom + 16));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Success View ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final Color accentColor;
  final String action;
  const _SuccessView(
      {required this.accentColor, required this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            builder: (ctx, val, child) =>
                Transform.scale(scale: val, child: child),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded,
                  color: accentColor, size: 64),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            action == 'handoff'
                ? 'Handoff Confirmed!'
                : 'Return Confirmed!',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: accentColor),
          ),
          const SizedBox(height: 8),
          Text(
            action == 'handoff'
                ? 'The item exchange has been registered.\nEnjoy your borrow!'
                : 'The item return is complete.\nTransaction concluded.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          const Text('Returning to chat...',
              style: TextStyle(fontSize: 11, color: Colors.black26)),
        ],
      ),
    );
  }
}
