import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_anon_key_guard.dart';
import 'supabase_runtime_overrides.dart';

/// إعدادات Supabase: تُقرأ بالترتيب من
/// `--dart-define=SUPABASE_*` ثم (ويب فقط) [SupabaseRuntimeOverrides] من `supabase_config.json`
/// ثم [flutter_dotenv] (`assets/env/default.env` واختيارياً `.env`).
///
/// استخدم من لوحة Supabase → **Project Settings → API Keys**:
/// - **Publishable** (`sb_publishable_…`) للعميل، أو JWT الـ **anon** القديم (`eyJ…`) إن ظهر.
/// لا تضع **`sb_secret_`** في التطبيق.
class SupabaseConfig {
  SupabaseConfig._();

  static const String _defaultProjectUrl =
      'https://czfvqhepsqkgsrfnknwm.supabase.co';

  static String get supabaseUrl {
    const fromDefine = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    final d = fromDefine.trim();
    if (SupabaseAnonKeyGuard.looksLikeValidProjectUrl(d)) return d;
    final fromWeb = (SupabaseRuntimeOverrides.webSupabaseUrl ?? '').trim();
    if (SupabaseAnonKeyGuard.looksLikeValidProjectUrl(fromWeb)) {
      return fromWeb;
    }
    final s = (dotenv.env['SUPABASE_URL'] ?? '').trim();
    if (SupabaseAnonKeyGuard.looksLikeValidProjectUrl(s)) return s;
    return _defaultProjectUrl;
  }

  /// مفتاح العميل لـ PostgREST / `supabase_flutter` (publishable أو JWT anon).
  static String get supabaseAnonKey {
    const fromDefine = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );
    final d = fromDefine.trim();
    if (SupabaseAnonKeyGuard.looksLikeValidClientKey(d)) return d;
    final fromWeb = (SupabaseRuntimeOverrides.webAnonKey ?? '').trim();
    if (SupabaseAnonKeyGuard.looksLikeValidClientKey(fromWeb)) return fromWeb;
    final fromDot = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
    if (SupabaseAnonKeyGuard.looksLikeValidClientKey(fromDot)) return fromDot;
    return '';
  }

  static SupabaseClient get client => Supabase.instance.client;
}
