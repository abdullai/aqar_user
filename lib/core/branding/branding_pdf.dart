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

/// ترويسة موحّدة لكل PDF (فواتير، تقارير، طباعة).
/// البسملة في الوسط، الشعار تحتها في الوسط، وبيانات الشركة/المستند يميناً ويساراً.
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
  List<pw.Font>? fontFallback,
}) {
  final platformName = AppBranding.invoiceLetterheadBrandName(isAr: isAr);
  final shortBrand = AppBranding.brandName(isAr: isAr);
  final ksa = isAr ? 'المملكة العربية السعودية' : 'Kingdom of Saudi Arabia';
  const contact =
      '${AppBranding.supportEmail}\n${AppBranding.invoiceLetterheadPhone}';
  pw.TextStyle st(pw.Font f, double size, {PdfColor? color}) => pw.TextStyle(
        font: f,
        fontSize: size,
        color: color,
        fontFallback: fontFallback ?? const <pw.Font>[],
        height: 1.25,
      );

  final logoBox = pw.Container(
    width: 62,
    height: 62,
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

  final leftText = _pdfText(
    (leftMeta ?? '').trim().isNotEmpty
        ? leftMeta!.trim()
        : '$ksa\n$platformName',
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
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Directionality(
                textDirection:
                    isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                child: pw.Text(
                  leftText,
                  style: st(base, 8, color: PdfColors.grey800),
                  textAlign: pw.TextAlign.start,
                  maxLines: 4,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10),
              child: logoBox,
            ),
            pw.Expanded(
              child: pw.Directionality(
                textDirection:
                    isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      title,
                      style: st(bold, 11, color: brandColor),
                      textAlign: pw.TextAlign.end,
                      maxLines: 2,
                    ),
                    if (rightText.isNotEmpty)
                      pw.Text(
                        rightText,
                        style: st(base, 8, color: PdfColors.grey800),
                        textAlign: pw.TextAlign.end,
                        maxLines: 3,
                      ),
                    pw.Text(
                      _pdfText(contact),
                      style: st(base, 7.5, color: PdfColors.grey700),
                      textAlign: pw.TextAlign.end,
                      maxLines: 2,
                    ),
                  ],
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
