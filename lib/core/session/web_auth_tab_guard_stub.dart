import 'package:supabase_flutter/supabase_flutter.dart';

/// غير الويب — لا ربط تبويب.
abstract final class WebAuthTabGuard {
  static Future<void> establishBinding(String userId) async {}

  static Future<void> clearBinding() async {}

  /// دائماً true خارج الويب.
  static Future<bool> isBindingValidForCurrentSession(
    SupabaseClient client,
  ) async =>
      true;

  /// لا شيء على المنصات غير الويب.
  static Future<bool> ensureValidOrSignOutLocal(SupabaseClient client) async =>
      true;
}
