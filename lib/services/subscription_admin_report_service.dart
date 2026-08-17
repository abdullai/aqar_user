import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';

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
  }) async {
    try {
      final rows = await _sb
          .from('billing_transactions')
          .select()
          .eq('status', 'success')
          .order('completed_at', ascending: false)
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
      return DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());
    }
    return s;
  }

  Future<void> exportBillingSuccessExcel({
    required List<Map<String, dynamic>> rows,
    required bool isAr,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['billing_success'];
    sheet.appendRow([TextCellValue(AppBranding.legalName(isAr: isAr))]);
    final headers = isAr
        ? [
            'المعرف',
            'المستخدم',
            'المبلغ',
            'العملة',
            'طريقة الدفع',
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
            'gateway_transaction_id',
            'subscription_id',
            'completed_at',
          ];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue('${r['id'] ?? ''}'),
        TextCellValue('${r['user_id'] ?? ''}'),
        TextCellValue('${r['amount'] ?? ''}'),
        TextCellValue('${r['currency'] ?? ''}'),
        TextCellValue('${r['payment_method'] ?? ''}'),
        TextCellValue('${r['gateway_transaction_id'] ?? ''}'),
        TextCellValue('${r['subscription_id'] ?? ''}'),
        TextCellValue(_fmt(r['completed_at'])),
      ]);
    }
    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: 'billing_success_${DateTime.now().millisecondsSinceEpoch}',
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
    sheet.appendRow([TextCellValue(AppBranding.legalName(isAr: isAr))]);
    final headers = isAr
        ? ['المعرف', 'المستخدم', 'الاشتراك', 'الحدث', 'الحمولة', 'الوقت']
        : ['id', 'user_id', 'subscription_id', 'event_type', 'payload', 'created_at'];
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
