import 'supabase_anon_key_guard.dart';

/// قيم يُملأها الويب عند التشغيل من [supabase_config.json] بجانب [index.html].
///
/// مفتاح anon العام مُصرَّح به في العميل؛ لا تضع أسرار الخادم هنا.
class SupabaseRuntimeOverrides {
  SupabaseRuntimeOverrides._();

  static String? webAnonKey;
  static String? webSupabaseUrl;

  static void applyFromJson(Map<String, dynamic> m) {
    final k = (m['SUPABASE_ANON_KEY'] ?? m['supabase_anon_key'] ?? '')
        .toString()
        .trim();
    if (SupabaseAnonKeyGuard.looksLikeValidClientKey(k)) {
      webAnonKey = k;
    } else {
      webAnonKey = null;
    }
    final u = (m['SUPABASE_URL'] ?? m['supabase_url'] ?? '')
        .toString()
        .trim();
    if (SupabaseAnonKeyGuard.looksLikeValidProjectUrl(u)) {
      webSupabaseUrl = u;
    } else {
      webSupabaseUrl = null;
    }
  }
}
