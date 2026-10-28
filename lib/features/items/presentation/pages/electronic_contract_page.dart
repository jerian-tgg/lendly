import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'contract_service.dart';

/// Full-screen page for reviewing and e-signing the Lendly lending agreement.
/// Shown once after the lender accepts the borrow request in chat.
class ElectronicContractPage extends StatefulWidget {
  final String convoId;
  final String currentUserId;
  final bool isLender;
  final Map<String, dynamic> convoData;
  final Map<String, dynamic> itemData;
  final String lenderName;
  final String lenderEmail;
  final String borrowerName;
  final String borrowerEmail;

  const ElectronicContractPage({
    super.key,
    required this.convoId,
    required this.currentUserId,
    required this.isLender,
    required this.convoData,
    required this.itemData,
    required this.lenderName,
    required this.lenderEmail,
    required this.borrowerName,
    required this.borrowerEmail,
  });

  @override
  State<ElectronicContractPage> createState() => _ElectronicContractPageState();
}

class _ElectronicContractPageState extends State<ElectronicContractPage> {
  static const _purple = Color(0xFF7B40B5);

  bool _agreed        = false;
  bool _signing       = false;
  bool _previewing    = false;
  Uint8List? _pdfBytes;

  ContractData get _contractData {
    final startStr = widget.convoData['startDate'] as String? ?? '';
    final endStr   = widget.convoData['endDate']   as String? ?? '';
    final start    = DateTime.tryParse(startStr) ?? DateTime.now();
    final end      = DateTime.tryParse(endStr)   ?? DateTime.now();
    final retTs    = widget.convoData['returnDate'];
    String? retFmt;
    if (retTs != null) {
      retFmt = DateFormat('MMM d, yyyy – h:mm a').format((retTs as Timestamp).toDate());
    }

    return ContractData(
      convoId:             widget.convoId,
      itemName:            widget.itemData['name'] ?? 'Item',
      itemDescription:     widget.itemData['description'] ?? '',
      lenderName:          widget.lenderName,
      lenderEmail:         widget.lenderEmail,
      borrowerName:        widget.borrowerName,
      borrowerEmail:       widget.borrowerEmail,
      totalPrice:          (widget.convoData['totalPrice'] as num?)?.toDouble() ?? 0,
      totalDays:           widget.convoData['totalDays'] as int? ?? 0,
      startDate:           start,
      endDate:             end,
      returnDateFormatted: retFmt,
    );
  }

