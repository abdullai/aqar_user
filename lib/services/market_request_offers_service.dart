import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications/in_app_notifications.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';

/// عروض المستخدمين على [market_property_requests] (طبقة منتج — توسّع لاحقاً للمحاسبة).
class MarketRequestOffersService {
  MarketRequestOffersService(this._sb);

  final SupabaseClient _sb;

  Future<List<Map<String, dynamic>>> listOffersForRequest(
      String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return const [];

    final res = await _sb
        .from('market_request_offers')
        .select(
          'id,created_at,status,message,price_offer,offerer_id',
        )
        .eq('market_request_id', id)
        .order('created_at', ascending: false);

    final rows = (res as List).cast<Map>();
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// نفس [listOffersForRequest] مع اسم وصورة مقدّم العرض من [users_profiles].
  Future<List<Map<String, dynamic>>> listOffersForRequestEnriched(
    String requestId, {
    bool preferArabicNames = true,
  }) async {
    final raw = await listOffersForRequest(requestId);
    if (raw.isEmpty) return raw;

    final ids = raw
        .map((e) => (e['offerer_id'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return raw;

    final byUser = await UsersProfilesSafeSelect.fetchProfilesByIds(_sb, ids);

    String offererName(Map<String, dynamic>? prof) {
      if (prof == null) return '';
      final row = Map<String, dynamic>.from(prof);
      final a = ProfileGreetingFromRow.displayName(row, isAr: preferArabicNames)
          ?.trim();
      if (a != null && a.isNotEmpty) return a;
      final b =
          ProfileGreetingFromRow.displayName(row, isAr: !preferArabicNames)
              ?.trim();
      if (b != null && b.isNotEmpty) return b;
      final u = (prof['username'] ?? '').toString().trim();
      if (u.isNotEmpty) return u;
      final lic = (prof['license_no'] ?? '').toString().trim();
      if (lic.isNotEmpty) return lic;
      return '';
    }

    return raw.map((o) {
      final oid = (o['offerer_id'] ?? '').toString();
      final prof = byUser[oid];
      return {
        ...o,
        '_offerer_display_name': offererName(prof),
        '_offerer_avatar_url': (prof?['avatar_url'] ?? '').toString().trim(),
        '_offerer_account_type': (prof?['account_type'] ?? '').toString(),
        '_offerer_phone': (prof?['phone'] ?? '').toString().trim(),
        '_offerer_city': (prof?['city'] ?? '').toString().trim(),
        '_offerer_license_no': (prof?['license_no'] ?? '').toString().trim(),
      };
    }).toList(growable: false);
  }

  Future<bool> submitOffer({
    required String marketRequestId,
    String? offerMessage,
    double? priceOffer,
  }) async {
    final rid = marketRequestId.trim();
    if (rid.isEmpty) return false;

    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return false;

    try {
      await _sb.from('market_request_offers').insert({
        'market_request_id': rid,
        'offerer_id': uid,
        'message': (offerMessage ?? '').trim().isEmpty
            ? null
            : (offerMessage ?? '').trim(),
        'price_offer': priceOffer,
        'status': 'submitted',
      });
      await _notifyRequesterOfferSubmitted(rid, uid, updated: false);
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final patch = {
          'message': (offerMessage ?? '').trim().isEmpty
              ? null
              : (offerMessage ?? '').trim(),
          'price_offer': priceOffer,
          'status': 'submitted',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        try {
          await _sb
              .from('market_request_offers')
              .update(patch)
              .eq('market_request_id', rid)
              .eq('offerer_id', uid)
              .inFilter('status', ['submitted', 'pending', 'accepted']);
        } on PostgrestException catch (updateError) {
          final detail = '${updateError.message} ${updateError.details ?? ''}'
              .toLowerCase();
          if (!detail.contains('updated_at')) rethrow;
          patch.remove('updated_at');
          await _sb
              .from('market_request_offers')
              .update(patch)
              .eq('market_request_id', rid)
              .eq('offerer_id', uid)
              .inFilter('status', ['submitted', 'pending', 'accepted']);
        }
        await _notifyRequesterOfferSubmitted(rid, uid, updated: true);
        return true;
      }
      rethrow;
    }
  }

  Future<void> respondOffer({
    required String offerId,
    required bool accept,
  }) async {
    final oid = offerId.trim();
    if (oid.isEmpty) return;
    try {
      await _sb.rpc(
        'respond_market_request_offer',
        params: {
          'p_offer_id': oid,
          'p_action': accept ? 'accept' : 'reject',
        },
      );
    } catch (_) {
      await _respondOfferFallback(offerId: oid, accept: accept);
    }
    await _notifyOfferResponse(offerId: oid, accepted: accept);
  }

  Future<Map<String, dynamic>> updateRequestLimited({
    required String requestId,
    required String title,
    String? description,
    double? budgetMin,
    double? budgetMax,
    double? areaMinM2,
  }) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return const {};
    final res = await _sb.rpc(
      'update_market_property_request_limited',
      params: {
        'p_request_id': rid,
        'p_title': title.trim(),
        'p_description': (description ?? '').trim().isEmpty
            ? null
            : (description ?? '').trim(),
        'p_budget_min': budgetMin,
        'p_budget_max': budgetMax,
        'p_area_min_m2': areaMinM2,
      },
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  Future<void> requestDeletion(String requestId) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return;
    await _sb.rpc(
      'request_delete_market_property_request',
      params: {'p_request_id': rid},
    );
  }

  Future<void> completeRequest({
    required String requestId,
    String? offerId,
  }) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return;
    await _sb.rpc(
      'complete_market_property_request',
      params: {
        'p_request_id': rid,
        'p_offer_id': (offerId ?? '').trim().isEmpty ? null : offerId!.trim(),
      },
    );
    await _notifyRequestCompleted(requestId: rid, offerId: offerId);
  }

  Future<Map<String, dynamic>?> _offerWithRequest(String offerId) async {
    try {
      final row = await _sb
          .from('market_request_offers')
          .select(
            'id,market_request_id,offerer_id,status,'
            'market_property_requests(id,title,requester_id)',
          )
          .eq('id', offerId)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      final row = await _sb
          .from('market_request_offers')
          .select('id,market_request_id,offerer_id,status')
          .eq('id', offerId)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    }
  }

  String _nestedRequestId(Map<String, dynamic> offer) {
    final nested = offer['market_property_requests'];
    if (nested is Map && (nested['id'] ?? '').toString().trim().isNotEmpty) {
      return (nested['id'] ?? '').toString().trim();
    }
    return (offer['market_request_id'] ?? '').toString().trim();
  }

  String _nestedRequestTitle(Map<String, dynamic> offer) {
    final nested = offer['market_property_requests'];
    if (nested is Map) return (nested['title'] ?? '').toString().trim();
    return '';
  }

  Future<void> _respondOfferFallback({
    required String offerId,
    required bool accept,
  }) async {
    final offer = await _offerWithRequest(offerId);
    if (offer == null) return;
    final rid = _nestedRequestId(offer);
    if (rid.isEmpty) return;

    if (accept) {
      await _sb.from('market_request_offers').update({
        'status': 'accepted',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', offerId);
      await _sb
          .from('market_request_offers')
          .update({
            'status': 'rejected',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('market_request_id', rid)
          .neq('id', offerId)
          .inFilter('status', ['submitted', 'pending']);
      await _sb.from('market_property_requests').update({
        'status': 'completed',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rid);
    } else {
      await _sb.from('market_request_offers').update({
        'status': 'rejected',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', offerId);
    }
  }

  Future<void> _notifyRequesterOfferSubmitted(
    String requestId,
    String offererId, {
    required bool updated,
  }) async {
    try {
      final req = await _sb
          .from('market_property_requests')
          .select('id,title,requester_id')
          .eq('id', requestId)
          .maybeSingle();
      final requesterId = (req?['requester_id'] ?? '').toString().trim();
      if (requesterId.isEmpty || requesterId == offererId) return;
      final title = (req?['title'] ?? '').toString().trim();
      await InAppNotificationWriter.insert(
        _sb,
        userId: requesterId,
        type: updated ? 'market_request_offer_updated' : 'market_request_offer',
        entityType: 'market_request_offer',
        entityId: requestId,
        data: {
          'kind': 'workflow',
          'main_tab': 'my_ads',
          'deep_route': 'market_request',
          'request_id': requestId,
          'offerer_id': offererId,
          'title_ar': updated ? 'تم تحديث عرض على طلبك' : 'وصلك عرض جديد',
          'title_en': updated ? 'Offer updated' : 'New offer received',
          'body_ar': title.isEmpty
              ? 'افتح طلبك لمراجعة بطاقة العرض واختيار الأنسب.'
              : 'افتح "$title" لمراجعة بطاقة العرض واختيار الأنسب.',
          'body_en': title.isEmpty
              ? 'Open your request to review the offer card.'
              : 'Open "$title" to review the offer card.',
        },
      );
    } catch (_) {}
  }

  Future<void> _notifyOfferResponse({
    required String offerId,
    required bool accepted,
  }) async {
    try {
      final offer = await _offerWithRequest(offerId);
      if (offer == null) return;
      final offererId = (offer['offerer_id'] ?? '').toString().trim();
      if (offererId.isEmpty) return;
      final rid = _nestedRequestId(offer);
      final title = _nestedRequestTitle(offer);
      await InAppNotificationWriter.insert(
        _sb,
        userId: offererId,
        type: accepted
            ? 'market_request_offer_accepted'
            : 'market_request_offer_rejected',
        entityType: 'market_request_offer',
        entityId: offerId,
        data: {
          'kind': 'workflow',
          'main_tab': 'cart',
          'deep_route': 'market_request',
          'request_id': rid,
          'offer_id': offerId,
          'status': accepted ? 'accepted' : 'rejected',
          'title_ar': accepted
              ? 'تمت الموافقة على طلبك لإتمام الصفقة'
              : 'لم يتم اختيار عرضك',
          'title_en': accepted
              ? 'Your offer was accepted'
              : 'Your offer was not selected',
          'body_ar': accepted
              ? (title.isEmpty
                  ? 'افتح صفقاتك لمتابعة إتمام الصفقة.'
                  : 'تم قبول عرضك على "$title". افتح صفقاتك للمتابعة.')
              : (title.isEmpty
                  ? 'اختار صاحب الطلب عرضاً آخر.'
                  : 'اختار صاحب الطلب عرضاً آخر على "$title".'),
          'body_en': accepted
              ? (title.isEmpty
                  ? 'Open My deals to continue.'
                  : 'Your offer on "$title" was accepted. Open My deals.')
              : (title.isEmpty
                  ? 'The requester selected another offer.'
                  : 'The requester selected another offer for "$title".'),
        },
      );
    } catch (_) {}
  }

  Future<void> _notifyRequestCompleted({
    required String requestId,
    String? offerId,
  }) async {
    try {
      final rid = requestId.trim();
      if (rid.isEmpty) return;
      String oid = (offerId ?? '').trim();
      if (oid.isEmpty) {
        final req = await _sb
            .from('market_property_requests')
            .select('selected_offer_id')
            .eq('id', rid)
            .maybeSingle();
        oid = (req?['selected_offer_id'] ?? '').toString().trim();
      }
      if (oid.isEmpty) return;
      final offer = await _offerWithRequest(oid);
      if (offer == null) return;
      final offererId = (offer['offerer_id'] ?? '').toString().trim();
      if (offererId.isEmpty) return;
      final title = _nestedRequestTitle(offer);
      await InAppNotificationWriter.insert(
        _sb,
        userId: offererId,
        type: 'market_request_deal_completed',
        entityType: 'market_request_offer',
        entityId: oid,
        data: {
          'kind': 'workflow',
          'main_tab': 'cart',
          'deep_route': 'market_request',
          'request_id': rid,
          'offer_id': oid,
          'status': 'completed',
          'title_ar': 'تم إتمام الصفقة',
          'title_en': 'Deal completed',
          'body_ar': title.isEmpty
              ? 'تم إغلاق الطلب وإتمام الصفقة. افتح صفقاتك للاطلاع.'
              : 'تم إتمام الصفقة على "$title". افتح صفقاتك للاطلاع.',
          'body_en': title.isEmpty
              ? 'The request was closed as completed. Open My deals.'
              : 'The deal for "$title" was completed. Open My deals.',
        },
      );
    } catch (_) {}
  }
}
