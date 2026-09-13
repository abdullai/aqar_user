import 'desktop_supabase_config_stub.dart'
    if (dart.library.io) 'desktop_supabase_config_io.dart' as impl;

/// ويندوز/سطح المكتب: نفس [web/supabase_config.json] المستخدم في الويب.
Future<void> tryLoadDesktopSupabaseRuntimeConfig() =>
    impl.tryLoadDesktopSupabaseRuntimeConfig();
