import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_branding.dart';
import 'branding_logo_image.dart';

/// شعار PDF ذكي — ويب→logo.png | تطبيق→splashscreen.png
Future<pw.ImageProvider?> loadBrandingPdfLogo() async {
  try {
    final bytes = await loadBrandingLogoBytes();
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  } catch (_) {
    return null;
  }
}

/// ترويسة PDF موحّدة — شعار ذكي + اسم المنصة.
pw.Widget brandingPdfHeader({
  required pw.Font base,
  required pw.Font bold,
  required pw.ImageProvider? logo,
  required bool isAr,
  required String docTitle,
  PdfColor brandColor = PdfColors.teal800,
  String? subtitle,
  String? metaLine,
}) {
  final platformName = AppBranding.legalName(isAr: isAr);
  final shortBrand = AppBranding.brandName(isAr: isAr);
  final contactLine = isAr
      ? '${AppBranding.supportEmail} · ${AppBranding.supportPhone}'
      : '${AppBranding.supportEmail} · ${AppBranding.supportPhone}';

  final logoBox = pw.Container(
    width: 68,
    height: 68,
    padding: const pw.EdgeInsets.all(5),
    child: logo != null
        ? pw.Image(logo, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              shortBrand,
              style: pw.TextStyle(font: bold, fontSize: 10, color: brandColor),
              textAlign: pw.TextAlign.center,
            ),
          ),
  );

  final textColumn = pw.Column(
    crossAxisAlignment:
        isAr ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        platformName,
        style: pw.TextStyle(font: bold, fontSize: 11, color: brandColor),
        textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        contactLine,
        style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey700),
        textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
      ),
      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          subtitle.trim(),
          style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey600),
          textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
        ),
      ],
    ],
  );

  final titleColumn = pw.Column(
    crossAxisAlignment:
        isAr ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end,
    children: [
      pw.Text(
        docTitle,
        style: pw.TextStyle(font: bold, fontSize: 13, color: brandColor),
        textAlign: isAr ? pw.TextAlign.start : pw.TextAlign.end,
      ),
      if (metaLine != null && metaLine.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          metaLine.trim(),
          style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey800),
          textAlign: isAr ? pw.TextAlign.start : pw.TextAlign.end,
        ),
      ],
    ],
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: isAr
            ? [titleColumn, pw.Spacer(), logoBox, pw.SizedBox(width: 10), textColumn]
            : [textColumn, pw.SizedBox(width: 10), logoBox, pw.Spacer(), titleColumn],
      ),
      pw.SizedBox(height: 8),
      pw.Container(height: 2, color: brandColor),
      pw.SizedBox(height: 10),
    ],
  );
}