  Future<void> _previewPdf() async {
    setState(() => _previewing = true);
    try {
      _pdfBytes ??= await ContractService.generatePdfBytes(_contractData);
      if (!mounted) return;
      final bytes = _pdfBytes!;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdfPreviewPage(pdfBytes: bytes),
        ),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _sign() async {
    if (!_agreed) return;
    setState(() => _signing = true);
    try {
      _pdfBytes ??= await ContractService.generatePdfBytes(_contractData);
      await ContractService.sign(
        data:   _contractData,
        userId: widget.currentUserId,
        role:   widget.isLender ? 'lender' : 'borrower',
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.verified_outlined, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Contract signed successfully!'),
            ]),
            backgroundColor: _purple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data  = _contractData;
    final dateFmt = DateFormat('MMMM d, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: const Text(
          'Electronic Lending Agreement',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton.icon(
            icon: _previewing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _purple,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: _purple, size: 18),
            label: const Text('View PDF', style: TextStyle(color: _purple, fontSize: 12)),
            onPressed: _previewing ? null : _previewPdf,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.convoId)
            .snapshots(),
        builder: (context, snap) {
          final convo      = snap.data?.data() as Map<String, dynamic>? ?? widget.convoData;
          final lenderSigned   = convo['contractLenderSigned']   == true;
          final borrowerSigned = convo['contractBorrowerSigned'] == true;
          final bothSigned     = convo['contractSigned']         == true;
          final mySignField = widget.isLender ? lenderSigned : borrowerSigned;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── RA 8792 badge ──
                _LegalBadge(),
                const SizedBox(height: 16),

                // ── Header card ──
                _ContractHeaderCard(
                  convoId:    widget.convoId,
                  itemName:   data.itemName,
                  lenderName: data.lenderName,
                  borrowerName: data.borrowerName,
                  totalPrice: data.totalPrice,
                  totalDays:  data.totalDays,
                  startDate:  data.startDate,
                  endDate:    data.endDate,
                  dateFmt:    dateFmt,
                  returnDateFormatted: data.returnDateFormatted,
                ),
                const SizedBox(height: 16),

                // ── Parties ──
                _SectionCard(
                  title: 'Parties',
                  icon: Icons.people_outline,
                  child: Column(
                    children: [
                      _PartyRow(
                        role: 'Lender',
                        name: data.lenderName,
                        email: data.lenderEmail,
                        signed: lenderSigned,
                      ),
                      const Divider(height: 16),
                      _PartyRow(
                        role: 'Borrower',
                        name: data.borrowerName,
                        email: data.borrowerEmail,
                        signed: borrowerSigned,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Terms summary ──
                _SectionCard(
                  title: 'Key Terms & Conditions',
                  icon: Icons.gavel_outlined,
                  child: const _TermsSummary(),
                ),
                const SizedBox(height: 12),

                // ── Legal compliance ──
                _SectionCard(
                  title: 'Legal Compliance',
                  icon: Icons.shield_outlined,
                  child: const _LegalComplianceBlock(),
                ),
                const SizedBox(height: 20),

                // ── Signature section ──
                if (bothSigned)
                  _AlreadySignedBanner()
                else if (mySignField)
                  _WaitingBanner(isLender: widget.isLender)
                else
                  _SignatureSection(
                    agreed: _agreed,
                    onAgreedChanged: (v) => setState(() => _agreed = v ?? false),
                    onSign: _sign,
                    signing: _signing,
                    isLender: widget.isLender,
                    userName: widget.isLender ? data.lenderName : data.borrowerName,
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _LegalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B40B5), Color(0xFF5B2D8E)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x337B40B5), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Legally Binding Electronic Contract',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Compliant with Philippine RA 8792 (Electronic Commerce Act)',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'RA 8792',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractHeaderCard extends StatelessWidget {
  final String convoId;
  final String itemName;
  final String lenderName;
  final String borrowerName;
  final double totalPrice;
  final int totalDays;
  final DateTime startDate;
  final DateTime endDate;
  final DateFormat dateFmt;
  final String? returnDateFormatted;

  const _ContractHeaderCard({
    required this.convoId,
    required this.itemName,
    required this.lenderName,
    required this.borrowerName,
    required this.totalPrice,
    required this.totalDays,
    required this.startDate,
    required this.endDate,
    required this.dateFmt,
    this.returnDateFormatted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: Color(0xFF7B40B5), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Lending Agreement',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A2E)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ID: ${convoId.substring(0, convoId.length.clamp(0, 8)).toUpperCase()}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF7B40B5), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _InfoRow(Icons.inventory_2_outlined, 'Item', itemName),
          _InfoRow(Icons.calendar_today_outlined, 'Borrow Period',
              '${dateFmt.format(startDate)} → ${dateFmt.format(endDate)}'),
          _InfoRow(Icons.timelapse, 'Duration', '$totalDays day${totalDays != 1 ? "s" : ""}'),
          _InfoRow(Icons.payments_outlined, 'Total Amount', '₱${totalPrice.toStringAsFixed(2)}'),
          if (returnDateFormatted != null)
            _InfoRow(Icons.schedule_outlined, 'Return Deadline', returnDateFormatted!),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.black38),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A2E), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: const Color(0xFF7B40B5), size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PartyRow extends StatelessWidget {
  final String role;
  final String name;
  final String email;
  final bool signed;
  const _PartyRow({required this.role, required this.name, required this.email, required this.signed});

  @override
  Widget build(BuildContext context) {
    final isLender = role == 'Lender';
    final color = isLender ? const Color(0xFF7B40B5) : const Color(0xFF3498DB);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            role,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(email, style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ],
          ),
        ),
        if (signed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, size: 12, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Signed', style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 12, color: Colors.orange),
                SizedBox(width: 4),
                Text('Pending', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TermsSummary extends StatelessWidget {
  const _TermsSummary();

  @override
  Widget build(BuildContext context) {
    final terms = [
      (Icons.handshake_outlined, 'Proper use of the borrowed item only'),
      (Icons.security_outlined, 'Item must be returned in original condition'),
      (Icons.schedule_outlined, 'Return on or before the agreed deadline'),
      (Icons.warning_amber_outlined, 'Borrower liable for damage or loss'),
      (Icons.payments_outlined, 'Full payment is non-refundable'),
      (Icons.verified_user_outlined, 'Lender warrants lawful ownership'),
      (Icons.gavel_outlined, 'Philippine law governs this agreement'),
      (Icons.forum_outlined, 'Disputes resolved via good-faith negotiation'),
    ];

    return Column(
      children: terms.map((t) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B40B5).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(t.$1, size: 13, color: const Color(0xFF7B40B5)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.$2, style: const TextStyle(fontSize: 12, color: Color(0xFF333333))),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _LegalComplianceBlock extends StatelessWidget {
  const _LegalComplianceBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 14),
            SizedBox(width: 6),
            Text(
              'Legal Notice',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
            ),
          ]),
          SizedBox(height: 8),
          Text(
            'This is a legally binding electronic contract under Republic Act No. 8792 '
            '(Philippine Electronic Commerce Act). By checking the agreement box and tapping '
            '"Sign Contract", you confirm that:\n\n'
            '• You have read and understood all terms\n'
            '• You agree to be legally bound by this contract\n'
            '• Your electronic signature is as valid as a handwritten signature\n'
            '• This agreement may be used as evidence in legal proceedings',
            style: TextStyle(fontSize: 11, color: Color(0xFF5D4037), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SignatureSection extends StatelessWidget {
  final bool agreed;
  final ValueChanged<bool?> onAgreedChanged;
  final VoidCallback onSign;
  final bool signing;
  final bool isLender;
  final String userName;

  const _SignatureSection({
    required this.agreed,
    required this.onAgreedChanged,
    required this.onSign,
    required this.signing,
    required this.isLender,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(color: Color(0x147B40B5), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.draw_outlined, color: Color(0xFF7B40B5), size: 18),
            const SizedBox(width: 8),
            Text(
              'Your Signature — ${isLender ? "Lender" : "Borrower"}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A2E)),
            ),
          ]),
          const SizedBox(height: 12),

          // Signature preview box (name displayed as e-signature)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF7B40B5).withValues(alpha: 0.3), style: BorderStyle.solid),
            ),
            child: Center(
              child: Text(
                userName,
                style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFF7B40B5),
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your full name serves as your electronic signature.',
            style: TextStyle(fontSize: 10, color: Colors.black45),
          ),
          const SizedBox(height: 16),

          // Checkbox agreement
          InkWell(
            onTap: () => onAgreedChanged(!agreed),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: agreed ? const Color(0xFFEDE7F6) : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: agreed
                      ? const Color(0xFF7B40B5).withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: agreed,
                    onChanged: onAgreedChanged,
                    activeColor: const Color(0xFF7B40B5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'I have read, understood, and agree to all terms and conditions of this Electronic Lending Agreement. I acknowledge this constitutes a legally binding contract under RA 8792.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF333333), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sign button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!agreed || signing) ? null : onSign,
              icon: signing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified_outlined, size: 18, color: Colors.white),
              label: Text(
                signing ? 'Signing...' : 'Sign Contract',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B40B5),
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlreadySignedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified, color: Color(0xFF2E7D32), size: 36),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contract Fully Executed',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2E7D32)),
                ),
                SizedBox(height: 4),
                Text(
                  'Both parties have signed. The contract PDF has been generated and stored securely. The transaction may now proceed.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF388E3C), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  final bool isLender;
  const _WaitingBanner({required this.isLender});

  @override
  Widget build(BuildContext context) {
    final other = isLender ? 'borrower' : 'lender';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_outlined, color: Colors.orange, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You\'ve Signed ✓',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange),
                ),
                const SizedBox(height: 4),
                Text(
                  'Waiting for the $other to review and sign the contract. You\'ll be notified once they sign.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF5D4037), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── PDF Preview Page ──────────────────────────────────────────────────────────

class _PdfPreviewPage extends StatelessWidget {
  final Uint8List pdfBytes;
  const _PdfPreviewPage({required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Contract Preview',
          style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF7B40B5)),
            onPressed: () => Printing.sharePdf(bytes: pdfBytes, filename: 'lendly_contract.pdf'),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => pdfBytes,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfPreviewPageDecoration: const BoxDecoration(color: Color(0xFFF7FAFC)),
      ),
    );
  }
}
