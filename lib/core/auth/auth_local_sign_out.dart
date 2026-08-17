import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/core/supabase_config.dart';

import 'auth_local_sign_out_stub.dart'
    if (dart.library.js_interop) 'auth_local_sign_out_web.dart';

/// خروج محلي آمن — يقلّل طلبات `POST /auth/v1/logout` الفاشلة (401) عند انتهاء الجلسة.
abstract final class AuthLocalSignOut {
  AuthLocalSignOut._();

  static bool _signOutInFlight = false;
  static DateTime? _lastSignOutAt;

  static String persistSessionKey() {
    final url = SupabaseConfig.supabaseUrl.trim();
    if (url.isEmpty) return 'sb-auth-token';
    final host = Uri.tryParse(url)?.host ?? '';
    final ref = host.split('.').first;
    return 'sb-$ref-auth-token';
  }

  static bool _accessTokenStillValid(Session session) {
    final exp = session.expiresAt;
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return exp > now + 15;
  }

  static Future<void> _purgePersistedAuthToken() async {
    final key = persistSessionKey();
    try {
      if (kIsWeb && bool.fromEnvironment('dart.library.js_interop')) {
        await _purgeWebLocalStorageKey(key);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<void> _purgeWebLocalStorageKey(String key) async {
    if (!kIsWeb) return;
    try {
      // ignore: avoid_web_libraries_in_flutter
      await _webRemoveLocalStorage(key);
    } catch (_) {}
  }

  static Future<void> _webRemoveLocalStorage(String key) async {
    // فصل conditional import خفيف — نفس مفتاح supabase_flutter على الويب.
    await purgeWebAuthTokenKey(key);
  }

  /// مسح جلسة Supabase محلياً. افتراضياً لا يُرسل POST /logout (يتجنّب 401 عند JWT منتهٍ).
  ///
  /// دائماً يُفرّغ الجلسة من الذاكرة + التخزين — وإلا يبقى JWT قديماً في وضع الضيف
  /// فتفشل طلبات الرئيسية ويبدو التطبيق معلّقاً بعد «الدخول كضيف».
  static Future<void> signOutLocal(
    SupabaseClient client, {
    bool tryRemoteRevoke = false,
  }) async {
    final now = DateTime.now();
    if (_signOutInFlight) return;
    if (_lastSignOutAt != null &&
        now.difference(_lastSignOutAt!) < const Duration(seconds: 3)) {
      return;
    }

    _signOutInFlight = true;
    _lastSignOutAt = now;
    try {
      try {
        client.auth.stopAutoRefresh();
      } catch (_) {}

      final session = client.auth.currentSession;
      if (session == null) {
        await _purgePersistedAuthToken();
        return;
      }

      // دائماً signOut(local) لتفريغ الجلسة من الذاكرة.
      // tryRemoteRevoke محفوظ للتوافق؛ لا نرسل revoke عن بُعد عند JWT منتهٍ.
      if (tryRemoteRevoke && !_accessTokenStillValid(session)) {
        await _purgePersistedAuthToken();
      }
      try {
        await client.auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        await _purgePersistedAuthToken();
      }
      if (client.auth.currentSession != null) {
        await _purgePersistedAuthToken();
      }
    } finally {
      _signOutInFlight = false;
    }
  }
}
