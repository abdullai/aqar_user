import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

import 'package:printing/printing.dart';

import 'package:share_plus/share_plus.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



import '../core/branding/app_branding.dart';

import '../core/utils/app_money.dart';

import '../core/utils/profile_greeting_from_row.dart';

import '../core/utils/users_profiles_safe_select.dart';

import 'billing_transaction_repository.dart';

import 'payment_service.dart';



/// بيانات شريكنا العقاري للفاتورة.

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



/// خدمة الفواتير — PDF، طباعة، مشاركة، أرشفة.

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



  /// أرقام لاتينية دائماً في التاريخ والوقت.

  static String formatLatinDateTime(DateTime dt) =>

      PaymentService.formatLatinDateTime(dt);



  String _titleFor(Map<String, dynamic> row) {

    final raw = isAr
        ? '${row['title_ar'] ?? row['title_en'] ?? '—'}'
        : '${row['title_en'] ?? row['title_ar'] ?? '—'}';
    final t = AppBranding.billingDisplayTitle(rawTitle: raw, isAr: isAr);

    if (t == '—' || t.isEmpty) {

      return isAr ? 'إيصال دفع' : 'Payment receipt';

    }

    return t;

  }



  String _amountLine(Map<String, dynamic> row) {

    final raw = row['amount'];

    final v = raw is num

        ? raw.toDouble()

        : double.tryParse('${raw ?? ''}') ?? 0.0;

    final cur = '${row['currency'] ?? 'SAR'}'.toUpperCase();

    return AppMoney.formatWithCurrencyCode(

      v,

      isAr: isAr,

      currencyCode: cur,

      maxFractionDigits: 2,

    );

  }



  String _statusLabel(Map<String, dynamic> row) {

    switch (BillingTransactionRepository.normalizedStatus(row)) {

      case 'success':

        return isAr ? 'مكتملة' : 'Completed';

      case 'pending':

        return isAr ? 'قيد المعالجة' : 'Pending';

      case 'failed':

        return isAr ? 'فاشلة' : 'Failed';

      default:

        return isAr ? 'غير معروف' : 'Unknown';

    }

  }



  String? _paidAtFor(Map<String, dynamic> row) {

    final c = row['completed_at'] ?? row['created_at'];

    final dt = DateTime.tryParse('$c');

    if (dt == null) return null;

    return formatLatinDateTime(dt);

  }



  Future<InvoicePayerInfo> loadPayerInfo() async {

    if (_cachedPayer != null) return _cachedPayer!;

    final user = _sb.auth.currentUser;

    if (user == null) {

      _cachedPayer = const InvoicePayerInfo();

      return _cachedPayer!;

    }

    String? name = ProfileGreetingFromRow.displayNameFromAuthMetadata(

      user.userMetadata,

    );

    String? phone;

    try {

      final profiles = await UsersProfilesSafeSelect.fetchProfilesByIds(

        _sb,

        [user.id],

        columnAttempts: UsersProfilesSafeSelect.structuredLegalNameColumns,

      );

      final row = profiles[user.id];

      if (row != null) {

        name = ProfileGreetingFromRow.displayName(row, isAr: isAr) ?? name;

        phone = '${row['phone'] ?? ''}'.trim();

        if (phone.isEmpty) phone = null;

      }

    } catch (_) {}

    _cachedPayer = InvoicePayerInfo(

      fullName: name,

      email: user.email,

      phone: phone,

    );

    return _cachedPayer!;

  }



  Future<Uint8List> buildPdf(

    Map<String, dynamic> row, {

    InvoicePayerInfo? payer,

  }) async {

    final p = payer ?? await loadPayerInfo();

    final ref = BillingTransactionRepository.latinReference(row);

    final title = _titleFor(row);

    return PaymentService.buildInvoicePdf(

      title: title,

      txnId: ref,

      amountLine: _amountLine(row),

      statusLine: _statusLabel(row),

      footer: isAr

          ? 'هذه الفاتورة لأغراض الإثبات داخل المنصة فقط.'

          : 'For platform proof only.',

      planName: () {

        final t = _titleFor(row);

        return (t == '—' || t.isEmpty) ? null : t;

      }(),

      paymentMethod: '${row['payment_method'] ?? ''}'.trim().isEmpty

          ? null

          : row['payment_method'].toString(),

      paidAtFormatted: _paidAtFor(row),

      subscriptionId: '${row['subscription_id'] ?? ''}'.trim().isEmpty

          ? null

          : row['subscription_id'].toString(),

      userFullName: p.fullName,

      userEmail: p.email,

      userPhone: p.phone,

      invoiceDateFormatted: formatLatinDateTime(DateTime.now()),

      isAr: isAr,

    );

  }



  String safeFileName(Map<String, dynamic> row) {

    final ref = BillingTransactionRepository.latinReference(row);

    return 'invoice_$ref.pdf';

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



  String _paymentMethodLabel(String raw) {
    final m = raw.trim().toLowerCase();
    if (m.isEmpty) return isAr ? 'غير محدد' : 'Not specified';
    switch (m) {
      case 'card':
        return isAr ? 'بطاقة' : 'Card';
      case 'mada_pay':
        return isAr ? 'مدى' : 'mada';
      case 'google_pay':
        return 'Google Pay';
      case 'apple_pay':
        return 'Apple Pay';
      case 'web_pay':
        return isAr ? 'محفظة المتصفح' : 'Browser wallet';
      default:
        return raw;
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

    final reportRows = rows.map((row) {
      final dt = DateTime.tryParse('${row['created_at']}');
      return {
        'ref': BillingTransactionRepository.latinReference(row),
        'date': dt != null ? formatLatinDateTime(dt) : '',
        'title': _titleFor(row),
        'amount': _amountLine(row),
        'status': _statusLabel(row),
        'method': _paymentMethodLabel('${row['payment_method'] ?? ''}'),
      };
    }).toList();

    await Printing.layoutPdf(
      name: 'invoices_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      onLayout: (_) => PaymentService.buildInvoicesReportPdf(
        rows: reportRows,
        isAr: isAr,
        generatedAtFormatted: formatLatinDateTime(DateTime.now()),
        reportTitleAr: tabTitleAr,
        reportTitleEn: tabTitleEn,
      ),
    );
  }

  String _amountLineForExport(Map<String, dynamic> row) {
    final raw = row['amount'];
    final v = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}') ?? 0.0;
    final cur = '${row['currency'] ?? 'SAR'}'.toUpperCase();
    return AppMoney.formatForExport(
      v,
      isAr: isAr,
      currencyCode: cur,
      maxFractionDigits: 2,
    );
  }

  /// يمنع Excel من تحويل الأرقام الطويلة إلى صيغة علمية.
  static String _csvTextCell(String raw) {
    final s = raw.replaceAll('"', '""').trim();
    if (s.isEmpty) return '""';
    return '"\t$s"';
  }

  CellStyle _excelBorderedStyle({
    bool bold = false,
    ExcelColor? background,
    bool header = false,
  }) {
    final thin = Border(borderStyle: BorderStyle.Thin);
    return CellStyle(
      bold: bold || header,
      fontColorHex: header ? ExcelColor.white : ExcelColor.black,
      backgroundColorHex: background ??
          (header ? ExcelColor.fromHexString('FF1A237E') : ExcelColor.white),
      horizontalAlign:
          isAr ? HorizontalAlign.Right : HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      textWrapping: TextWrapping.WrapText,
    );
  }

  void _excelSetCell(
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
    final metaStyle = _excelBorderedStyle(
      background: ExcelColor.fromHexString('FFE8EAF6'),
    );

    var r = 0;
    _excelSetCell(sheet, 0, r, '﷽', metaStyle);
    r++;
    _excelSetCell(sheet, 0, r, AppBranding.legalName(isAr: isAr), metaStyle);
    r++;
    _excelSetCell(
      sheet,
      0,
      r,
      AppBranding.legalNoticeLine(isAr: isAr),
      metaStyle,
    );
    r++;
    _excelSetCell(
      sheet,
      0,
      r,
      '${AppBranding.supportEmail} · ${AppBranding.supportPhone}',
      metaStyle,
    );
    r++;
    if (sectionTitle != null && sectionTitle.trim().isNotEmpty) {
      _excelSetCell(sheet, 0, r, sectionTitle.trim(), metaStyle);
      r++;
    }
    _excelSetCell(sheet, 0, r, formatLatinDateTime(DateTime.now()), metaStyle);
    r += 2;

    final payer = await loadPayerInfo();
    if (payer.fullName != null ||
        payer.email != null ||
        (payer.phone ?? '').trim().isNotEmpty) {
      final partnerLabel = AppBranding.invoicePartnerLabel(isAr: isAr);
      _excelSetCell(sheet, 0, r, partnerLabel, headerStyle);
      _excelSetCell(sheet, 1, r, payer.fullName ?? '', bodyStyle);
      _excelSetCell(sheet, 2, r, payer.email ?? '', bodyStyle);
      _excelSetCell(sheet, 3, r, payer.phone ?? '', bodyStyle);
      r += 2;
    }

    final headers = isAr
        ? [
            'رقم العملية',
            'التاريخ',
            'البيان',
            'المبلغ',
            'الحالة',
            'طريقة الدفع',
          ]
        : [
            'Reference',
            'Date',
            'Description',
            'Amount',
            'Status',
            'Payment Method',
          ];
    for (var c = 0; c < headers.length; c++) {
      _excelSetCell(sheet, c, r, headers[c], headerStyle);
    }
    r++;

    for (final row in rows) {
      final dt = DateTime.tryParse('${row['created_at']}');
      final date = dt != null ? formatLatinDateTime(dt) : '';
      final ref = BillingTransactionRepository.latinReference(row);
      final title = _titleFor(row);
      final amt = _amountLineForExport(row);
      final st = _statusLabel(row);
      final method = _paymentMethodLabel('${row['payment_method'] ?? ''}');
      final values = [ref, date, title, amt, st, method];
      for (var c = 0; c < values.length; c++) {
        _excelSetCell(sheet, c, r, values[c], bodyStyle);
      }
      r++;
    }

    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 34);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 16);

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? const <int>[]);
  }

  /// CSV بترميز UTF-8 مع BOM لفتح صحيح في Excel (عربي).
  static Uint8List csvUtf8BomBytes(String csv) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);



  Future<Map<String, dynamic>> archive(Map<String, dynamic> row) async {

    final id = '${row['id'] ?? ''}'.trim();

    if (id.isEmpty) return {'ok': false, 'error': 'no_id'};

    return repository.archive(id);

  }



  Future<Map<String, dynamic>> delete(Map<String, dynamic> row) async {

    final id = '${row['id'] ?? ''}'.trim();

    if (id.isEmpty) return {'ok': false, 'error': 'no_id'};

    return repository.delete(id);

  }



  Future<String> exportAllCsv(
    List<Map<String, dynamic>> rows, {
    String? sectionTitle,
  }) async {
    final buf = StringBuffer();
    final now = formatLatinDateTime(DateTime.now());
    buf.writeln('"﷽"');
    buf.writeln('"${AppBranding.legalName(isAr: isAr)}"');
    buf.writeln('"${AppBranding.legalName(isAr: !isAr)}"');
    buf.writeln('"${AppBranding.legalNoticeLine(isAr: isAr)}"');
    buf.writeln(
      isAr
          ? '"${AppBranding.supportEmail}","${AppBranding.supportPhone}"'
          : '"${AppBranding.supportEmail}","${AppBranding.supportPhone}"',
    );
    if (sectionTitle != null && sectionTitle.trim().isNotEmpty) {
      buf.writeln('"$sectionTitle"');
    }
    buf.writeln('"$now"');

    buf.writeln('');



    final payer = await loadPayerInfo();

    if (payer.fullName != null || payer.email != null) {

      buf.writeln(

        '${_csvTextCell(AppBranding.invoicePartnerLabel(isAr: isAr))},'
        '${_csvTextCell(payer.fullName ?? '')},'
        '"${(payer.email ?? '').replaceAll('"', '""')}",'
        '${_csvTextCell(payer.phone ?? '')}',

      );

      buf.writeln('');

    }



    buf.writeln(

      isAr

          ? 'رقم العملية,التاريخ,البيان,المبلغ,الحالة,طريقة الدفع'

          : 'Reference,Date,Description,Amount,Status,Payment Method',

    );

    for (final r in rows) {

      final dt = DateTime.tryParse('${r['created_at']}');

      final date = dt != null ? formatLatinDateTime(dt) : '';

      final ref = BillingTransactionRepository.latinReference(r);

      final title = _titleFor(r).replaceAll('"', '""');

      final amt = _amountLineForExport(r);

      final st = _statusLabel(r);

      final method = _paymentMethodLabel('${r['payment_method'] ?? ''}');

      buf.writeln(
        '${_csvTextCell(ref)},'
        '"$date",'
        '"$title",'
        '"$amt",'
        '"$st",'
        '"$method"',
      );

    }

    return buf.toString();

  }

}

