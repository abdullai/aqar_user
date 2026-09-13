import 'package:supabase_flutter/supabase_flutter.dart';

/// تسميات جهات النشر على بطاقات الإعلان (ضيف + مسجّل) عبر RPC عام.
abstract final class ListingPublisherCardLabelsService {
  static Future<Map<String, ({String label, String entityKind})>> fetchByUserIds(
    SupabaseClient client,
    Iterable<String> userIds,
  ) async {
    final ids = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};

    try {
      final raw = await client.rpc(
        'get_listing_publisher_card_labels',
        params: {'p_user_ids': ids},
      );
      if (raw is! List) return const {};
      final out = <String, ({String label, String entityKind})>{};
      for (final row in raw) {
        if (row is! Map) continue;
        final id = (row['user_id'] ?? '').toString().trim();
        final label = (row['display_label'] ?? '').toString().trim();
        final kind = (row['entity_kind'] ?? 'marketer').toString().trim();
        if (id.isEmpty || label.isEmpty) continue;
        out[id] = (label: label, entityKind: kind.isEmpty ? 'marketer' : kind);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}
