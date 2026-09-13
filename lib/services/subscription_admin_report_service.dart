import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_pdf.dart';
import '../core/utils/date_helper.dart';
import '../core/payment/invoice_copy.dart';

/// تقارير اشتراكات ومدفوعات لموظفي المنصة (RLS: `*_staff_read`).
class SubscriptionAdminReportService {
  SubscriptionAdminReportService(this._sb);

  final SupabaseClient _sb;

  Future<bool> isPlatformStaff() async {
    try {
      final r = await _sb.rpc('is_platform_staff');
      return r == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchBillingSuccess({
    int limit = 500,
  }) =>
      fetchBilling(limit: limit);

  Future<List<Map<String, dynamic>>> fetchBilling({
    int limit = 500,
  }) async {
    try {
      final rows = await _sb
          .from('billing_transactions')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchLifecycleEvents({
    int limit = 500,
  }) async {
    try {
      final rows = await _sb
          .from('subscription_lifecycle_events')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    final d = DateTime.tryParse(s);
    if (d != null) {
      return DateHelper.fmtCivilDateTime(d.toLocal(), isAr: false);
    }
    return s;
  }

  double _amount(Map<String, dynamic> r) {
    final raw = r['amount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}') ?? 0.0;
  }

  Future<void> exportBillingSuccessExcel({
    required List<Map<String, dynamic>> rows,
    required bool isAr,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['billing'];
    for (final line in excelLetterheadLines(
      isAr: isAr,
      title: isAr ? 'مدفوعات المنصة' : 'Platform billing',
    )) {
      sheet.appendRow([TextCellValue(line)]);
    }
    final headers = isAr
        ? [
            'المعرف',
            'المستخدم',
            'المبلغ',
            'العملة',
            'طريقة الدفع',
            'الحالة',
            'الغرض',
            'معرف البوابة',
            'اشتراك',
            'أُكمل في',
          ]
        : [
            'id',
            'user_id',
            'amount',
            'currency',
            'payment_method',
            'status',
            'purpose',
            'gateway_transaction_id',
            'subscription_id',
            'completed_at',
          ];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue('${r['id'] ?? ''}'),
        TextCellValue('${r['user_id'] ?? ''}'),
        TextCellValue(
          excelAmountCell(_amount(r), isAr: isAr),
        ),
        TextCellValue('${r['currency'] ?? 'SAR'}'),
        TextCellValue(
          InvoiceCopy.methodLabel('${r['payment_method'] ?? ''}', isAr: isAr),
        ),
        TextCellValue('${r['status'] ?? ''}'),
        TextCellValue(InvoiceCopy.purposeFromRow(r)),
        TextCellValue('${r['gateway_transaction_id'] ?? ''}'),
        TextCellValue('${r['subscription_id'] ?? ''}'),
        TextCellValue(_fmt(r['completed_at'] ?? r['created_at'])),
      ]);
    }
    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: 'billing_${DateTime.now().millisecondsSinceEpoch}',
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> exportLifecycleExcel({
    required List<Map<String, dynamic>> rows,
    required bool isAr,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['lifecycle'];
    for (final line in excelLetterheadLines(
      isAr: isAr,
      title: isAr ? 'أحداث دورة الاشتراك' : 'Subscription lifecycle',
    )) {
      sheet.appendRow([TextCellValue(line)]);
    }
    final headers = isAr
        ? ['المعرف', 'المستخدم', 'الاشتراك', 'الحدث', 'الحمولة', 'الوقت']
        : [
            'id',
            'user_id',
            'subscription_id',
            'event_type',
            'payload',
            'created_at',
          ];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue('${r['id'] ?? ''}'),
        TextCellValue('${r['user_id'] ?? ''}'),
        TextCellValue('${r['subscription_id'] ?? ''}'),
        TextCellValue('${r['event_type'] ?? ''}'),
        TextCellValue('${r['payload'] ?? ''}'),
        TextCellValue(_fmt(r['created_at'])),
      ]);
    }
    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: 'subscription_lifecycle_${DateTime.now().millisecondsSinceEpoch}',
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}
