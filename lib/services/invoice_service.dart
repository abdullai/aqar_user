import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../core/payment/invoice_copy.dart';
import '../core/payment/invoice_document.dart';
import '../core/utils/app_money.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';
import 'billing_transaction_repository.dart';
import 'payment_service.dart';

class InvoicePayerInfo {
  const InvoicePayerInfo({
    this.fullName,
    this.email,
    this.phone,
  });

  final String? fullName;
  final String? email;
  final String? phone;
}

/// خدمة الفواتير — PDF، طباعة، Excel، إخفاء. المصدر: billing_transactions.
class InvoiceService {
  InvoiceService({
    required this.repository,
    required this.isAr,
    SupabaseClient? supabase,
  }) : _sb = supabase ?? Supabase.instance.client;

  final BillingTransactionRepository repository;
  final bool isAr;
  final SupabaseClient _sb;

  InvoicePayerInfo? _cachedPayer;
  String? _cachedPayerUid;

  static InvoicePayerInfo? _staticPayer;
  static String? _staticPayerUid;

  static void forgetPayerCache() {
    _staticPayer = null;
    _staticPayerUid = null;
  }

  static String formatLatinDateTime(DateTime dt) =>
      PaymentService.formatLatinDateTime(dt);

  Future<InvoiceDocument> documentFor(Map<String, dynamic> row) async {
    return InvoiceDocument.fromRow(
      row,
      isAr: isAr,
      subscription: await _subscriptionFor(row),
    );
  }

  Future<Map<String, dynamic>?> _subscriptionFor(Map<String, dynamic> row) async {
    final id = '${row['subscription_id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    try {
      final rec = await _sb
          .from('user_subscriptions')
          .select('starts_at, ends_at, start_date, end_date, period, plan_id')
          .eq('id', id)
          .maybeSingle();
      if (rec == null) return null;
      return Map<String, dynamic>.from(rec);
    } catch (_) {
      return null;
    }
  }

  Future<InvoicePayerInfo> loadPayerInfo() async {
    final user = _sb.auth.currentUser;
    final uid = user?.id;
    if (user == null || uid == null) {
      forgetPayerCache();
      _cachedPayer = const InvoicePayerInfo();
      _cachedPayerUid = null;
      return _cachedPayer!;
    }
    if (_staticPayer != null && _staticPayerUid == uid) {
      _cachedPayer = _staticPayer;
      _cachedPayerUid = uid;
      return _cachedPayer!;
    }
    if (_cachedPayer != null && _cachedPayerUid == uid) return _cachedPayer!;
    String? name = ProfileGreetingFromRow.displayNameFromAuthMetadata(
      user.userMetadata,
    );
    String? phone;
    try {
      final profiles = await UsersProfilesSafeSelect.fetchProfilesByIds(
        _sb,
        [uid],
        columnAttempts: UsersProfilesSafeSelect.structuredLegalNameColumns,
      );
      final row = profiles[uid];
      if (row != null) {
        name = ProfileGreetingFromRow.displayName(row, isAr: isAr) ?? name;
        phone = '${row['phone'] ?? ''}'.trim();
        if (phone.isEmpty) phone = null;
      }
    } catch (_) {}
    final info = InvoicePayerInfo(
      fullName: name,
      email: user.email,
      phone: phone,
    );
    _cachedPayer = info;
    _cachedPayerUid = uid;
    _staticPayer = info;
    _staticPayerUid = uid;
    return info;
  }

