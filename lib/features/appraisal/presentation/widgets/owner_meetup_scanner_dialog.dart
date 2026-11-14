import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class OwnerMeetupScannerDialog extends StatefulWidget {
  final String expectedOwnerId;
  final String ownerName;

  const OwnerMeetupScannerDialog({
    super.key,
    required this.expectedOwnerId,
    required this.ownerName,
  });

  @override
  State<OwnerMeetupScannerDialog> createState() => _OwnerMeetupScannerDialogState();
}

class _OwnerMeetupScannerDialogState extends State<OwnerMeetupScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawVal = barcode.rawValue!.trim();
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      String scannedUserId = '';
      if (rawVal.startsWith('{') && rawVal.endsWith('}')) {
        final data = jsonDecode(rawVal) as Map<String, dynamic>;
        scannedUserId = (data['userId'] ?? '').toString().trim();
      } else {
        scannedUserId = rawVal;
      }

      if (scannedUserId.isNotEmpty && scannedUserId == widget.expectedOwnerId) {
        _controller.stop();
        Navigator.pop(context, true);
      } else {
        setState(() {
          _errorMessage = 'Scanned QR does not match owner (${widget.ownerName}).';
          _isProcessing = false;
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Invalid QR code. Please scan the owner\'s Personal QR Code.';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 380,
        height: 480,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: const Color(0xFF98259A),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scan ${widget.ownerName}\'s QR',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF98259A), width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (_errorMessage != null)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: const Text(
                'Ask the owner to open their Profile > My Personal QR Code and point camera at it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

