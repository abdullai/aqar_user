// lib/services/connectivity_guard.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../shared/core/supabase_config.dart';

/// خدمة مركزية لفحص الاتصال — مصدر واحد للتحقق من الشبكة + إمكانية الوصول للخادم.
class ConnectivityGuard {
  static final Connectivity _connectivity = Connectivity();

  /// فحص سريع عبر المكوّن فقط (بدون HTTP).
  static Future<bool> hasPluginLink() async {
    try {
      final result = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 5));
      if (result.isEmpty) return true;
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// فحص فوري كما كان سابقاً (لتوافق الاستدعاءات القديمة).
  static Future<bool> hasInternet() async => hasPluginLink();

  /// تحقق صارم: رابط شبكة + (على الموبايل) استجابة HTTP من مشروع Supabase.
  ///
  /// **الويب:** لا نستدعي جذر PostgREST هنا — طلبات مثل `HEAD/GET …/rest/v1/` قد تعيد
  /// 401 في الـ console مع مفتاح publishable **دون** أن تعني فشل جلب `properties`.
  /// نعتمد على المكوّن فقط؛ نجاح/فشل البيانات يظهر من استعلامات [SupabaseClient] نفسها.
  static Future<bool> hasReachableInternet() async {
    final linked = await hasPluginLink();
    if (!linked) return false;
    if (kIsWeb) return true;
    return probeBackendReachable();
  }

  /// طلب خفيف لجذر PostgREST (بدون `/auth/v1/health`). مفتاح anon غير صالح → 401.
  static Future<bool> probeBackendReachable() async {
    final base = SupabaseConfig.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    final key = SupabaseConfig.supabaseAnonKey;
    if (key.isEmpty) return false;
    final isPublishable = key.startsWith('sb_publishable_');
    final headers = <String, String>{
      'apikey': key,
      // ملاحظة مهمة:
      // - مفاتيح sb_publishable_* ليست JWT ولا تصلح كـ Bearer token.
      // - إرسالها داخل Authorization يسبب 401 متكرر على /rest/v1/ في الويب.
      if (!isPublishable) 'Authorization': 'Bearer $key',
    };
    // تجنّب HEAD على /rest/v1/ (غالباً 401 في المتصفح مع مفتاح publishable ويملأ الـ console).
    // جذر المشروع يستجيب غالباً بـ 404 — يكفي لإثبات الوصول للشبكة دون ضوضاء.
    try {
      final root = await http
          .get(Uri.parse('$base/'))
          .timeout(const Duration(seconds: 8));
      if (root.statusCode > 0 && root.statusCode < 600) return true;
    } catch (_) {}
    final restRoot = Uri.parse('$base/rest/v1/');
    try {
      final res = await http
          .get(restRoot, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode > 0 && res.statusCode < 600) return true;
    } catch (_) {}
    return false;
  }

  /// بعد [await] لفحص الشبكة: إن كان الاتصال غير متاح يعرض [SnackBar] دون كراش.
  static void showOfflineSnackIfNeeded(BuildContext context, bool connected) {
    if (connected || !context.mounted) return;
    final loc = AppLocalizations.of(context);
    final msg = loc?.noInternetConnectionTitle ?? 'No internet connection';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  /// Stream لمتابعة تغيّر حالة الاتصال (اختياري لاحقاً)
  static Stream<bool> onStatusChange() {
    return _connectivity.onConnectivityChanged.map((list) {
      if (list.isEmpty) return true;
      return !list.contains(ConnectivityResult.none);
    }).distinct();
  }
}
