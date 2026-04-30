import 'package:supabase_flutter/supabase_flutter.dart';

class UsersProfilesSafeSelect {
  const UsersProfilesSafeSelect._();

  static const List<String> defaultProfileColumns = [
    'user_id,username,full_name,full_name_ar,full_name_en,avatar_url,account_type',
    'user_id,username',
    'user_id',
  ];

  static const List<String> enrichedProfileColumns = [
    'user_id,username,full_name,full_name_ar,full_name_en,avatar_url,account_type',
    'user_id,username',
    'user_id',
  ];

  static Future<Map<String, Map<String, dynamic>>> fetchProfilesByIds(
    SupabaseClient sb,
    Iterable<String> ids, {
    List<String> columnAttempts = defaultProfileColumns,
  }) async {
    final uniqueIds = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueIds.isEmpty) return const {};

    for (final columns in columnAttempts) {
      try {
        final rows = await sb
            .from('users_profiles')
            .select(columns)
            .inFilter('user_id', uniqueIds);
        final out = <String, Map<String, dynamic>>{};
        for (final row in (rows as List).cast<Map>()) {
          final uid = (row['user_id'] ?? '').toString().trim();
          if (uid.isNotEmpty) {
            out[uid] = Map<String, dynamic>.from(row);
          }
        }
        return out;
      } catch (_) {
        // Try a narrower select; optional profile columns differ between DBs.
      }
    }
    return const {};
  }

  static Future<Map<String, dynamic>?> fetchProfileById(
    SupabaseClient sb,
    String id, {
    List<String> columnAttempts = defaultProfileColumns,
  }) async {
    final rows = await fetchProfilesByIds(
      sb,
      [id],
      columnAttempts: columnAttempts,
    );
    return rows[id.trim()];
  }
}
