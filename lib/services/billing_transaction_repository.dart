import 'package:supabase_flutter/supabase_flutter.dart';

/// مستودع معاملات الفواتير — استعلامات، أرشفة، وتطبيع الحالة.
/// Billing transaction repository — queries, archive, status normalization.
class BillingTransactionRepository {
  BillingTransactionRepository(this._sb);

  final SupabaseClient _sb;
  static const _table = 'billing_transactions';

  String? get _uid => _sb.auth.currentUser?.id;

  /// يُحوّل الحالة الخام إلى تبويب العرض (success / pending / failed).
  static String normalizedStatus(Map<String, dynamic> row) {
    final raw = '${row['status'] ?? ''}'.toLowerCase().trim();
    if (raw == 'refunded' || raw == 'refund') {
      return 'refunded';
    }
    if (raw == 'partially_refunded' || raw == 'partial_refund') {
      return 'partially_refunded';
    }
    if (raw == 'success' ||
        raw == 'paid' ||
        raw == 'completed' ||
        raw == 'succeeded' ||
        raw == 'captured' ||
        raw == 'ok') {
      return 'success';
    }
    if (raw == 'failed' ||
        raw == 'error' ||
        raw == 'declined' ||
        raw == 'canceled' ||
        raw == 'cancelled' ||
        raw == 'expired' ||
        raw == 'voided') {
      return 'failed';
    }
    if (raw == 'authorized') {
      return 'pending';
    }

    final gw = row['gateway_response'];
    if (gw is Map) {
      final m = Map<String, dynamic>.from(gw);
      if (m['ok'] == true ||
          '${m['status'] ?? ''}'.toLowerCase() == 'paid' ||
          '${m['status'] ?? ''}'.toLowerCase() == 'success') {
        return 'success';
      }
      if (m['ok'] == false || m['status'] == 'failed') return 'failed';
      final err = '${m['error'] ?? ''}'.toLowerCase();
      if (err.contains('fail') ||
          err.contains('declin') ||
          err.contains('reject')) {
        return 'failed';
      }
    }

    if (raw == 'pending' || raw == 'processing' || raw == 'initiated') {
      final created = DateTime.tryParse('${row['created_at']}');
      if (created != null) {
        final age = DateTime.now().difference(created);
        if (age.inHours > 2) return 'failed';
      }
      return 'pending';
    }
    return raw.isEmpty ? 'pending' : raw;
  }

  static bool isArchived(Map<String, dynamic> row) {
    if (row['hidden_from_user'] == true) return true;
    final gw = row['gateway_response'];
    if (gw is Map) {
      return gw['archived'] == true;
    }
    return false;
  }

  /// رقم عملية لاتيني داخلي قديم — لا يُعرض للمستخدم.
  static String latinReference(Map<String, dynamic> row) {
    final created = DateTime.tryParse('${row['created_at']}') ?? DateTime.now();
    final ymd =
        '${created.year}${created.month.toString().padLeft(2, '0')}${created.day.toString().padLeft(2, '0')}';
    final id = '${row['id'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final seq = id.isEmpty
        ? '001'
        : id.substring(id.length > 3 ? id.length - 3 : 0).padLeft(3, '0');
    final gw = '${row['gateway_transaction_id'] ?? ''}'.trim();
    if (gw.isNotEmpty && RegExp(r'^\d+$').hasMatch(gw)) return gw;
    return '$ymd$seq';
  }

  /// نطاق التاريخ من فلتر جاهز: all | today | week | month
  static ({DateTime? from, DateTime? to}) dateRangeForFilter(String filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (filter) {
      case 'today':
        return (from: today, to: today);
      case 'week':
        return (from: today.subtract(const Duration(days: 6)), to: today);
      case 'month':
        return (from: DateTime(now.year, now.month, 1), to: today);
      default:
        return (from: null, to: null);
    }
  }

  Future<List<Map<String, dynamic>>> listTransactions({
    String? status,
    String? search,
    String dateFilter = 'all',
    DateTime? fromDate,
    DateTime? toDate,
    bool includeArchived = false,
    int limit = 200,
  }) async {
    final preset = dateRangeForFilter(dateFilter);
    return list(
      statusFilter: status,
      search: search,
      fromDate: fromDate ?? preset.from,
      toDate: toDate ?? preset.to,
      includeArchived: includeArchived,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> archiveTransaction(String txId) => archive(txId);

  Future<Map<String, dynamic>> deleteTransaction(String txId) => delete(txId);

  Future<List<Map<String, dynamic>>> list({
    String? statusFilter,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeArchived = false,
    int limit = 200,
  }) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _sb
          .from(_table)
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      var list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!includeArchived) {
        list = list.where((r) => !isArchived(r)).toList();
      }

      if (fromDate != null) {
        list = list.where((r) {
          final dt = DateTime.tryParse('${r['created_at']}');
          return dt != null && !dt.isBefore(fromDate);
        }).toList();
      }
      if (toDate != null) {
        final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
        list = list.where((r) {
          final dt = DateTime.tryParse('${r['created_at']}');
          return dt != null && !dt.isAfter(end);
        }).toList();
      }

      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim().toLowerCase();
        list = list.where((r) {
          final inv = '${r['invoice_number'] ?? ''}'.toLowerCase();
          final ta = '${r['title_ar'] ?? ''}'.toLowerCase();
          final te = '${r['title_en'] ?? ''}'.toLowerCase();
          return inv.contains(s) || ta.contains(s) || te.contains(s);
        }).toList();
      }

      if (statusFilter != null && statusFilter.isNotEmpty) {
        list = list
            .where((r) => normalizedStatus(r) == statusFilter)
            .toList();
      }

      return list;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getOwn(String txId) async {
    final uid = _uid;
    if (uid == null) return null;
    final id = txId.trim();
    if (id.isEmpty) return null;
    try {
      final row = await _sb
          .from(_table)
          .select()
          .eq('id', id)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getOwnByInvoiceNumber(String invoiceNumber) async {
    final uid = _uid;
    if (uid == null) return null;
    final inv = invoiceNumber.trim();
    if (inv.isEmpty) return null;
    try {
      final row = await _sb
          .from(_table)
          .select()
          .eq('invoice_number', inv)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// إخفاء من السجل فقط — لا حذف مالي.
  Future<Map<String, dynamic>> archive(String txId) => hideFromLedger(txId);

  Future<Map<String, dynamic>> hideFromLedger(String txId) async {
    final uid = _uid;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      final res = await _sb.rpc(
        'billing_hide_own_invoice',
        params: {'p_id': txId},
      );
      if (res is Map && res['ok'] == true) return {'ok': true};
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'ok': false, 'error': 'hide_failed'};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// لا حذف صف مالي. يُخفي من السجل فقط.
  Future<Map<String, dynamic>> delete(String txId) => hideFromLedger(txId);
}
