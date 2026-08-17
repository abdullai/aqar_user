// lib/services/connectivity_guard.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../shared/core/supabase_config.dart';

/// خدمة مركزية لفحص الاتصال — مصدر واحد للتحقق من الشبكة.
///
/// **قاعدة صارمة:** حالة «متصل» المستخدمة لحجب اللمس/الدخول تعتمد فقط على
/// رابط الشبكة (Wi‑Fi/بيانات)، وليس على نجاح HTTP إلى Supabase.
/// فحص الخادم اختياري وتشخيصي فقط — فشله لا يعني قطع الإنترنت ولا يجمّد التطبيق.
class ConnectivityGuard {
  static final Connectivity _connectivity = Connectivity();

  /// فحص سريع عبر المكوّن فقط (بدون HTTP). فشل الفحص → نفترض الاتصال متاحاً.
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

  /// فحص فوري لتوافق الاستدعاءات القديمة — رابط الشبكة فقط.
  static Future<bool> hasInternet() async => hasPluginLink();

  /// هل يمكن اعتبار الجهاز «متصلاً» لواجهة التطبيق؟
  ///
  /// لا يعتمد على استجابة Supabase. طلب HTTP بطيء/فاشل بعد الدخول كان يضع
  /// `IgnorePointer` على كامل التطبيق فيبدو معلّقاً بعد تسجيل الدخول أو الضيف.
  static Future<bool> hasReachableInternet() async => hasPluginLink();

  /// تشخيص اختياري: هل مشروع Supabase يرد؟ لا يُستخدم لحجب اللمس.
  static Future<bool> probeBackendReachable() async {
    final base = SupabaseConfig.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    final key = SupabaseConfig.supabaseAnonKey;
    if (key.isEmpty) return false;
    final isPublishable = key.startsWith('sb_publishable_');
    final headers = <String, String>{
      'apikey': key,
      if (!isPublishable) 'Authorization': 'Bearer $key',
    };
    if (!kIsWeb) {
      try {
        final root = await http
            .get(Uri.parse('$base/'))
            .timeout(const Duration(seconds: 5));
        if (root.statusCode > 0 && root.statusCode < 600) return true;
      } catch (_) {}
    }
    final restRoot = Uri.parse('$base/rest/v1/');
    try {
      final res = await http
          .get(restRoot, headers: headers)
          .timeout(const Duration(seconds: 5));
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
