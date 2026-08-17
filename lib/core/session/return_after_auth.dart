// lib/core/session/return_after_auth.dart
//
// يحفظ اسم المسار (والوسائط عند الإمكان) قبل إجبار المستخدم على تسجيل الدخول أو
// الدخول السريع، ثم يستعيدها بعد نجاح المصادقة.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/post_auth_navigation.dart';

class ReturnAfterAuth {
  ReturnAfterAuth._();

  static const String kPrefReturnRoute = 'post_auth_return_route';
  static const String kPrefReturnArgsJson = 'post_auth_return_args_json';

  static const Set<String> _ignoredRoutes = {
    '',
    '/',
    '/login',
    '/fastLogin',
    '/gate',
    '/entryChoice',
    '/verify',
    '/resetPassword',
    '/passwordSetup',
  };

  static dynamic _sanitizeForJson(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return v.map(
        (k, val) => MapEntry(k.toString(), _sanitizeForJson(val)),
      );
    }
    if (v is Iterable) {
      return v.map(_sanitizeForJson).toList();
    }
    return v;
  }

  /// يحفظ المسار الحالي إن كان مسماً ويُعتبر داخل التطبيق بعد المصادقة.
  static Future<void> saveFromNavigatorKey(GlobalKey<NavigatorState> key) async {
    final state = key.currentState;
    final ctx = key.currentContext ?? state?.context;
    if (ctx == null) return;

    final route = ModalRoute.of(ctx)?.settings;
    final name = route?.name?.trim() ?? '';
    if (name.isEmpty || _ignoredRoutes.contains(name)) return;

    await _persist(name, route?.arguments);
  }

  static Future<void> _persist(String name, Object? args) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefReturnRoute, name);

    if (args is Map) {
      final raw = Map<String, dynamic>.from(
        args.map((k, v) => MapEntry(k.toString(), v)),
      );
      final safe = _sanitizeForJson(raw);
      try {
        if (safe is Map) {
          await prefs.setString(kPrefReturnArgsJson, jsonEncode(safe));
        } else {
          await prefs.remove(kPrefReturnArgsJson);
        }
      } catch (_) {
        await prefs.remove(kPrefReturnArgsJson);
      }
    } else {
      await prefs.remove(kPrefReturnArgsJson);
    }
  }

  static Map<String, dynamic>? decodeArgsJson(String? argsJson) {
    if (argsJson == null || argsJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(argsJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// يقرأ المسار المحفوظ ويمسحه من التخزين (استدعاء واحد بعد نجاح الدخول).
  static Future<({String route, String? argsJson})?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString(kPrefReturnRoute);
    if (route == null || route.isEmpty) return null;
    final argsJson = prefs.getString(kPrefReturnArgsJson);
    await prefs.remove(kPrefReturnRoute);
    await prefs.remove(kPrefReturnArgsJson);
    return (route: route, argsJson: argsJson);
  }

  /// ينتقل إلى المسار المحفوظ أو إلى [defaultRoute].
  static Future<void> navigatePostAuthOrDefault(
    NavigatorState nav,
    String defaultRoute, {
    Object? defaultArgs,
  }) async {
    final tuple = await consume();
    if (tuple != null) {
      final args = decodeArgsJson(tuple.argsJson) ?? defaultArgs;
      await PostAuthNavigation.navigatorOpenRouteReplacingStack(
        nav,
        PostAuthNavigation.resolveDashboardRoute(tuple.route),
        arguments: args,
      );
    } else {
      await PostAuthNavigation.navigatorOpenRouteReplacingStack(
        nav,
        PostAuthNavigation.resolveDashboardRoute(defaultRoute),
        arguments: defaultArgs,
      );
    }
  }
}
