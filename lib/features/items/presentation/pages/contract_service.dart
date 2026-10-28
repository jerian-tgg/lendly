import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Holds all the data needed to populate the contract.
class ContractData {
  final String convoId;
  final String itemName;
  final String itemDescription;
  final String lenderName;
  final String lenderEmail;
  final String borrowerName;
  final String borrowerEmail;
  final double totalPrice;
  final int totalDays;
  final DateTime startDate;
  final DateTime endDate;
  final String? returnDateFormatted;

  const ContractData({
    required this.convoId,
    required this.itemName,
    required this.itemDescription,
    required this.lenderName,
    required this.lenderEmail,
    required this.borrowerName,
    required this.borrowerEmail,
    required this.totalPrice,
    required this.totalDays,
    required this.startDate,
    required this.endDate,
    this.returnDateFormatted,
  });
}

class ContractService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Generates the PDF bytes for preview / review purposes (no upload).
  static Future<Uint8List> generatePdfBytes(ContractData data) async {
    return _buildPdf(data);
  }

  /// Signs the contract for [userId] with given [role] ('lender' or 'borrower').
  /// On second sign (both parties done) it generates, uploads the PDF,
  /// and writes the final record to Firestore.
  static Future<void> sign({
    required ContractData data,
    required String userId,
    required String role, // 'lender' | 'borrower'
  }) async {
    final ref = _db.collection('conversations').doc(data.convoId);
    final sigField = role == 'lender' ? 'contractLenderSigned' : 'contractBorrowerSigned';
    final tsField  = role == 'lender' ? 'contractLenderSignedAt' : 'contractBorrowerSignedAt';

    await ref.update({
      sigField: true,
      tsField: FieldValue.serverTimestamp(),
    });

    // Re-read to check if both parties have now signed
    final updated = (await ref.get()).data() ?? {};
    final bothSigned = updated['contractLenderSigned'] == true &&
        updated['contractBorrowerSigned'] == true;

    if (bothSigned && updated['contractPdfUrl'] == null) {
      // Generate & upload PDF
      final pdfBytes = await _buildPdf(data);
      final storageRef = _storage
          .ref()
          .child('contracts/${data.convoId}/lendly_contract.pdf');
      final uploadTask = storageRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final downloadUrl = await (await uploadTask).ref.getDownloadURL();

      await ref.update({
        'contractPdfUrl': downloadUrl,
        'contractFinalizedAt': FieldValue.serverTimestamp(),
        'contractSigned': true,
      });
    }
  }

  // ── PDF builder ────────────────────────────────────────────────────────────

  static Future<Uint8List> _buildPdf(ContractData d) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('MMMM d, yyyy');
    final now = DateTime.now();
    const grey   = PdfColors.grey700;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _buildHeader(ctx, d, now, dateFmt),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          _section('RECITALS'),
          _body(
            'This Electronic Lending Agreement ("Agreement") is entered into as of '
            '${dateFmt.format(now)}, by and between the parties identified below, '
            'facilitated through the Lendly platform. This Agreement is executed '
            'electronically in accordance with the Philippine Electronic Commerce Act '
            '(Republic Act No. 8792) and its Implementing Rules and Regulations, '
            'and shall have the same legal effect as a manually signed written contract.',
          ),
          pw.SizedBox(height: 16),

          _section('ARTICLE I — PARTIES'),
          _partyBlock('LENDER', d.lenderName, d.lenderEmail),
          pw.SizedBox(height: 8),
          _partyBlock('BORROWER', d.borrowerName, d.borrowerEmail),
          pw.SizedBox(height: 16),

          _section('ARTICLE II — SUBJECT MATTER'),
          _keyValue('Item', d.itemName, grey),
          if (d.itemDescription.isNotEmpty)
            _keyValue('Description', d.itemDescription, grey),
          _keyValue('Rental Period', '${dateFmt.format(d.startDate)} to ${dateFmt.format(d.endDate)}', grey),
          _keyValue('Duration', '${d.totalDays} day${d.totalDays != 1 ? "s" : ""}', grey),
          _keyValue('Total Amount', '₱${d.totalPrice.toStringAsFixed(2)} (Philippine Peso)', grey),
          if (d.returnDateFormatted != null)
            _keyValue('Agreed Return Deadline', d.returnDateFormatted!, grey),
          pw.SizedBox(height: 16),

          _section('ARTICLE III — TERMS & CONDITIONS'),
          _numberedTerms([
            'PROPER USE. The Borrower agrees to use the borrowed item solely for its intended purpose and shall not sub-lend, sell, pledge, or otherwise transfer possession of the item to any third party without the express written consent of the Lender.',
            'CARE OF ITEM. The Borrower shall exercise reasonable care in the use of the item and shall return it in the same condition as received, subject to normal wear and tear.',
            'TIMELY RETURN. The Borrower agrees to return the item on or before the agreed return deadline. Failure to return the item on time constitutes a breach of this Agreement and may result in additional charges and legal action.',
            'DAMAGE & LOSS. The Borrower shall be liable for any damage, loss, or destruction of the item during the rental period. Liability shall extend to the fair market value of the item at the time of damage or loss.',
            'PAYMENT. The Borrower agrees to pay the total rental amount of ₱${d.totalPrice.toStringAsFixed(2)} in full. This amount is non-refundable except as otherwise agreed by both parties.',
            'LENDER WARRANTIES. The Lender warrants that the item is in good working condition and that the Lender is the lawful owner or has authority to lend the item.',
            'LIABILITY LIMITATION. The Lendly platform acts solely as a facilitator and is not a party to this Agreement. Neither Lendly nor its affiliates shall be liable for any loss, damage, or injury arising from this lending arrangement.',
            'DISPUTE RESOLUTION. Any dispute arising out of this Agreement shall first be resolved through good-faith negotiation. If unresolved within thirty (30) days, the parties agree to submit the dispute to the appropriate courts or mediation bodies with jurisdiction in the Philippines.',
            'GOVERNING LAW. This Agreement shall be governed by the laws of the Republic of the Philippines, including Republic Act No. 8792 (Electronic Commerce Act) and the Civil Code of the Philippines.',
            'ENTIRE AGREEMENT. This Agreement constitutes the entire agreement between the parties with respect to the subject matter hereof and supersedes all prior negotiations, representations, or agreements, whether oral or written.',
          ]),
          pw.SizedBox(height: 16),

          _section('ARTICLE IV — ELECTRONIC SIGNATURES'),
          _body(
            'By electronically agreeing to this contract within the Lendly application, '
            'each party acknowledges that they have read, understood, and agreed to all '
            'terms and conditions set forth herein. This electronic agreement constitutes '
            'a valid, binding, and enforceable contract under RA 8792.',
          ),
          pw.SizedBox(height: 20),
          _signaturesRow(d, now, dateFmt),
          pw.SizedBox(height: 24),

          _section('ARTICLE V — LEGAL NOTICE'),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              border: pw.Border.all(color: PdfColors.amber700, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: _body(
              'NOTICE: This document is an electronic contract executed under Republic Act No. 8792 '
              '(Philippine Electronic Commerce Act). It has the same legal force and effect as a '
              'handwritten contract. Falsification, tampering, or unauthorized alteration of this '
              'document may constitute a criminal offense under Philippine law. This contract is '
              'stored securely on Lendly servers and may be used as evidence in legal proceedings.',
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── PDF helper widgets ─────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    pw.Context ctx,
    ContractData d,
    DateTime now,
    DateFormat dateFmt,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(
                'LENDLY',
                style: pw.TextStyle(
                  color: PdfColors.deepPurple,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              pw.Text(
                'Electronic Lending Agreement',
                style: const pw.TextStyle(
                  color: PdfColors.grey600,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
              ),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(
                'CONTRACT ID',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey500,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                d.convoId.substring(0, d.convoId.length.clamp(0, 12)).toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated: ${dateFmt.format(now)}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
              ),
            ]),
          ],
        ),
        pw.Divider(color: PdfColors.deepPurple, thickness: 1.5),
        pw.SizedBox(height: 4),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Column(children: [
      pw.Divider(color: PdfColors.grey300),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Lendly Platform — Electronic Contract | RA 8792 Compliant',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
        ],
      ),
    ]);
  }

  static pw.Widget _section(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFEDE7F6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: PdfColors.deepPurple,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static pw.Widget _body(String text) {
    return pw.Text(
      text,
      textAlign: pw.TextAlign.justify,
      style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800, lineSpacing: 2),
    );
  }

  static pw.Widget _keyValue(String key, String value, PdfColor grey) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              '$key:',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: grey,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _partyBlock(String role, String name, String email) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      margin: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0xFFCE93D8), width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        color: PdfColor.fromInt(0xFFF3E5F5),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.deepPurple,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              role,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(email, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _numberedTerms(List<String> terms) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: terms.asMap().entries.map((e) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 18,
                height: 18,
                margin: const pw.EdgeInsets.only(right: 8, top: 1),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.deepPurple,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text(
                    '${e.key + 1}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  e.value,
                  textAlign: pw.TextAlign.justify,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800, lineSpacing: 1.8),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _signaturesRow(ContractData d, DateTime now, DateFormat dateFmt) {
    return pw.Row(
      children: [
        pw.Expanded(child: _sigBlock('LENDER', d.lenderName, d.lenderEmail, now, dateFmt)),
        pw.SizedBox(width: 24),
        pw.Expanded(child: _sigBlock('BORROWER', d.borrowerName, d.borrowerEmail, now, dateFmt)),
      ],
    );
  }

  static pw.Widget _sigBlock(
    String role,
    String name,
    String email,
    DateTime now,
    DateFormat dateFmt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            role,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple),
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            height: 28,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEDE7F6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Center(
              child: pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.deepPurple,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(email, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          pw.Text(
            'Signed: ${dateFmt.format(now)}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '✔ Electronically signed via Lendly (RA 8792)',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.green700),
          ),
        ],
      ),
    );
  }
}
