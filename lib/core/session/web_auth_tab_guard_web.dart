import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_local_sign_out.dart';

/// يربط جلسة الويب بتبويب واحد (sessionStorage) مقابل [SharedPreferences] على نفس الأصل.
/// فتح الرابط في تبويب جديد لا يملك نفس sessionStorage → يُرفض الدخول حتى إعادة التحقق.
abstract final class WebAuthTabGuard {
  static const _kPrefSig = 'web_auth_tab_sig_v1';
  static const _kPrefUid = 'web_auth_tab_uid_v1';
  static const _sessionKey = 'aqar_auth_tab_sig';

  static Future<void> establishBinding(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final sig = const Uuid().v4();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefSig, sig);
      await p.setString(_kPrefUid, uid);
    } catch (_) {}
    try {
      html.window.sessionStorage[_sessionKey] = sig;
    } catch (_) {}
  }

  static Future<void> clearBinding() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kPrefSig);
      await p.remove(_kPrefUid);
    } catch (_) {}
    try {
      html.window.sessionStorage.remove(_sessionKey);
    } catch (_) {}
  }

  static Future<bool> isBindingValidForCurrentSession(
    SupabaseClient client,
  ) async {
    if (!kIsWeb) return true;
    final session = client.auth.currentSession;
    if (session == null) return true;

    final uid = session.user.id.trim();
    if (uid.isEmpty) return true;

    try {
      final p = await SharedPreferences.getInstance();
      final sigP = (p.getString(_kPrefSig) ?? '').trim();
      final uidP = (p.getString(_kPrefUid) ?? '').trim();

      if (sigP.isEmpty || uidP.isEmpty) {
        await establishBinding(uid);
        return true;
      }
      if (uidP != uid) {
        await establishBinding(uid);
        return true;
      }

      final sigS = (html.window.sessionStorage[_sessionKey] ?? '').trim();
      if (sigS.isEmpty || sigS != sigP) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> ensureValidOrSignOutLocal(SupabaseClient client) async {
    if (!kIsWeb) return true;
    final ok = await isBindingValidForCurrentSession(client);
    if (ok) return true;
    try {
      await clearBinding();
    } catch (_) {}
    try {
      await AuthLocalSignOut.signOutLocal(client);
    } catch (_) {}
    return false;
  }
}
