import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../branding/app_branding.dart';
import '../branding/branding_pdf.dart';
import '../pdf/pdf_readable_qr.dart';
import '../utils/app_money.dart';
import 'invoice_copy.dart';

/// صفحة فاتورة واحدة — بدون MultiPage حتى لا تنقسم الفاتورة على صفحتين.
void addOfficialInvoicePage({
  required pw.Document doc,
  required pw.Font base,
  required pw.Font bold,
  required List<pw.Font> fontFallback,
  required pw.ImageProvider? logo,
  required String title,
  required String txnId,
  required String amountLine,
  required String statusLine,
  String? footer,
  String? planName,
  String? descriptionLabel,
  String? periodLabel,
  String? paymentMethod,
  String? paidAtFormatted,
  String? payerName,
  String? purposeLabel,
  String? userFullName,
  String? userEmail,
  String? userPhone,
  String? invoiceDateFormatted,
  String? calendarLine,
  required bool isAr,
  String? subtotalLine,
  String? discountLine,
  String? discountLabel,
  String? autoPayDiscountLine,
  String? autoPayDiscountLabel,
  String? promoDiscountLine,
  String? promoDiscountLabel,
  String? vatLine,
  String? feesLine,
  String? refundLine,
  String? vatNote,
  String? paymentReference,
  String? periodStart,
  String? periodEnd,
  String? currencyLabel,
  String? qrPayload,
  String? riyalSvg,
}) {
  String t(String ar, String en) => isAr ? ar : en;
  String safe(String? v) => InvoiceCopy.stripBidi((v ?? '').trim());
  pw.TextStyle st(pw.Font f, double size, {PdfColor? color}) => pw.TextStyle(
        font: f,
        fontSize: size,
        color: color,
        fontFallback: fontFallback,
        height: 1.25,
      );

  final issuedAt = safe(
    invoiceDateFormatted ??
        InvoiceCopy.latinDateTime(DateTime.now()),
  );
  final invoiceNo = safe(txnId);
  final clientName = safe(userFullName ?? payerName);
  final clientEmail = safe(userEmail);
  final clientPhone = safe(userPhone);
  final plan = safe(planName ?? title);
  final statement = () {
    final custom = safe(descriptionLabel);
    if (custom.isNotEmpty) return custom;
    return InvoiceCopy.statementForPlan(plan, isAr: isAr);
  }();
  final linePeriod = safe(periodLabel).isEmpty
      ? t('حسب العملية', 'Per transaction')
      : safe(periodLabel);
  final status = safe(statusLine);
  final method = safe(paymentMethod);
  final purpose = safe(purposeLabel);
  final amount = _pdfMoneyLine(safe(amountLine));
  final qrData = safe(qrPayload).isNotEmpty
      ? safe(qrPayload)
      : documentQrPlainText(
          isAr: isAr,
          kind: safe(title).isNotEmpty ? safe(title) : t('فاتورة', 'INVOICE'),
          invoiceNo: invoiceNo,
          description: statement,
          period: linePeriod,
          amountLine: amount,
          status: status,
          paidAt: safe(calendarLine).isNotEmpty
              ? safe(calendarLine)
              : safe(paidAtFormatted).isNotEmpty
                  ? safe(paidAtFormatted)
                  : issuedAt,
          method: method,
        );

  pw.Widget moneyCell(String raw, {bool emphasize = false}) {
    final n = AppMoney.stripSarMarks(safe(raw)).trim();
    final style = st(
      emphasize ? bold : base,
      emphasize ? 11 : 9,
      color: emphasize ? kDocumentBrandPdfColor : PdfColors.black,
    );
    final svg = (riyalSvg ?? '').trim();
    final icon = svg.isEmpty
        ? pw.Text(AppMoney.saudiRiyalSignCompat, style: style)
        : pw.SvgImage(svg: svg, width: 11, height: 9);
    if (!isAr) {
      return pw.Text('$n SAR', style: style);
    }
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(n, style: style),
          icon,
        ],
      ),
    );
  }

  pw.Widget moneyRow(String label, String value, {bool emphasize = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              safe(label),
              style: st(emphasize ? bold : base, emphasize ? 10 : 8.5),
              maxLines: 1,
            ),
          ),
          moneyCell(value, emphasize: emphasize),
        ],
      ),
    );
  }

  pw.Widget chip(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFCCFBF1),
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: kDocumentBrandPdfColor, width: 0.55),
      ),
      child: pw.Text(
        '$label: $value',
        style: st(bold, 8.5, color: kDocumentBrandPdfColor),
        maxLines: 1,
      ),
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 22, 30, 22),
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        fontFallback: fontFallback,
      ),
      build: (ctx) {
        return pw.Directionality(
          textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              brandingPdfHeader(
                base: base,
                bold: bold,
                logo: logo,
                isAr: isAr,
                docTitle: safe(title).isNotEmpty
                    ? safe(title)
                    : t('فاتورة', 'Invoice'),
                brandColor: kDocumentBrandPdfColor,
                metaLine: '${t('التاريخ', 'Date')}: $issuedAt',
                fontFallback: fontFallback,
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          t('رقم الفاتورة', 'Invoice number'),
                          style: st(base, 8, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 2),
                        if (invoiceNo.isNotEmpty)
                          pw.Directionality(
                            textDirection: pw.TextDirection.ltr,
                            child: pw.Text(
                              invoiceNo,
                              style: st(
                                bold,
                                20,
                                color: kDocumentBrandPdfColor,
                              ),
                              maxLines: 1,
                            ),
                          )
                        else
                          pw.Text(
                            t('رقم غير متوفر', 'Number unavailable'),
                            style: st(bold, 11),
                          ),
                        if (purpose.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '${t('نوع العملية', 'Purpose')}: $purpose',
                            style: st(bold, 9.5),
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.Row(
                    children: [
                      if (status.isNotEmpty)
                        chip(t('الحالة', 'Status'), status),
                      if (status.isNotEmpty && method.isNotEmpty)
                        pw.SizedBox(width: 6),
                      if (method.isNotEmpty)
                        chip(t('طريقة الدفع', 'Payment'), method),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              if (clientName.isNotEmpty ||
                  clientEmail.isNotEmpty ||
                  clientPhone.isNotEmpty)
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF8FAFC),
                    border:
                        pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        AppBranding.invoicePartnerSectionTitle(isAr: isAr),
                        style: st(bold, 11, color: kDocumentBrandPdfColor),
                        textAlign: pw.TextAlign.center,
                      ),
                      if (clientName.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          clientName,
                          style: st(bold, 11),
                          textAlign: pw.TextAlign.center,
                          maxLines: 2,
                        ),
                      ],
                      if (clientEmail.isNotEmpty || clientPhone.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        if (clientEmail.isNotEmpty)
                          pw.Row(
                            children: [
                              pw.SizedBox(
                                width: 88,
                                child: pw.Text(
                                  t('البريد الإلكتروني', 'Email'),
                                  style: st(base, 8, color: PdfColors.grey700),
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Directionality(
                                  textDirection: pw.TextDirection.ltr,
                                  child: pw.Text(
                                    clientEmail,
                                    style: st(base, 9),
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (clientPhone.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          pw.Row(
                            children: [
                              pw.SizedBox(
                                width: 88,
                                child: pw.Text(
                                  t('الجوال', 'Mobile'),
                                  style: st(base, 8, color: PdfColors.grey700),
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Directionality(
                                  textDirection: pw.TextDirection.ltr,
                                  child: pw.Text(
                                    clientPhone,
                                    style: st(base, 9),
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              if (clientName.isNotEmpty ||
                  clientEmail.isNotEmpty ||
                  clientPhone.isNotEmpty)
                pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.45,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(1.6),
                  2: const pw.FlexColumnWidth(1.0),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: kDocumentBrandPdfColor,
                    ),
                    children: [
                      _th(t('البيان', 'Description'), st(bold, 8.5, color: PdfColors.white), isAr),
                      _th(t('الفترة', 'Period'), st(bold, 8.5, color: PdfColors.white), isAr),
                      _th(t('المبلغ', 'Amount'), st(bold, 8.5, color: PdfColors.white), isAr),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _td(statement, st(base, 8.5), isAr),
                      _td(linePeriod, st(base, 8), isAr, center: true),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 7,
                        ),
                        child: pw.Center(child: moneyCell(amount)),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment:
                    isAr ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
                child: pw.SizedBox(
                  width: 250,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: kDocumentBrandPdfColor,
                        width: 0.7,
                      ),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Column(
                      children: [
                        if (subtotalLine != null &&
                            subtotalLine.trim().isNotEmpty)
                          moneyRow(
                            t('قبل الخصم', 'Before discount'),
                            subtotalLine,
                          ),
                        if (autoPayDiscountLine != null)
                          moneyRow(
                            safe(autoPayDiscountLabel).isNotEmpty
                                ? autoPayDiscountLabel!
                                : InvoiceCopy.autoRenewDiscountLabel(
                                    isAr: isAr,
                                  ),
                            autoPayDiscountLine,
                          ),
                        if (promoDiscountLine != null)
                          moneyRow(
                            safe(promoDiscountLabel).isNotEmpty
                                ? promoDiscountLabel!
                                : InvoiceCopy.promoCodeDiscountLabel(
                                    isAr: isAr,
                                  ),
                            promoDiscountLine,
                          ),
                        if (discountLine != null &&
                            autoPayDiscountLine == null &&
                            promoDiscountLine == null)
                          moneyRow(
                            safe(discountLabel).isNotEmpty
                                ? discountLabel!
                                : t('الخصم', 'Discount'),
                            discountLine,
                          ),
                        if (vatLine != null)
                          moneyRow(t('الضريبة', 'VAT'), vatLine),
                        if (feesLine != null)
                          moneyRow(t('الرسوم', 'Fees'), feesLine),
                        if (refundLine != null)
                          moneyRow(t('المسترجع', 'Refunded'), refundLine),
                        moneyRow(
                          t('الإجمالي النهائي', 'Final total'),
                          amountLine,
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (safe(calendarLine).isNotEmpty ||
                  safe(paidAtFormatted).isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  '${t('تاريخ العملية', 'Transaction date')}: ${safe(calendarLine).isNotEmpty ? safe(calendarLine) : safe(paidAtFormatted)}',
                  style: st(base, 8.5, color: PdfColors.grey800),
                  maxLines: 1,
                ),
              ],
              if (safe(paymentReference).isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Text(
                    '${t('مرجع الدفع', 'Payment reference')}: ${safe(paymentReference)}',
                    style: st(base, 8, color: PdfColors.grey700),
                    maxLines: 1,
                  ),
                ),
              ],
              pw.SizedBox(height: 10),
              pw.Center(
                child: pdfReadableQrBlock(
                  data: qrData,
                  isAr: isAr,
                  font: base,
                  fontBold: bold,
                  size: 78,
                  title: t('رمز التحقق من الفاتورة', 'Invoice verification QR'),
                  hint: invoiceNo.isEmpty
                      ? t(
                          'امسح الرمز لبيانات الفاتورة',
                          'Scan to read invoice fields',
                        )
                      : invoiceNo,
                  brandColor: kDocumentBrandPdfColor,
                ),
              ),
              if (footer != null && footer.trim().isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  safe(footer),
                  style: st(base, 7.5, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                ),
              ],
              pw.Spacer(),
              pw.Container(height: 0.6, color: PdfColors.grey400),
              pw.SizedBox(height: 5),
              pw.Text(
                AppBranding.copyrightLine(isAr: isAr),
                style: st(base, 7, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
                maxLines: 1,
              ),
            ],
          ),
        );
      },
    ),
  );
}

pw.Widget _th(String text, pw.TextStyle style, bool isAr) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(
      text,
      style: style,
      textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
      maxLines: 1,
    ),
  );
}

pw.Widget _td(
  String text,
  pw.TextStyle style,
  bool isAr, {
  bool center = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    child: pw.Text(
      InvoiceCopy.stripBidi(text),
      style: style,
      textAlign: center
          ? pw.TextAlign.center
          : (isAr ? pw.TextAlign.right : pw.TextAlign.left),
      maxLines: 3,
    ),
  );
}

String _pdfMoneyLine(String raw) {
  final n = AppMoney.stripSarMarks(InvoiceCopy.stripBidi(raw)).trim();
  if (n.isEmpty) return raw;
  return '$n ${AppMoney.saudiRiyalSignCompat}';
}

Future<String?> loadInvoiceRiyalSvg() async {
  try {
    final s =
        await rootBundle.loadString('assets/currency/saudi_riyal_symbol.svg');
    return s.replaceAll('currentColor', '#0F766E');
  } catch (_) {
    return null;
  }
}
