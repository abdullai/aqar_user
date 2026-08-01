/// ربط طبقة HTTP بجلسة Supabase الحالية (يُعيَّن بعد [Supabase.initialize]).
abstract final class SupabaseHttpAuthBridge {
  static String? Function()? accessToken;

  static String? activeAccessToken() {
    try {
      return accessToken?.call();
    } catch (_) {
      return null;
    }
  }
}