  Future<Uint8List> buildPdf(
    Map<String, dynamic> row, {
    InvoicePayerInfo? payer,
  }) async {
    final p = payer ?? await loadPayerInfo();
    final doc = await documentFor(row);
    return PaymentService.buildInvoicePdf(
      title: doc.documentTitle,
      txnId: doc.hasInvoiceNumber ? doc.invoiceNumber : '',
      amountLine: doc.amountPdf(),
      statusLine: doc.statusLabel,
      footer: null,
      planName: doc.title,
      descriptionLabel: doc.statementLabel,
      periodLabel: doc.periodLabel,
      paymentMethod: doc.methodLabel,
      paidAtFormatted: doc.latinDateLine,
      calendarLine: doc.dateLine.isEmpty ? null : doc.latinDateLine,
      purposeLabel: doc.purposeLabel,
      userFullName: p.fullName,
      userEmail: p.email,
      userPhone: p.phone,
      invoiceDateFormatted: doc.hasInvoiceNumber
          ? InvoiceCopy.slashDate(doc.occurredAt ?? DateTime.now())
          : doc.latinDateLine,
      isAr: isAr,
      subtotalLine: doc.showSubtotal
          ? AppMoney.formatForPdf(doc.subtotal, isAr: isAr, currencyCode: doc.currency)
          : null,
      autoPayDiscountLine: doc.showAutoPayDiscount
          ? AppMoney.formatForPdf(
              doc.autoPayDiscountSar,
              isAr: isAr,
              currencyCode: doc.currency,
            )
          : null,
      autoPayDiscountLabel:
          doc.showAutoPayDiscount ? doc.autoPayDiscountLabel(isAr: isAr) : null,
      promoDiscountLine: doc.showPromoDiscount
          ? AppMoney.formatForPdf(
              doc.promoDiscountSar,
              isAr: isAr,
              currencyCode: doc.currency,
            )
          : null,
      promoDiscountLabel:
          doc.showPromoDiscount ? doc.promoDiscountLabel(isAr: isAr) : null,
      discountLine: doc.showCombinedDiscount
          ? AppMoney.formatForPdf(doc.discount, isAr: isAr, currencyCode: doc.currency)
          : null,
      discountLabel:
          doc.showCombinedDiscount ? doc.discountLabel(isAr: isAr) : null,
      vatLine: doc.showVat
          ? AppMoney.formatForPdf(doc.vat, isAr: isAr, currencyCode: doc.currency)
          : null,
      feesLine: doc.showFees
          ? AppMoney.formatForPdf(doc.fees, isAr: isAr, currencyCode: doc.currency)
          : null,
      refundLine: doc.showRefund
          ? AppMoney.formatForPdf(doc.refundAmount, isAr: isAr, currencyCode: doc.currency)
          : null,
      vatNote: null,
      paymentReference: doc.paymentReference,
      periodStart: null,
      periodEnd: null,
      currencyLabel: null,
      qrPayload: doc.qrPayload,
    );
  }

  String safeFileName(Map<String, dynamic> row) {
    return InvoiceDocument.fromRow(row, isAr: isAr).pdfFileName;
  }

  Future<void> downloadOrShare(Map<String, dynamic> row) async {
    final bytes = await buildPdf(row);
    final fileName = safeFileName(row);
    if (kIsWeb) {
      await Share.shareXFiles([
        XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
      ]);
    } else {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$fileName');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path)]);
    }
  }

  Future<void> printInvoice(Map<String, dynamic> row) async {
    try {
      await Printing.layoutPdf(
        name: safeFileName(row),
        onLayout: (_) => buildPdf(row),
      );
    } catch (_) {
      await downloadOrShare(row);
    }
  }

