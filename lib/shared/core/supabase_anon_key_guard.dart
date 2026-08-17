/// يتأكد أن المفتاح مناسب للعميل (JWT قديم أو مفتاح Publishable الجديد من Supabase).
abstract final class SupabaseAnonKeyGuard {
  SupabaseAnonKeyGuard._();

  static const Set<String> _knownPlaceholders = {
    'YOUR_KEY_HERE',
    'your_key_here',
    'PASTE_ANON_KEY',
    'REPLACE_ME',
  };

  /// مفتاح عميل صالح:
  /// - JWT الـ anon القديم: يبدأ بـ `eyJ` وطوله كافٍ؛ أو
  /// - مفتاح **Publishable** من لوحة Supabase الحديثة: يبدأ بـ `sb_publishable_`.
  ///
  /// لا تستخدم **`sb_secret_`** في التطبيق (خادم فقط).
  static bool looksLikeValidClientKey(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return false;
    if (_knownPlaceholders.contains(s)) return false;
    if (s.contains('YOUR_KEY')) return false;
    if (s.startsWith('sb_secret_')) return false;

    if (s.startsWith('sb_publishable_')) {
      if (s.length < 28) return false;
      if (s.endsWith('...') || s.contains('...')) return false;
      return true;
    }

    if (s.startsWith('eyJ')) {
      if (s.length < 100) return false;
      if (s.endsWith('...') || s.contains('...')) return false;
      return true;
    }

    return false;
  }

  /// عنوان مشروع Supabase (ليس قالب YOUR_PROJECT_REF).
  static bool looksLikeValidProjectUrl(String? raw) {
    final s = (raw ?? '').trim();
    if (s.length < 24) return false;
    if (!s.startsWith('https://')) return false;
    if (!s.contains('.supabase.co')) return false;
    if (s.contains('YOUR_PROJECT')) return false;
    if (s.contains('YOUR_PROJECT_REF')) return false;
    return true;
  }
}
