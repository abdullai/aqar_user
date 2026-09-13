import 'package:supabase_flutter/supabase_flutter.dart';

import 'open_accepted_deal.dart';

/// صفقات مقبولة بانتظار تأكيد الإتمام (المالك والشريك المختار).
abstract final class DealCompletionInbox {
  static Future<List<OpenAcceptedDeal>> load(SupabaseClient sb) async {
    try {
      final raw = await sb.rpc('open_accepted_deals_for_me');
      final list = _asList(raw);
      return list
          .map(OpenAcceptedDeal.fromJson)
          .where((d) => d.id.isNotEmpty && d.kind.isNotEmpty)
          .toList();
    } catch (_) {
      return _fallback(sb);
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map && raw['deals'] is List) {
      return (raw['deals'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  static Future<int> activeDealCount(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return 0;
    try {
      final pair = await Future.wait([
        sb
            .from('reservations')
            .select('id')
            .eq('user_id', uid)
            .inFilter('status', ['pending', 'paid', 'accepted']),
        sb
            .from('market_request_offers')
            .select('id')
            .eq('offerer_id', uid)
            .inFilter('status', [
          'submitted',
          'pending',
          'accepted',
          'approved',
          'selected',
        ]),
      ]);
      return (pair[0] as List).length + (pair[1] as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> hasActiveOfferOnRequest({
    required SupabaseClient sb,
    required String requestId,
  }) async {
    final uid = sb.auth.currentUser?.id ?? '';
    final rid = requestId.trim();
    if (uid.isEmpty || rid.isEmpty) return false;
    try {
      final rows = await sb
          .from('market_request_offers')
          .select('id')
          .eq('offerer_id', uid)
          .eq('market_request_id', rid)
          .inFilter('status', [
        'submitted',
        'pending',
        'accepted',
        'approved',
        'selected',
      ])
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<List<OpenAcceptedDeal>> _fallback(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return const [];
    final out = <OpenAcceptedDeal>[];
    try {
      final rows = await sb
          .from('reservations')
          .select('id,property_id,user_id,status,properties(title,owner_id)')
          .eq('status', 'accepted');
      for (final raw in (rows as List)) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final nested = m['properties'];
        final title = nested is Map ? (nested['title'] ?? '').toString() : '';
        final ownerId =
            nested is Map ? (nested['owner_id'] ?? '').toString() : '';
        final buyer = (m['user_id'] ?? '').toString();
        if (buyer != uid && ownerId != uid) continue;
        out.add(
          OpenAcceptedDeal(
            kind: 'listing',
            id: (m['id'] ?? '').toString(),
            title: title,
            role: buyer == uid ? 'partner' : 'owner',
            propertyId: (m['property_id'] ?? '').toString(),
          ),
        );
      }
    } catch (_) {}
    try {
      final rows = await sb
          .from('market_request_offers')
          .select(
            'id,market_request_id,offerer_id,status,'
            'market_property_requests(title,status,requester_id,selected_offer_id)',
          )
          .inFilter('status', ['accepted', 'approved', 'selected']);
      for (final raw in (rows as List)) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final nested = m['market_property_requests'];
        final reqSt = nested is Map
            ? (nested['status'] ?? '').toString().toLowerCase().trim()
            : '';
        if (reqSt == 'completed' ||
            reqSt == 'cancelled' ||
            reqSt == 'canceled' ||
            reqSt == 'closed') {
          continue;
        }
        final title = nested is Map ? (nested['title'] ?? '').toString() : '';
        final requesterId =
            nested is Map ? (nested['requester_id'] ?? '').toString() : '';
        final offerer = (m['offerer_id'] ?? '').toString();
        if (offerer != uid && requesterId != uid) continue;
        out.add(
          OpenAcceptedDeal(
            kind: 'market_request',
            id: (m['id'] ?? '').toString(),
            title: title,
            role: offerer == uid ? 'partner' : 'owner',
            requestId: (m['market_request_id'] ?? '').toString(),
            offerId: (m['id'] ?? '').toString(),
          ),
        );
      }
    } catch (_) {}
    return out;
  }
}