  Future<void> printAll(
    List<Map<String, dynamic>> rows, {
    String? tabTitleAr,
    String? tabTitleEn,
  }) async {
    if (rows.isEmpty) {
      await Printing.layoutPdf(
        name: 'no_invoices.pdf',
        onLayout: (_) => PaymentService.buildNoInvoicesPdf(
          isAr: isAr,
          titleAr: tabTitleAr,
          titleEn: tabTitleEn,
        ),
      );
      return;
    }
    final payer = await loadPayerInfo();
    final invoices = <Map<String, dynamic>>[];
    for (final row in rows) {
      final doc = await documentFor(row);
      invoices.add({
        'title': doc.title,
        'txnId': doc.hasInvoiceNumber ? doc.invoiceNumber : '',
        'amountLine': doc.amountPdf(),
        'statusLine': doc.statusLabel,
        'footer': isAr
            ? 'هذه الفاتورة إثبات داخل المنصة لعملية الدفع المعتمدة من الخادم.'
            : 'This invoice is platform proof of the server-confirmed payment.',
        'planName': doc.title,
        'descriptionLabel': doc.statementLabel,
        'periodLabel': doc.periodLabel,
        'paymentMethod': doc.methodLabel,
        'paidAtFormatted': doc.latinDateLine,
        'calendarLine': doc.dateLine,
        'purposeLabel': doc.purposeLabel,
        'userFullName': payer.fullName,
        'userEmail': payer.email,
        'userPhone': payer.phone,
        'invoiceDateFormatted': doc.latinDateLine,
        'subtotalLine': doc.showSubtotal
            ? AppMoney.formatForPdf(
                doc.subtotal,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'discountLine': doc.showCombinedDiscount
            ? AppMoney.formatForPdf(
                doc.discount,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'discountLabel': doc.showCombinedDiscount
            ? doc.discountLabel(isAr: isAr)
            : null,
        'autoPayDiscountLine': doc.showAutoPayDiscount
            ? AppMoney.formatForPdf(
                doc.autoPayDiscountSar,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'autoPayDiscountLabel': doc.showAutoPayDiscount
            ? doc.autoPayDiscountLabel(isAr: isAr)
            : null,
        'promoDiscountLine': doc.showPromoDiscount
            ? AppMoney.formatForPdf(
                doc.promoDiscountSar,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'promoDiscountLabel': doc.showPromoDiscount
            ? doc.promoDiscountLabel(isAr: isAr)
            : null,
        'vatLine': doc.showVat
            ? AppMoney.formatForPdf(doc.vat, isAr: isAr, currencyCode: doc.currency)
            : null,
        'feesLine': doc.showFees
            ? AppMoney.formatForPdf(
                doc.fees,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'refundLine': doc.showRefund
            ? AppMoney.formatForPdf(
                doc.refundAmount,
                isAr: isAr,
                currencyCode: doc.currency,
              )
            : null,
        'vatNote': null,
        'paymentReference': doc.paymentReference,
        'periodStart': null,
        'periodEnd': null,
        'currencyLabel': null,
        'qrPayload': doc.qrPayload,
      });
    }
    final stamp = DateTime.now().toUtc();
    final name =
        'Invoices_${stamp.year}-${stamp.month.toString().padLeft(2, '0')}.pdf';
    await Printing.layoutPdf(
      name: name,
      onLayout: (_) => PaymentService.buildInvoiceBookPdf(
        invoices: invoices,
        isAr: isAr,
      ),
    );
  }

  static Uint8List csvUtf8BomBytes(String csv) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

  Future<Map<String, dynamic>> archive(Map<String, dynamic> row) async {
    final id = '${row['id'] ?? ''}'.trim();
    if (id.isEmpty) return {'ok': false, 'error': 'no_id'};
    return repository.hideFromLedger(id);
  }

  Future<Map<String, dynamic>> delete(Map<String, dynamic> row) async {
    return archive(row);
  }

  Future<Map<String, dynamic>> hideFromLedger(Map<String, dynamic> row) async {
    return archive(row);
  }

  CellStyle _excelBorderedStyle({
    bool bold = false,
    ExcelColor? background,
    bool header = false,
    HorizontalAlign? align,
  }) {
    final thin = Border(borderStyle: BorderStyle.Thin);
    return CellStyle(
      bold: bold || header,
      fontColorHex: header ? ExcelColor.white : ExcelColor.black,
      backgroundColorHex: background ??
          (header ? ExcelColor.fromHexString('FF0F766E') : ExcelColor.white),
      horizontalAlign: align ??
          (isAr ? HorizontalAlign.Right : HorizontalAlign.Left),
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      textWrapping: TextWrapping.WrapText,
    );
  }

  void _excelText(
    Sheet sheet,
    int col,
    int row,
    String value,
    CellStyle style,
  ) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }

  void _excelNumber(
    Sheet sheet,
    int col,
    int row,
    double? value,
    CellStyle style,
  ) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    if (value == null) {
      cell.value = TextCellValue('');
    } else {
      cell.value = DoubleCellValue(value);
    }
    cell.cellStyle = style;
  }

  Future<Uint8List> exportAllExcel(
    List<Map<String, dynamic>> rows, {
    String? sectionTitle,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.sheets.keys.first;
    excel.rename(defaultSheet, isAr ? 'فواتير' : 'Invoices');
    final sheet = excel.sheets[isAr ? 'فواتير' : 'Invoices']!;
    sheet.isRTL = isAr;

    final headerStyle = _excelBorderedStyle(header: true);
    final bodyStyle = _excelBorderedStyle();
    final moneyStyle = _excelBorderedStyle(
      align: HorizontalAlign.Right,
    );
    final metaStyle = _excelBorderedStyle(
      background: ExcelColor.fromHexString('FFCCFBF1'),
    );
    final totalStyle = _excelBorderedStyle(
      bold: true,
      background: ExcelColor.fromHexString('FFECFDF5'),
    );

    String t(String ar, String en) => isAr ? ar : en;
    var r = 0;
    _excelText(sheet, 0, r, t('بسم الله الرحمن الرحيم', 'In the name of Allah'), metaStyle);
    r++;
    _excelText(sheet, 0, r, t('المملكة العربية السعودية', 'Kingdom of Saudi Arabia'), metaStyle);
    r++;
    _excelText(sheet, 0, r, AppBranding.invoiceLetterheadBrandName(isAr: isAr), metaStyle);
    r++;
    _excelText(
      sheet,
      0,
      r,
      '${t('جوال التواصل', 'Contact mobile')} ${AppBranding.invoiceLetterheadPhone}',
      metaStyle,
    );
    r++;
    _excelText(sheet, 0, r, AppBranding.supportEmail, metaStyle);
    r++;
    if (sectionTitle != null && sectionTitle.trim().isNotEmpty) {
      _excelText(sheet, 0, r, sectionTitle.trim(), metaStyle);
      r++;
    }
    _excelText(sheet, 0, r, formatLatinDateTime(DateTime.now()), metaStyle);
    r++;
    _excelText(
      sheet,
      0,
      r,
      '${t('عدد الفواتير', 'Invoice count')}: ${rows.length}',
      metaStyle,
    );
    r += 2;

    final docs = <InvoiceDocument>[];
    for (final row in rows) {
      docs.add(await documentFor(row));
    }
    final eligible = docs.where((d) => d.isEligibleRevenue()).toList();
    final refunded = docs.where((d) => d.isRefundedTab()).toList();
    if (eligible.isNotEmpty) {
      final sum = eligible.fold<double>(0, (a, d) => a + d.amount);
      _excelText(sheet, 0, r, t('إجمالي العمليات المؤهلة (مدفوعة)', 'Eligible paid total'), totalStyle);
      _excelNumber(sheet, 1, r, sum, totalStyle);
      _excelText(sheet, 2, r, isAr ? 'ريال' : 'Riyal', totalStyle);
      r++;
    }
    if (refunded.isNotEmpty) {
      final sum = refunded.fold<double>(
        0,
        (a, d) => a + (d.showRefund ? d.refundAmount : d.amount),
      );
      _excelText(sheet, 0, r, t('إجمالي المسترجع (ليس إيراداً)', 'Refunded total (not revenue)'), totalStyle);
      _excelNumber(sheet, 1, r, sum, totalStyle);
      _excelText(sheet, 2, r, isAr ? 'ريال' : 'Riyal', totalStyle);
      r++;
    }
    r++;

    final payer = await loadPayerInfo();
    if (payer.fullName != null ||
        payer.email != null ||
        (payer.phone ?? '').trim().isNotEmpty) {
      _excelText(sheet, 0, r, AppBranding.invoicePartnerLabel(isAr: isAr), headerStyle);
      _excelText(sheet, 1, r, payer.fullName ?? '', bodyStyle);
      _excelText(sheet, 2, r, payer.email ?? '', bodyStyle);
      _excelText(sheet, 3, r, payer.phone ?? '', bodyStyle);
      r += 2;
    }

    final headers = isAr
        ? [
            'رقم الفاتورة',
            'التاريخ',
            'البيان',
            'نوع العملية',
            'الفترة',
            'قبل الخصم',
            'خصم الدفع التلقائي',
            'نسبة التلقائي',
            'كود الخصم',
            'خصم الكود',
            'إجمالي الخصم',
            'بيان الخصم',
            'الضريبة',
            'الرسوم',
            'الإجمالي',
            'العملة',
            'الحالة',
            'طريقة الدفع',
            'مرجع الدفع',
            'بداية الاشتراك',
            'نهاية الاشتراك',
            'المسترجع',
          ]
        : [
            'Invoice number',
            'Date',
            'Description',
            'Purpose',
            'Period',
            'Subtotal',
            'Auto-pay discount',
            'Auto-pay %',
            'Promo code',
            'Promo discount',
            'Total discount',
            'Discount label',
            'VAT',
            'Fees',
            'Total',
            'Currency',
            'Status',
            'Payment method',
            'Payment reference',
            'Subscription start',
            'Subscription end',
            'Refunded',
          ];
    for (var c = 0; c < headers.length; c++) {
      _excelText(sheet, c, r, headers[c], headerStyle);
    }
    final headerRow = r;
    r++;

    for (final doc in docs) {
      _excelText(sheet, 0, r, doc.hasInvoiceNumber ? doc.invoiceNumber : '', bodyStyle);
      _excelText(sheet, 1, r, doc.latinDateLine, bodyStyle);
      _excelText(sheet, 2, r, doc.title, bodyStyle);
      _excelText(sheet, 3, r, doc.purposeLabel, bodyStyle);
      _excelText(sheet, 4, r, doc.periodLabel, bodyStyle);
      _excelNumber(sheet, 5, r, doc.showSubtotal ? doc.subtotal : null, moneyStyle);
      _excelNumber(
        sheet,
        6,
        r,
        doc.autoPayDiscountSar > 0.009 ? doc.autoPayDiscountSar : null,
        moneyStyle,
      );
      _excelNumber(
        sheet,
        7,
        r,
        doc.autoPayDiscountPct > 0.009 ? doc.autoPayDiscountPct : null,
        moneyStyle,
      );
      _excelText(sheet, 8, r, doc.promoCode ?? '', bodyStyle);
      _excelNumber(
        sheet,
        9,
        r,
        doc.promoDiscountSar > 0.009 ? doc.promoDiscountSar : null,
        moneyStyle,
      );
      _excelNumber(sheet, 10, r, doc.showDiscount ? doc.discount : null, moneyStyle);
      _excelText(
        sheet,
        11,
        r,
        doc.showDiscount ? doc.discountLabel(isAr: isAr) : '',
        bodyStyle,
      );
      _excelNumber(sheet, 12, r, doc.showVat ? doc.vat : null, moneyStyle);
      _excelNumber(sheet, 13, r, doc.showFees ? doc.fees : null, moneyStyle);
      _excelNumber(sheet, 14, r, doc.amount, moneyStyle);
      _excelText(sheet, 15, r, doc.currency, bodyStyle);
      _excelText(sheet, 16, r, doc.statusLabel, bodyStyle);
      _excelText(sheet, 17, r, doc.methodLabel, bodyStyle);
      _excelText(sheet, 18, r, doc.paymentReference ?? '', bodyStyle);
      _excelText(sheet, 19, r, doc.subscriptionStart ?? '', bodyStyle);
      _excelText(sheet, 20, r, doc.subscriptionEnd ?? '', bodyStyle);
      _excelNumber(sheet, 21, r, doc.showRefund ? doc.refundAmount : null, moneyStyle);
      r++;
    }

    final widths = <int, double>{
      0: 22,
      1: 18,
      2: 34,
      3: 18,
      4: 14,
      5: 12,
      6: 16,
      7: 12,
      8: 14,
      9: 14,
      10: 14,
      11: 22,
      12: 12,
      13: 12,
      14: 14,
      15: 10,
      16: 16,
      17: 16,
      18: 22,
      19: 20,
      20: 20,
      21: 12,
    };
    for (final e in widths.entries) {
      sheet.setColumnWidth(e.key, e.value);
    }
    sheet.setRowHeight(headerRow, 22);

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? const <int>[]);
  }

  Future<String> exportAllCsv(
    List<Map<String, dynamic>> rows, {
    String? sectionTitle,
  }) async {
    final buf = StringBuffer();
    final now = formatLatinDateTime(DateTime.now());
    buf.writeln('"${isAr ? 'بسم الله الرحمن الرحيم' : 'In the name of Allah'}"');
    for (final line in excelLetterheadLines(
      isAr: isAr,
      title: sectionTitle ?? (isAr ? 'سجل الفواتير' : 'Invoice ledger'),
    )) {
      buf.writeln('"${line.replaceAll('"', '""')}"');
    }
    buf.writeln('"$now"');
    buf.writeln('');
    buf.writeln(
      isAr
          ? 'رقم الفاتورة,التاريخ,البيان,الإجمالي,العملة,الحالة,طريقة الدفع'
          : 'Invoice number,Date,Description,Amount,Currency,Status,Payment method',
    );
    for (final row in rows) {
      final doc = await documentFor(row);
      buf.writeln(
        [
          '"${doc.invoiceNumber}"',
          '"${doc.latinDateLine}"',
          '"${doc.title.replaceAll('"', '""')}"',
          '${doc.amount}',
          '"${doc.currency}"',
          '"${doc.statusLabel}"',
          '"${doc.methodLabel}"',
        ].join(','),
      );
    }
    return buf.toString();
  }
}
