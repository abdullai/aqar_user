import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/share/app_listing_links.dart';

/// توليد PDF لعقد تسويق: نص كامل (عربي عند توفر الخط)، رقم العقد، التواريخ، QR للتحقق، توقيعان.
class ContractPdfService {
  static const String _arabicFontAsset = 'assets/fonts/arabic_pdf_regular.ttf';
  static const String _platformLogoAsset = 'assets/logo.png';

  /// يبنى الرابط من [AppListingLinks.contractVerifyWebUri] ويُمرَّر كنص للـ QR.
  static Future<Uint8List> buildListingContractFullPdf({
    required String contractId,
    required bool isAr,
    required String contractBody,
    String? ownerSignedAtIso,
    String? marketerSignedAtIso,
    Uint8List? marketerSignaturePng,
    Uint8List? ownerSignaturePng,
  }) async {
    pw.Font? arabicFont;
    try {
      final data = await rootBundle.load(_arabicFontAsset);
      arabicFont = pw.Font.ttf(data);
    } catch (_) {
      arabicFont = null;
    }

    final verifyUri = AppListingLinks.contractVerifyWebUri(
      contractId,
      lang: isAr ? 'ar' : 'en',
    );
    final verifyUrl = verifyUri.toString();
    final now = DateTime.now().toLocal();
    final issuedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final title = isAr ? 'عقد تسويق عقاري' : 'Real estate marketing contract';
    final idLabel = isAr ? 'رقم العقد' : 'Contract no.';
    final dateLabel = isAr ? 'تاريخ العقد' : 'Contract date';
    final verifyLabel = isAr
        ? 'التحقق من صحة العقد (امسح الرمز)'
        : 'Verify authenticity (scan)';
    final platformName = isAr ? 'منصة عقار موثوق' : 'Aqar Mawthuq Platform';

    final signedLine = _formatSignedDateLine(
      isAr: isAr,
      ownerSignedAtIso: ownerSignedAtIso,
      marketerSignedAtIso: marketerSignedAtIso,
    );

    final bodyText = contractBody.trim();
    final paragraphs = _splitContractBody(bodyText);

    pw.ImageProvider? marketerSig;
    if (marketerSignaturePng != null && marketerSignaturePng.isNotEmpty) {
      try {
        marketerSig = pw.MemoryImage(marketerSignaturePng);
      } catch (_) {
        marketerSig = null;
      }
    }
    pw.ImageProvider? ownerSig;
    if (ownerSignaturePng != null && ownerSignaturePng.isNotEmpty) {
      try {
        ownerSig = pw.MemoryImage(ownerSignaturePng);
      } catch (_) {
        ownerSig = null;
      }
    }
    pw.ImageProvider? logo;
    try {
      final logoData = await rootBundle.load(_platformLogoAsset);
      logo = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    final baseStyle = pw.TextStyle(
      font: arabicFont,
      fontSize: 10,
      lineSpacing: 1.15,
    );
    final headerStyle = pw.TextStyle(
      font: arabicFont,
      fontSize: 18,
      fontWeight: pw.FontWeight.bold,
    );
    final small = pw.TextStyle(font: arabicFont, fontSize: 9);
    const fallback = pw.TextStyle(fontSize: 10, lineSpacing: 1.15);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        theme: arabicFont != null
            ? pw.ThemeData.withFont(base: arabicFont, bold: arabicFont)
            : null,
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (ctx) {
          final out = <pw.Widget>[
            pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    isAr
                        ? 'بسم الله الرحمن الرحيم'
                        : 'In the name of Allah, the Most Gracious, the Most Merciful',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 8),
                  if (logo != null)
                    pw.Image(
                      logo,
                      width: 74,
                      height: 74,
                      fit: pw.BoxFit.contain,
                    )
                  else
                    pw.Text(platformName, style: headerStyle),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    platformName,
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('$idLabel: $contractId', style: small),
                pw.Text('$dateLabel: $issuedDate', style: small),
              ],
            ),
            pw.Divider(color: PdfColors.grey500, thickness: 0.7),
            pw.SizedBox(height: 8),
            pw.Text(title, style: headerStyle, textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 10),
            if (signedLine.isNotEmpty) ...[
              pw.Text(
                '${isAr ? 'تاريخ اكتمال التوقيعات' : 'Signatures completed'}: $signedLine',
                style: baseStyle,
                textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            ],
            pw.SizedBox(height: 12),
          ];

          if (arabicFont == null) {
            out.add(
              pw.Text(
                isAr
                    ? 'تعذر تحميل خط العربية. أضف الملف assets/fonts/arabic_pdf_regular.ttf'
                    : 'Arabic font missing. Add assets/fonts/arabic_pdf_regular.ttf',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
              ),
            );
            out.add(pw.SizedBox(height: 8));
          }

          for (final p in paragraphs) {
            final line = arabicFont == null ? _asciiOnly(p) : p;
            if (line.trim().isEmpty) {
              out.add(pw.SizedBox(height: 6));
              continue;
            }
            out.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  line,
                  style: arabicFont == null ? fallback : baseStyle,
                  textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
                ),
              ),
            );
          }

          out.add(pw.SizedBox(height: 16));
          out.add(pw.Divider(color: PdfColors.grey500, thickness: 0.7));
          out.add(pw.SizedBox(height: 8));
          out.add(
            pw.Text(
              isAr ? 'الأطراف والتوقيعات' : 'Parties and signatures',
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          );
          out.add(pw.SizedBox(height: 10));
          out.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _signatureBox(
                    label:
                        isAr ? 'توقيع المالك / المعلن' : 'Owner / Advertiser',
                    sig: ownerSig,
                    small: small,
                    isAr: isAr,
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Container(
                  width: 116,
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: verifyUrl,
                        width: 92,
                        height: 92,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(verifyLabel,
                          style: small, textAlign: pw.TextAlign.center),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: _signatureBox(
                    label:
                        isAr ? 'توقيع المسوّق / المنشأة' : 'Marketer / Entity',
                    sig: marketerSig,
                    small: small,
                    isAr: isAr,
                  ),
                ),
              ],
            ),
          );
          out.add(pw.SizedBox(height: 6));
          out.add(
              pw.Text(verifyUrl, style: small, textAlign: pw.TextAlign.center));

          return out;
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _signatureBox({
    required String label,
    required pw.TextStyle small,
    required bool isAr,
    pw.ImageProvider? sig,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment:
            isAr ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: small),
          pw.SizedBox(height: 8),
          if (sig != null)
            pw.Image(sig, width: 150, height: 64, fit: pw.BoxFit.contain)
          else
            pw.Container(height: 64),
          pw.Container(height: 0.7, color: PdfColors.grey600),
        ],
      ),
    );
  }

  /// توافق مع الاستدعاءات القديمة — يمرّر المقتطف كنص كامل.
  static Future<Uint8List> buildListingContractReferencePdf({
    required String contractId,
    required bool isAr,
    String? contractSnippet,
    Uint8List? marketerSignaturePng,
    Uint8List? ownerSignaturePng,
  }) {
    return buildListingContractFullPdf(
      contractId: contractId,
      isAr: isAr,
      contractBody: contractSnippet ?? '',
      ownerSignedAtIso: null,
      marketerSignedAtIso: null,
      marketerSignaturePng: marketerSignaturePng,
      ownerSignaturePng: ownerSignaturePng,
    );
  }

  static String _formatSignedDateLine({
    required bool isAr,
    String? ownerSignedAtIso,
    String? marketerSignedAtIso,
  }) {
    DateTime? p(String? s) => s == null || s.trim().isEmpty
        ? null
        : DateTime.tryParse(s.trim())?.toLocal();
    final o = p(ownerSignedAtIso);
    final m = p(marketerSignedAtIso);
    if (o == null && m == null) return '';
    DateTime? latest;
    if (o != null && m != null) {
      latest = o.isAfter(m) ? o : m;
    } else {
      latest = o ?? m;
    }
    if (latest == null) return '';
    final d =
        '${latest.year}-${latest.month.toString().padLeft(2, '0')}-${latest.day.toString().padLeft(2, '0')} '
        '${latest.hour.toString().padLeft(2, '0')}:${latest.minute.toString().padLeft(2, '0')}';
    if (isAr) {
      return '$d (توقيع المالك: ${o != null ? _shortDate(o) : '—'} — المسوّق: ${m != null ? _shortDate(m) : '—'})';
    }
    return '$d (owner: ${o != null ? _shortDate(o) : '—'}, marketer: ${m != null ? _shortDate(m) : '—'})';
  }

  static String _shortDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static List<String> _splitContractBody(String raw) {
    if (raw.isEmpty) return const [''];
    final normalized = raw.replaceAll('\r\n', '\n');
    final parts = normalized.split('\n');
    final out = <String>[];
    for (final line in parts) {
      if (line.length > 500) {
        var s = line;
        while (s.isNotEmpty) {
          out.add(s.length > 500 ? s.substring(0, 500) : s);
          s = s.length > 500 ? s.substring(500) : '';
        }
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static String _asciiOnly(String input) {
    final buf = StringBuffer();
    for (final c in input.runes) {
      if (c <= 0x7E && c >= 0x20) buf.writeCharCode(c);
      if (c == 0x0A || c == 0x0D) buf.writeCharCode(c);
    }
    final s = buf.toString().trim();
    return s.isEmpty ? '(…)' : s;
  }

  static Future<Uint8List?> downloadMarketerSignaturePng(
      SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return null;
    return downloadUserSignaturePng(sb, uid);
  }

  static Future<Uint8List?> downloadUserSignaturePng(
    SupabaseClient sb,
    String userId,
  ) async {
    final uid = userId.trim();
    if (uid.isEmpty) return null;
    try {
      final row = await sb
          .from('users_profiles')
          .select('signature_storage_path')
          .eq('user_id', uid)
          .maybeSingle();
      final path = (row?['signature_storage_path'] ?? '').toString().trim();
      if (path.isEmpty) return null;
      return await sb.storage.from('kyc').download(path);
    } catch (_) {
      return null;
    }
  }
}
