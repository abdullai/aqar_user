import 'package:flutter/foundation.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/supabase_public_read_guard.dart';
import '../core/network/supabase_publishable_http_layer.dart';
import '../shared/core/supabase_config.dart';
import '../shared/core/supabase_schema_selects.dart';

/// جلب إعلانات الرئيسية (قراءة عامة) — **بدون** JWT في `Authorization`.
///
/// السبب الجذري لـ 401 الشائع على الويب: استعلام مضمّن
/// `property_images(...)` بينما جدول `property_images` بلا سياسة SELECT لـ `anon`
/// على المشروع (نفّذ `supabase/sql/20260429_guest_public_home_images_read_policy.sql`).
///
/// العميل الافتراضي قد يضيف `Bearer` منتهٍ أو publishable → 401؛ هنا `apikey` فقط.
abstract final class PropertiesHomeFeedService {
  static Future<List<dynamic>>? _inFlight;

  static bool get isCircuitOpen => SupabasePublicReadGuard.isInAuthFailureCooldown;

  static void resetCircuit() => SupabasePublicReadGuard.clearAuthFailureCooldown();

  static Future<List<dynamic>> fetch({
    required SupabaseClient client,
    required bool filterSuppressed,
    required int limit,
    bool allowBypassCircuit = false,
  }) async {
    if (!allowBypassCircuit && isCircuitOpen) {
      throw PostgrestException(
        message: 'Home properties fetch paused after auth error (circuit open)',
        code: '401',
      );
    }

    final existing = _inFlight;
    if (existing != null) {
      return List<dynamic>.from(await existing);
    }

    final fut = _fetchOnce(
      client: client,
      filterSuppressed: filterSuppressed,
      limit: limit,
    );
    _inFlight = fut;
    try {
      return List<dynamic>.from(await fut);
    } finally {
      if (identical(_inFlight, fut)) {
        _inFlight = null;
      }
    }
  }

  static PostgrestClient _anonRestClient(String base, String key) {
    return PostgrestClient(
      '$base/rest/v1',
      headers: {
        'apikey': key,
        'Accept': 'application/json',
      },
      httpClient: SupabasePublishableHttpLayer(),
    );
  }

  static Future<List<dynamic>> _runQuery({
    required PostgrestClient rest,
    required String select,
    required bool filterSuppressed,
    required int limit,
  }) async {
    var qb = rest.from('properties').select(select).neq('status', 'deleted');
    if (filterSuppressed) {
      qb = qb.or(
        'home_feed_suppressed.is.null,home_feed_suppressed.eq.false',
      );
    }
    final data = await qb
        .or(SupabaseSchemaSelects.propertiesHomeFeedOrFilter)
        .order('created_at', ascending: false)
        .limit(limit);
    if (data is! List) return const [];
    return data;
  }

  static bool _isUnauthorized(PostgrestException e) {
    final c = (e.code ?? '').trim();
    if (c == '401' || c == '403') return true;
    final m = e.message.toLowerCase();
    return m.contains('401') ||
        m.contains('403') ||
        m.contains('unauthorized') ||
        m.contains('jwt');
  }

  static Future<List<dynamic>> _fetchOnce({
    required SupabaseClient client,
    required bool filterSuppressed,
    required int limit,
  }) async {
    // عميل anon منفصل بلا JWT — لا تستدعِ dropStale هنا:
    // مسح الجلسة أثناء OTP/الدخول كان يسبب 401 على in_app_notifications والعودة لـ login.
    final key = SupabaseConfig.supabaseAnonKey.trim();
    final base = SupabaseConfig.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    if (key.isEmpty || base.isEmpty) {
      throw const PostgrestException(
        message: 'Supabase URL or anon key missing',
        code: '401',
      );
    }

    final rest = _anonRestClient(base, key);

    try {
      final data = await _runQuery(
        rest: rest,
        select: SupabaseSchemaSelects.propertiesListing,
        filterSuppressed: filterSuppressed,
        limit: limit,
      );
      if (kDebugMode) {
        debugPrint(
          '[PropertiesHomeFeedService] with images rows=${data.length} '
          'suppressed=$filterSuppressed',
        );
      }
      return data;
    } on PostgrestException catch (e) {
      if (!_isUnauthorized(e)) rethrow;

      if (kDebugMode) {
        debugPrint(
          '[PropertiesHomeFeedService] embed property_images blocked (${e.code}): '
          'retry without embed — apply supabase/sql/20260429_guest_public_home_images_read_policy.sql',
        );
      }

      try {
        final fallback = await _runQuery(
          rest: rest,
          select: SupabaseSchemaSelects.propertiesListingWithoutImageEmbed,
          filterSuppressed: filterSuppressed,
          limit: limit,
        );
        if (kDebugMode) {
          debugPrint(
            '[PropertiesHomeFeedService] fallback without images rows=${fallback.length}',
          );
        }
        return fallback;
      } on PostgrestException catch (e2) {
        if (_isUnauthorized(e2)) {
          SupabasePublicReadGuard.recordAuthFailure();
        }
        rethrow;
      }
    }
  }
}
