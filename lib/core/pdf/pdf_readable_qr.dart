import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// كتلة QR للـ PDF بنفس أسلوب الفاتورة: إطار أبيض، منطقة هادئة، تسمية ثنائية اللغة.
pw.Widget pdfReadableQrBlock({
  required String data,
  required bool isAr,
  pw.Font? font,
  pw.Font? fontBold,
  double size = 112,
  String? title,
  String? hint,
  PdfColor brandColor = PdfColors.teal800,
}) {
  final resolvedTitle =
      title ?? (isAr ? 'رمز الاستجابة السريعة' : 'QR verification');
  final resolvedHint = hint ??
      (isAr
          ? 'امسح الرمز للتحقق من صحة المستند'
          : 'Scan to verify this document');

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          resolvedTitle,
          style: pw.TextStyle(
            font: fontBold ?? font,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: brandColor,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          color: PdfColors.white,
          padding: const pw.EdgeInsets.all(10),
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: data,
            width: size,
            height: size,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          resolvedHint,
          style: pw.TextStyle(
            font: font,
            fontSize: 7.5,
            color: PdfColors.grey700,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ),
  );
}
