import 'dart:convert';

import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تفضيلات محلية: إخفاء إعلانات/طلبات من الرئيسية + تتبّع بلاغات المستخدم (حدّ معدّل، سحب، إحصاء).
abstract final class UserListingPreferencesService {
  static const String _kHiddenProperties = 'user_hidden_property_ids_v1';
  static const String _kHiddenRequests = 'user_hidden_market_request_ids_v1';
  static const String _kHiddenCompletedDeals =
      'user_hidden_completed_deal_property_ids_v1';
  static const String _kReportEvents = 'user_report_events_v1';
  static const String _kPendingPropertyReports =
      'user_pending_property_reports_map_v1';

  static const int _maxEvents = 400;

  /// حدود مبدئية ضد الإساءة (قابلة للتوسعة من الخادم).
  static const int maxPropertyReportsPerHour = 3;
  static const int maxPropertyReportsPerDay = 12;
  static const int sternWarningPropertyReportsPerDay = 5;

  static Future<Set<String>> hiddenPropertyIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHiddenProperties);
      return _decodeIdSet(raw);
    } catch (_) {
      return {};
    }
  }

  static Future<Set<String>> hiddenMarketRequestIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHiddenRequests);
      return _decodeIdSet(raw);
    } catch (_) {
      return {};
    }
  }

  static Set<String> _decodeIdSet(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _saveSet(String key, Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(ids.toList()));
  }

  static Future<void> addHiddenProperty(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenPropertyIds();
    s.add(sid);
    await _saveSet(_kHiddenProperties, s);
  }

  static Future<void> removeHiddenProperty(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenPropertyIds();
    s.remove(sid);
    await _saveSet(_kHiddenProperties, s);
  }

  static Future<void> addHiddenMarketRequest(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenMarketRequestIds();
    s.add(sid);
    await _saveSet(_kHiddenRequests, s);
  }

  static Future<void> removeHiddenMarketRequest(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenMarketRequestIds();
    s.remove(sid);
    await _saveSet(_kHiddenRequests, s);
  }

  /// مسح إخفاء الرئيسية المحلي (إعلانات + طلبات السوق) — لا يمس «صفقات مكتملة».
  static Future<void> clearHomeFeedHideSets() async {
    await _saveSet(_kHiddenProperties, {});
    await _saveSet(_kHiddenRequests, {});
  }

  /// إخفاء عقار من تبويب «صفقات مكتملة» في صفحتي (محلي، لا يؤثر على الرئيسية).
  static Future<Set<String>> hiddenCompletedDealPropertyIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kHiddenCompletedDeals);
      return _decodeIdSet(raw);
    } catch (_) {
      return {};
    }
  }

  static Future<void> addHiddenCompletedDealProperty(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenCompletedDealPropertyIds();
    s.add(sid);
    await _saveSet(_kHiddenCompletedDeals, s);
  }

  static Future<void> removeHiddenCompletedDealProperty(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final s = await hiddenCompletedDealPropertyIds();
    s.remove(sid);
    await _saveSet(_kHiddenCompletedDeals, s);
  }

  static Future<void> clearHiddenCompletedDeals() async {
    await _saveSet(_kHiddenCompletedDeals, {});
  }

  // ---------------------------------------------------------------------------
  // تقارير — أحداث (إحصاء + حدّ معدّل)
  // ---------------------------------------------------------------------------

  static Future<List<_ReportEvent>> _loadReportEvents() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kReportEvents);
      if (raw == null || raw.trim().isEmpty) return [];
      final d = jsonDecode(raw);
      if (d is! List) return [];
      final out = <_ReportEvent>[];
      for (final e in d) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final ts = (m['ts'] as num?)?.toInt() ?? 0;
          final kind = (m['kind'] ?? '').toString();
          final id = (m['id'] ?? '').toString().trim();
          if (ts > 0 && id.isNotEmpty) {
            out.add(_ReportEvent(ts: ts, kind: kind, id: id));
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveReportEvents(List<_ReportEvent> list) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = list.length > _maxEvents
        ? list.sublist(list.length - _maxEvents)
        : list;
    await p.setString(
      _kReportEvents,
      jsonEncode(trimmed
          .map((e) => {'ts': e.ts, 'kind': e.kind, 'id': e.id})
          .toList()),
    );
  }

  static Future<void> recordPropertyReportSubmitted(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) return;
    final list = await _loadReportEvents();
    list.add(_ReportEvent(
      ts: DateTime.now().millisecondsSinceEpoch,
      kind: 'property',
      id: id,
    ));
    await _saveReportEvents(list);
  }

  static Future<void> recordMarketRequestReportSubmitted(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    final list = await _loadReportEvents();
    list.add(_ReportEvent(
      ts: DateTime.now().millisecondsSinceEpoch,
      kind: 'request',
      id: id,
    ));
    await _saveReportEvents(list);
  }

  /// حدّ معدّل الإبلاغ: يجمع بلاغات الإعلانات وطلبات السوق.
  static Future<({bool allow, String? sternWarning, String? blockMessage})>
      evaluateListingReportGate(AppLocalizations l10n) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dayAgo = now - const Duration(hours: 24).inMilliseconds;
    final hourAgo = now - const Duration(hours: 1).inMilliseconds;
    final events = await _loadReportEvents();
    bool countsTowardLimit(_ReportEvent e) =>
        e.kind == 'property' || e.kind == 'request';
    final day = events.where((e) => countsTowardLimit(e) && e.ts >= dayAgo).length;
    final hour =
        events.where((e) => countsTowardLimit(e) && e.ts >= hourAgo).length;

    if (hour >= maxPropertyReportsPerHour) {
      return (
        allow: false,
        sternWarning: null,
        blockMessage: l10n.listingReportGateHourlyBlock,
      );
    }
    if (day >= maxPropertyReportsPerDay) {
      return (
        allow: false,
        sternWarning: null,
        blockMessage: l10n.listingReportGateDailyBlock,
      );
    }
    String? stern;
    if (day >= sternWarningPropertyReportsPerDay) {
      stern = l10n.listingReportGateSternWarning;
    }
    return (allow: true, sternWarning: stern, blockMessage: null);
  }

  static Future<({int propertyReports, int requestReports, int last30d})>
      reportStatsSummary() async {
    final events = await _loadReportEvents();
    var p = 0;
    var r = 0;
    final cut = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    var last30 = 0;
    for (final e in events) {
      if (e.kind == 'property') {
        p++;
      } else if (e.kind == 'request') {
        r++;
      }
      if (e.ts >= cut) last30++;
    }
    return (
      propertyReports: p,
      requestReports: r,
      last30d: last30,
    );
  }

  // ---------------------------------------------------------------------------
  // بلاغ معلّق (للسحب + إشعار المسوّق كان من جهة الخادم)
  // ---------------------------------------------------------------------------

  static Future<Map<String, String>> _pendingReportsMap() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPendingPropertyReports);
      if (raw == null || raw.trim().isEmpty) return {};
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      return d.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePendingReportsMap(Map<String, String> m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPendingPropertyReports, jsonEncode(m));
  }

  static Future<void> setPendingPropertyReportRow(
    String propertyId,
    String reportRowId,
  ) async {
    final pid = propertyId.trim();
    final rid = reportRowId.trim();
    if (pid.isEmpty || rid.isEmpty) return;
    final m = await _pendingReportsMap();
    m[pid] = rid;
    await _savePendingReportsMap(m);
  }

  static Future<void> clearPendingPropertyReport(String propertyId) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return;
    final m = await _pendingReportsMap();
    m.remove(pid);
    await _savePendingReportsMap(m);
  }

  static Future<bool> hasPendingPropertyReport(String propertyId) async {
    final m = await _pendingReportsMap();
    return m.containsKey(propertyId.trim());
  }

  /// سحب بلاغ معلّق من الخادم (حالة pending) ثم تنظيف محلي.
  static Future<void> withdrawPendingPropertyReport(
    SupabaseClient sb,
    String propertyId,
  ) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return;
    final uid = sb.auth.currentUser?.id ?? '';
    final m = await _pendingReportsMap();
    final rid = m[pid]?.trim() ?? '';

    try {
      if (rid.isNotEmpty) {
        await sb.from('listing_user_reports').delete().eq('id', rid);
      } else if (uid.isNotEmpty) {
        await sb
            .from('listing_user_reports')
            .delete()
            .eq('property_id', pid)
            .eq('reporter_user_id', uid)
            .eq('status', 'pending');
      }
    } catch (_) {}

    await clearPendingPropertyReport(pid);
  }

  /// إزالة معرّفات إخفاء لم تعد موجودة في الخادم (بيع/حذف/إزالة من التغذية).
  static Future<void> pruneHiddenAgainstKnownPropertyIds(
    Iterable<String> knownIds,
  ) async {
    final set = knownIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final hidden = await hiddenPropertyIds();
    if (hidden.isEmpty) return;
    final next = hidden.where((id) => set.contains(id)).toSet();
    if (next.length != hidden.length) {
      await _saveSet(_kHiddenProperties, next);
    }
    final pending = await _pendingReportsMap();
    if (pending.isEmpty) return;
    final pNext = Map<String, String>.from(pending);
    pNext.removeWhere((pid, _) => !set.contains(pid));
    if (pNext.length != pending.length) {
      await _savePendingReportsMap(pNext);
    }
  }

  static Future<void> pruneHiddenAgainstKnownRequestIds(
    Iterable<String> knownIds,
  ) async {
    final set = knownIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final hidden = await hiddenMarketRequestIds();
    if (hidden.isEmpty) return;
    final next = hidden.where((id) => set.contains(id)).toSet();
    if (next.length != hidden.length) {
      await _saveSet(_kHiddenRequests, next);
    }
  }
}

class _ReportEvent {
  final int ts;
  final String kind;
  final String id;

  _ReportEvent({required this.ts, required this.kind, required this.id});
}
