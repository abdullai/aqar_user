import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/app_session.dart';

/// After one-time mock pay: optional anonymous Supabase session so RLS-backed flows work.
abstract final class GuestSessionBridge {
  static Future<bool> tryEstablishBrowsingUser({
    required SupabaseClient sb,
    required AppSession appSession,
  }) async {
    try {
      final res = await sb.auth.signInAnonymously();
      final uid = res.user?.id;
      if (uid == null || uid.isEmpty) return false;
      await appSession.setUser(uid);
      return true;
    } catch (_) {
      return false;
    }
  }
}
