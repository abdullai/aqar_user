import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../payment/invoice_copy.dart';
import '../utils/app_money.dart';
import 'app_branding.dart';
import 'branding_logo_image.dart';

/// لون ترويسة المستندات — نفس بذرة المنصة.
const PdfColor kDocumentBrandPdfColor = PdfColor.fromInt(0xFF0F766E);

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

String _pdfText(String raw) => InvoiceCopy.stripBidi(raw);

/// ترويسة موحّدة لمستندات PDF، مع تخطيط مستقل للفواتير عند الحاجة.
/// البسملة في الوسط، الشعار تحته في الوسط، وبيانات الشركة/المستند على الجانبين.
pw.Widget brandingPdfHeader({
  required pw.Font base,
  required pw.Font bold,
  required pw.ImageProvider? logo,
  required bool isAr,
  required String docTitle,
  PdfColor brandColor = kDocumentBrandPdfColor,
  String? subtitle,
  String? metaLine,
  String? leftMeta,
  String? rightMeta,
  bool invoiceLayout = false,
  List<pw.Font>? fontFallback,
}) {
  final platformName = AppBranding.invoiceLetterheadBrandName(isAr: isAr);
  final shortBrand = AppBranding.brandName(isAr: isAr);
  final ksa = isAr ? 'المملكة العربية السعودية' : 'Kingdom of Saudi Arabia';
  pw.TextStyle st(pw.Font f, double size, {PdfColor? color}) => pw.TextStyle(
        font: f,
        fontSize: size,
        color: color,
        fontFallback: fontFallback ?? const <pw.Font>[],
        height: 1.25,
      );

  final logoBox = pw.Container(
    child: logo != null
        ? pw.Image(logo, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              shortBrand,
              style: st(bold, 9, color: brandColor),
              textAlign: pw.TextAlign.center,
            ),
          ),
  );

  final rightText = _pdfText((rightMeta ?? metaLine ?? '').trim());
  final title = _pdfText(docTitle);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Center(
        child: pw.Text(
          isAr
              ? 'بسم الله الرحمن الرحيم'
              : 'In the name of Allah, the Most Gracious, the Most Merciful',
          style: st(bold, 12.5, color: PdfColors.black),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              child: pw.Container(
                height: 92,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: brandColor, width: 0.8),
                ),
                child: logoBox,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Directionality(
                textDirection:
                    isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                child: pw.Container(
                  height: 92,
                  padding: const pw.EdgeInsets.fromLTRB(12, 6, 12, 6),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF0FDFA),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border(
                      right: isAr
                          ? pw.BorderSide(color: brandColor, width: 3)
                          : pw.BorderSide.none,
                      left: isAr
                          ? pw.BorderSide.none
                          : pw.BorderSide(color: brandColor, width: 3),
                    ),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        ksa,
                        style: st(base, 9, color: PdfColors.grey700),
                        maxLines: 1,
                      ),
                      pw.Text(
                        platformName,
                        style: st(bold, 12.5, color: brandColor),
                        maxLines: 1,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Directionality(
                        textDirection: pw.TextDirection.ltr,
                        child: pw.Text(
                          AppBranding.invoiceLetterheadPhone,
                          style: st(base, 8.5, color: PdfColors.grey800),
                          maxLines: 1,
                        ),
                      ),
                      pw.Directionality(
                        textDirection: pw.TextDirection.ltr,
                        child: pw.Text(
                          AppBranding.supportEmail,
                          style: st(base, 8.5, color: PdfColors.grey800),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          _pdfText(subtitle.trim()),
          style: st(base, 8, color: PdfColors.grey600),
          textAlign: pw.TextAlign.center,
        ),
      ],
      pw.SizedBox(height: 8),
      pw.Container(height: 1.4, color: brandColor),
      pw.SizedBox(height: 7),
      pw.Center(
        child: pw.Text(
          title,
          style: st(bold, 13, color: brandColor),
          textAlign: pw.TextAlign.center,
          maxLines: 2,
        ),
      ),
      if (!invoiceLayout && rightText.isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          rightText,
          style: st(base, 8, color: PdfColors.grey800),
          textAlign: pw.TextAlign.center,
          maxLines: 3,
        ),
      ],
      pw.SizedBox(height: 8),
    ],
  );
}

/// نص QR قابل للقراءة بالمسح — بيانات حقيقية لا قوالب.
String documentQrPlainText({
  required bool isAr,
  required String kind,
  String? invoiceNo,
  String? description,
  String? period,
  String? amountLine,
  String? status,
  String? paidAt,
  String? method,
  String? transactionId,
  int? rowCount,
}) {
  final b = StringBuffer();
  b.writeln(AppBranding.invoiceLetterheadBrandName(isAr: isAr));
  b.writeln(kind);
  if ((invoiceNo ?? '').trim().isNotEmpty) {
    b.writeln(isAr ? 'رقم: ${invoiceNo!.trim()}' : 'No: ${invoiceNo!.trim()}');
  }
  if ((description ?? '').trim().isNotEmpty) {
    b.writeln(description!.trim());
  }
  if ((period ?? '').trim().isNotEmpty) {
    b.writeln(isAr ? 'الفترة: ${period!.trim()}' : 'Period: ${period!.trim()}');
  }
  if ((amountLine ?? '').trim().isNotEmpty) {
    b.writeln(
      isAr ? 'المبلغ: ${amountLine!.trim()}' : 'Amount: ${amountLine!.trim()}',
    );
  }
  if ((status ?? '').trim().isNotEmpty) {
    b.writeln(isAr ? 'الحالة: ${status!.trim()}' : 'Status: ${status!.trim()}');
  }
  if ((method ?? '').trim().isNotEmpty) {
    b.writeln(isAr ? 'الدفع: ${method!.trim()}' : 'Pay: ${method!.trim()}');
  }
  if ((paidAt ?? '').trim().isNotEmpty) {
    b.writeln(InvoiceCopy.stripBidi(paidAt!.trim()));
  }
  final tx = (transactionId ?? '').trim();
  if (tx.isNotEmpty && !RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(tx)) {
    b.writeln(isAr ? 'مرجع: $tx' : 'Ref: $tx');
  }
  if (rowCount != null) {
    b.writeln(isAr ? 'عدد الصفوف: $rowCount' : 'Rows: $rowCount');
  }
  return InvoiceCopy.stripBidi(b.toString().trim());
}

String excelAmountCell(double amount, {required bool isAr}) =>
    AppMoney.formatForExport(amount, isAr: isAr, maxFractionDigits: 2);

List<String> excelLetterheadLines({
  required bool isAr,
  required String title,
}) {
  return [
    isAr ? 'بسم الله الرحمن الرحيم' : 'In the name of Allah',
    AppBranding.invoiceLetterheadBrandName(isAr: isAr),
    '${AppBranding.supportEmail} · ${AppBranding.invoiceLetterheadPhone}',
    title,
  ];
}
