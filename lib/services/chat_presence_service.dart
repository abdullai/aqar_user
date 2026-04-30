import 'package:supabase_flutter/supabase_flutter.dart';

/// تحديث «آخر ظهور» في الدردشة (يُستدعى دورياً أثناء الجلسة).
abstract final class ChatPresenceService {
  static Future<void> ping(SupabaseClient sb) async {
    try {
      await sb.rpc('ping_chat_presence');
    } catch (_) {}
  }
}
