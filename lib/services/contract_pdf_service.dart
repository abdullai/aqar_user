import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../core/pdf/pdf_readable_qr.dart';
import '../core/share/app_listing_links.dart';

/// توليد PDF لعقد تسويق: نص كامل (عربي عند توفر الخط)، رقم العقد، التواريخ، QR للتحقق، توقيعان.
class ContractPdfService {
  static const String _arabicFontAsset = 'assets/fonts/arabic_pdf_regular.ttf';

  /// يبنى الرابط من [AppListingLinks.contractVerifyWebUri] ويُمرَّر كنص للـ QR.
  static Future<Uint8List> buildListingContractFullPdf({
    required String contractId,
    required bool isAr,
    required String contractBody,
    String? ownerSignedAtIso,
    String? marketerSignedAtIso,
    Uint8List? marketerSignaturePng,
    Uint8List? ownerSignaturePng,
    /// رمز التحقق الظاهر في QR مع رقم العقد (يُخزَّن في `listing_contracts.verify_public_token`).
    String? verifyQrToken,
  }) async {
    pw.Font? arabicFont;
    try {
      final data = await rootBundle.load(_arabicFontAsset);
      arabicFont = pw.Font.ttf(data);
    } catch (_) {
      arabicFont = null;
    }

    final lang = isAr ? 'ar' : 'en';
    final verifyUri = kIsWeb
        ? AppListingLinks.contractVerifyWebUri(
            contractId,
            lang: lang,
            verifyToken: verifyQrToken,
          )
        : AppListingLinks.contractVerifyAppUri(
            contractId,
            lang: lang,
            verifyToken: verifyQrToken,
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
    final platformName = AppBranding.legalName(isAr: isAr);

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
    pw.ImageProvider? logo = await loadBrandingPdfLogo();

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

    final doc = pw.Document(
      title: isAr
          ? 'عقد تسويق عقاري - $contractId'
          : 'Real Estate Marketing Contract - $contractId',
      author: platformName,
      creator: platformName,
      producer: platformName,
      subject: isAr
          ? 'وثيقة عقد موقّعة رقمياً — قابلة للتحقق عبر QR'
          : 'Digitally signed contract — verifiable via QR',
      keywords:
          'contract,signed,immutable,verify,$contractId,${verifyQrToken ?? ''}',
    );

    // علامة مائية ظاهرة على كل صفحة + ترويسة وذيل ثابت يوحيان بأن الملف
    // وثيقة رسمية موقَّعة ولا يجوز تعديلها. أي تعديل لاحق يجعل QR التحقق
    // يكشف أن النسخة المُعدَّلة لا تطابق الأصل المخزَّن على الخادم.
    pw.Widget tamperWatermark() {
      return pw.Center(
        child: pw.Opacity(
          opacity: 0.08,
          child: pw.Transform.rotate(
            angle: -0.6,
            child: pw.Text(
              isAr
                  ? 'موقَّع رقمياً — غير قابل للتعديل'
                  : 'DIGITALLY SIGNED — DO NOT EDIT',
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 56,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ),
      );
    }

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(44),
      textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      theme: arabicFont != null
          ? pw.ThemeData.withFont(base: arabicFont, bold: arabicFont)
          : null,
      buildBackground: (ctx) => pw.FullPage(
        ignoreMargins: true,
        child: tamperWatermark(),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            isAr
                ? '$platformName — وثيقة موقَّعة رقمياً • $idLabel: $contractId'
                : '$platformName — Digitally signed document • $idLabel: $contractId',
            style: pw.TextStyle(
              font: arabicFont,
              fontSize: 8,
              color: PdfColors.grey800,
            ),
          ),
        ),
        footer: (ctx) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Divider(color: PdfColors.grey400, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  isAr
                      ? 'صفحة ${ctx.pageNumber} من ${ctx.pagesCount} • أي تعديل يبطل التحقق عبر QR'
                      : 'Page ${ctx.pageNumber} of ${ctx.pagesCount} • Any edit invalidates QR verification',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  verifyUrl,
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 7,
                    color: PdfColors.blueGrey700,
                  ),
                ),
              ],
            ),
          ],
        ),
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
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        isAr ? 'الهوية: مستخدم مسجّل في المنصة' : 'Identity: registered platform user',
                        style: small,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('$idLabel: $contractId', style: small),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('$dateLabel: $issuedDate', style: small),
                    if (verifyQrToken != null) ...[
                      if (verifyQrToken.trim().length >= 8)
                        pw.Text(
                          '${isAr ? 'رمز التحقق' : 'Verify ref'}: '
                          '${verifyQrToken.trim().substring(0, 8)}…',
                          style: small,
                        ),
                    ],
                  ],
                ),
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
                    stampFont: arabicFont,
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Container(
                  width: 140,
                  child: pdfReadableQrBlock(
                    data: verifyUrl,
                    isAr: isAr,
                    font: arabicFont,
                    fontBold: arabicFont,
                    size: 100,
                    title: verifyLabel,
                    hint: isAr
                        ? 'امسح للتحقق من العقد'
                        : 'Scan to verify contract',
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
                    stampFont: arabicFont,
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
    pw.Font? stampFont,
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
          pw.SizedBox(height: 6),
          pw.Text(
            isAr
                ? 'تم التحقق والتوقيع عبر ${AppBranding.legalName(isAr: true)}'
                : 'Verified & signed via ${AppBranding.legalName(isAr: false)}',
            style: pw.TextStyle(
              font: stampFont,
              fontSize: 7.5,
              color: PdfColors.grey700,
            ),
          ),
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
    String? verifyQrToken,
  }) {
    return buildListingContractFullPdf(
      contractId: contractId,
      isAr: isAr,
      contractBody: contractSnippet ?? '',
      ownerSignedAtIso: null,
      marketerSignedAtIso: null,
      marketerSignaturePng: marketerSignaturePng,
      ownerSignaturePng: ownerSignaturePng,
      verifyQrToken: verifyQrToken,
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
