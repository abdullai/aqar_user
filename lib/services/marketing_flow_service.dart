// lib/services/marketing_flow_service.dart
//
// Marketing / REGA workflow calls the Supabase PostgREST + RPC layer (JSON over HTTPS,
// auth via Supabase session). Heavy or third-party integrations belong in Edge Functions
// or external microservices; this client stays a thin, typed facade.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/contracts/marketing_contract_template.dart';
import '../core/notifications/in_app_notifications.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../core/workflow/listing_workflow.dart';
import '../shared/core/supabase_schema_selects.dart';

class MarketingFlowService {
  final SupabaseClient sb;
  MarketingFlowService(this.sb);

  // ----------------------------
  // Helpers
  // ----------------------------
  List<Map<String, dynamic>> _asListOfMaps(dynamic rows) {
    final list = (rows as List);
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Map<String, dynamic> _asMap(dynamic row) {
    return Map<String, dynamic>.from(row as Map);
  }

  /// بعض المشاريع تستخدم `listing_request_id` بدل `request_id`؛ واختلاف أسماء الأعمدة
  /// في `select(...)` يسبب PostgREST 400.
  Future<List<Map<String, dynamic>>> _listingInvitesForRequestId(
    String requestId,
  ) async {
    Future<List<Map<String, dynamic>>> pull(String fk) async {
      final rows = await sb
          .from('listing_request_invites')
          .select()
          .eq(fk, requestId)
          .order('created_at', ascending: false);
      return _asListOfMaps(rows);
    }

    for (final fk in const ['request_id', 'listing_request_id']) {
      try {
        final list = await pull(fk);
        for (final m in list) {
          final lr = m['listing_request_id'];
          final rr = m['request_id'];
          final rrs = rr == null ? '' : rr.toString().trim();
          if (rrs.isEmpty && lr != null) {
            m['request_id'] = lr;
          }
        }
        return list;
      } catch (_) {}
    }
    return [];
  }

  String _marketerDisplayName(
    Map<String, dynamic>? p, {
    bool preferArabic = true,
  }) {
    if (p == null) return '';
    final row = Map<String, dynamic>.from(p);
    final primary =
        ProfileGreetingFromRow.displayName(row, isAr: preferArabic)?.trim();
    if (primary != null && primary.isNotEmpty) return primary;
    final alt =
        ProfileGreetingFromRow.displayName(row, isAr: !preferArabic)?.trim();
    if (alt != null && alt.isNotEmpty) return alt;
    for (final k in const [
      'full_name_ar',
      'full_name_en',
      'full_name',
    ]) {
      final s = (p[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    final user = (p['username'] ?? '').toString().trim();
    if (user.isNotEmpty) return user;
    final phone = (p['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    final lic = (p['license_no'] ?? '').toString().trim();
    if (lic.isNotEmpty) return lic;
    return '';
  }

  Future<Map<String, Map<String, dynamic>>> _usersProfilesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final uniq = ids.toSet().toList();
    return UsersProfilesSafeSelect.fetchProfilesByIds(sb, uniq);
  }

  String _contractEntityTypeLabel(Map<String, dynamic>? row, bool isAr) {
    final type = (row?['account_type'] ?? '').toString().trim().toLowerCase();
    switch (type) {
      case 'office':
      case 'brokerage_office':
        return isAr ? 'مكتب عقاري' : 'Real estate office';
      case 'company':
        return isAr ? 'شركة عقارية' : 'Real estate company';
      case 'establishment':
      case 'institution':
        return isAr ? 'مؤسسة عقارية' : 'Real estate establishment';
      case 'marketer':
        return isAr ? 'مسوق عقاري مرخص' : 'Licensed real estate marketer';
      default:
        return isAr ? 'مسوق عقاري' : 'Real estate marketer';
    }
  }

  Future<
      ({
        String ownerName,
        String marketerName,
        String marketerEntityType,
        String marketerLicenseNo,
      })> _contractPartiesContext({
    required String ownerId,
    required String marketerId,
    required bool isAr,
  }) async {
    final profs = await _usersProfilesByIds([ownerId, marketerId]);
    final owner = profs[ownerId];
    final marketer = profs[marketerId];
    return (
      ownerName: _marketerDisplayName(owner, preferArabic: isAr),
      marketerName: _marketerDisplayName(marketer, preferArabic: isAr),
      marketerEntityType: _contractEntityTypeLabel(marketer, isAr),
      marketerLicenseNo: (marketer?['license_no'] ?? '').toString().trim(),
    );
  }

  String _uidOrThrow() {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Not authenticated');
    }
    return uid;
  }

  // ----------------------------
  // Role
  // ----------------------------
  Future<bool> isMarketer() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await sb
        .from('marketer_profiles')
        .select('user_id')
        .eq('user_id', uid)
        .maybeSingle();
    return row != null;
  }

  // ----------------------------
  // Owner: Requests
  // ----------------------------
  Future<String> createListingRequest({
    required String title,
    required String city,
    required double lat,
    required double lng,
    Map<String, dynamic>? payloadJson,
  }) async {
    final uid = _uidOrThrow();
    final inserted = await sb
        .from('listing_requests')
        .insert({
          'owner_id': uid,
          'title': title,
          'city': city,
          'lat': lat,
          'lng': lng,
          'status': 'new',
          // طلب جديد: إقرار تنظيمي تلقائي (لا يُشترط توثيق مسوّق لطلب الإعلان).
          'owner_regulatory_ack_at': DateTime.now().toUtc().toIso8601String(),
          if (payloadJson != null) 'payload_json': payloadJson,
        })
        .select('id')
        .single();

    final map = _asMap(inserted);
    return map['id'] as String;
  }

  /// إقرار تنظيمي لطلبات قديمة (owner_regulatory_ack_at كان NULL) — مرة واحدة.
  Future<void> ownerAckListingRequestRegulatoryAck({
    required String requestId,
  }) async {
    await sb.rpc(
      'listing_request_owner_ack_regulatory',
      params: {'p_request_id': requestId},
    );
  }

  Future<List<Map<String, dynamic>>> ownerMyRequests() async {
    final uid = _uidOrThrow();
    final rows = await sb
        .from('listing_requests')
        .select(
          'id,title,city,status,created_at,selected_marketer_id,contract_id,permits_due_at',
        )
        .eq('owner_id', uid)
        .order('created_at', ascending: false);

    return _asListOfMaps(rows);
  }

  Future<Map<String, dynamic>?> requestById(String requestId) async {
    final row = await sb
        .from('listing_requests')
        .select(
          'id,owner_id,title,city,lat,lng,status,workflow_stage,selected_offer_id,selected_marketer_id,contract_id,permits_due_at,created_at',
        )
        .eq('id', requestId)
        .maybeSingle();

    if (row == null) return null;
    return _asMap(row);
  }

  // ----------------------------
  // Owner: Offers
  // ----------------------------
  Future<List<Map<String, dynamic>>> ownerOffers(String requestId) async {
    final rows = await sb
        .from('listing_offers')
        .select(
          'id,marketer_id,price,notes,status,created_at,expires_at,'
          'offer_amount,commission_type,commission_value,marketer_type,round_no,updated_at,owner_responded_at,'
          'owner_decline_reason',
        )
        .eq('request_id', requestId)
        .order('created_at', ascending: false);

    return _asListOfMaps(rows);
  }

  /// عروض الطلب مع محاولة جلب اسم المسوق من `users_profiles` (آمن إن اختلفت الأعمدة).
  Future<List<Map<String, dynamic>>> ownerOffersEnriched(
    String requestId, {
    bool preferArabicNames = true,
  }) async {
    final offers = await ownerOffers(requestId);
    if (offers.isEmpty) return offers;

    final ids = offers
        .map((e) => (e['marketer_id'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return offers;

    final byUser = await _usersProfilesByIds(ids);

    return offers.map((o) {
      final mid = (o['marketer_id'] ?? '').toString();
      final prof = byUser[mid];
      return {
        ...o,
        '_marketer_display_name':
            _marketerDisplayName(prof, preferArabic: preferArabicNames),
        '_marketer_account_type': (prof?['account_type'] ?? '').toString(),
        '_marketer_phone': (prof?['phone'] ?? '').toString().trim(),
        '_marketer_avatar_url': (prof?['avatar_url'] ?? '').toString().trim(),
        '_marketer_license_no': (prof?['license_no'] ?? '').toString().trim(),
      };
    }).toList();
  }

  /// عروضي النشطة على طلبات سوق الآخرين (متابعة قبول/رفض من السلة).
  Future<List<Map<String, dynamic>>> myActiveMarketRequestOffers() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return const [];

    try {
      dynamic rows;
      try {
        rows = await sb
            .from('market_request_offers')
            .select(
              'id,market_request_id,status,created_at,message,price_offer,'
              'market_property_requests(title,status,selected_offer_id)',
            )
            .eq('offerer_id', uid)
            .order('created_at', ascending: false);
      } catch (_) {
        rows = await sb
            .from('market_request_offers')
            .select(
              'id,market_request_id,status,created_at,message,price_offer',
            )
            .eq('offerer_id', uid)
            .order('created_at', ascending: false);
      }

      final list = _asListOfMaps(rows);
      return list.map((m) {
        final nested = m['market_property_requests'];
        String title = '';
        String requestStatus = '';
        String selectedOfferId = '';
        if (nested is Map) {
          title = (nested['title'] ?? '').toString().trim();
          requestStatus = (nested['status'] ?? '').toString().trim();
          selectedOfferId =
              (nested['selected_offer_id'] ?? '').toString().trim();
        }
        return {
          ...m,
          if (title.isNotEmpty) '_request_title': title,
          if (requestStatus.isNotEmpty) '_request_status': requestStatus,
          if (selectedOfferId.isNotEmpty) '_selected_offer_id': selectedOfferId,
        };
      }).where((m) {
        final st = (m['status'] ?? '').toString().toLowerCase().trim();
        final requestSt =
            (m['_request_status'] ?? '').toString().toLowerCase().trim();
        final selectedOfferId =
            (m['_selected_offer_id'] ?? '').toString().trim();
        final offerId = (m['id'] ?? '').toString().trim();
        if (requestSt == 'completed' &&
            selectedOfferId.isNotEmpty &&
            selectedOfferId != offerId) {
          return false;
        }
        return st.isEmpty ||
            st == 'submitted' ||
            st == 'pending' ||
            st == 'accepted' ||
            st == 'approved' ||
            st == 'selected' ||
            st == 'completed';
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// صف واحد من `market_property_requests` (مثلاً فتح الطلب من السلة بعد إخفائه عن الرئيسية).
  Future<Map<String, dynamic>?> marketPropertyRequestSnapshotById(
      String id) async {
    final clean = id.trim();
    if (clean.isEmpty) return null;

    bool missingColumn(Object e, String col) {
      final s = e.toString().toLowerCase();
      return s.contains(col.toLowerCase()) &&
          (s.contains('column') ||
              s.contains('schema') ||
              s.contains('could not find'));
    }

    const selFull = 'id,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,request_priority,details_json,status,'
        'request_public_code,edit_count,max_edits,deletion_requested_at,'
        'completed_at,selected_offer_id';
    const selMid = 'id,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,request_priority,status,'
        'request_public_code,edit_count,max_edits,deletion_requested_at,'
        'completed_at,selected_offer_id';
    const selLegacy =
        'id,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,status';

    Future<Map<String, dynamic>?> one(String cols) async {
      final row = await sb
          .from('market_property_requests')
          .select(cols)
          .eq('id', clean)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    }

    try {
      Map<String, dynamic>? m;
      try {
        m = await one(selFull);
      } catch (e) {
        if (missingColumn(e, 'request_public_code') ||
            missingColumn(e, 'edit_count') ||
            missingColumn(e, 'selected_offer_id')) {
          m = await one(selLegacy);
        } else if (missingColumn(e, 'details_json')) {
          try {
            m = await one(selMid);
          } catch (e2) {
            if (missingColumn(e2, 'request_public_code') ||
                missingColumn(e2, 'edit_count') ||
                missingColumn(e2, 'selected_offer_id') ||
                missingColumn(e2, 'request_priority')) {
              m = await one(selLegacy);
            } else {
              rethrow;
            }
          }
        } else if (missingColumn(e, 'request_priority')) {
          m = await one(selLegacy);
        } else {
          rethrow;
        }
      }
      if (m == null) return null;
      final uid = (m['requester_id'] ?? '').toString().trim();
      if (uid.isNotEmpty) {
        final profiles = await UsersProfilesSafeSelect.fetchProfilesByIds(
          sb,
          [uid],
        );
        final url = (profiles[uid]?['avatar_url'] ?? '').toString().trim();
        if (url.isNotEmpty) m['requester_avatar_url'] = url;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> ownerListingRequestSnapshot(
      String requestId) async {
    final row = await sb
        .from('listing_requests')
        .select(SupabaseSchemaSelects.listingRequestsLookup)
        .eq('id', requestId)
        .maybeSingle();
    if (row == null) return null;
    return _asMap(row);
  }

  /// عقود التسويق المرتبطة بالطلب (للمالك — يعتمد RLS).
  Future<List<Map<String, dynamic>>> contractsForListingRequest(
    String requestId,
  ) async {
    try {
      final rows = await sb
          .from('listing_contracts')
          .select(
            'id,request_id,owner_id,marketer_id,offer_id,status,'
            'created_at,updated_at,sent_at,owner_signed_at,marketer_signed_at,'
            'returned_at,cancelled_at',
          )
          .eq('request_id', requestId)
          .order('created_at', ascending: false);
      return _asListOfMaps(rows);
    } catch (_) {
      return [];
    }
  }

  /// دعوات المسوّقين لهذا الطلب.
  Future<List<Map<String, dynamic>>> ownerInvitesForRequest(
    String requestId,
  ) async {
    try {
      return await _listingInvitesForRequestId(requestId);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> ownerInvitesEnriched(
    String requestId, {
    bool preferArabicNames = true,
  }) async {
    final invites = await ownerInvitesForRequest(requestId);
    if (invites.isEmpty) return invites;

    final ids = invites
        .map((e) => (e['marketer_id'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return invites;

    final byUser = await _usersProfilesByIds(ids);

    return invites.map((i) {
      final mid = (i['marketer_id'] ?? '').toString();
      final prof = byUser[mid];
      return {
        ...i,
        '_marketer_display_name':
            _marketerDisplayName(prof, preferArabic: preferArabicNames),
        '_marketer_account_type': (prof?['account_type'] ?? '').toString(),
        '_marketer_phone': (prof?['phone'] ?? '').toString().trim(),
      };
    }).toList();
  }

  /// تتبع موحّد للمالك: طلب محدّث، دعوات، عروض، عقود، عقار مرتبط.
  Future<Map<String, dynamic>> ownerRequestActivityBundle(
    String requestId,
  ) async {
    final req = await ownerListingRequestSnapshot(requestId);
    final offers = await ownerOffersEnriched(requestId);
    final invites = await ownerInvitesEnriched(requestId);
    final contractsRaw = await contractsForListingRequest(requestId);
    final linkedProperty = await linkedPropertyForListingRequest(requestId);

    final ids = <String>{};
    for (final c in contractsRaw) {
      final m = (c['marketer_id'] ?? '').toString().trim();
      if (m.isNotEmpty) ids.add(m);
    }
    final byUser = await _usersProfilesByIds(ids.toList());
    final contracts = contractsRaw.map((c) {
      final mid = (c['marketer_id'] ?? '').toString().trim();
      final prof = byUser[mid];
      return {
        ...c,
        '_marketer_display_name':
            _marketerDisplayName(prof, preferArabic: true),
      };
    }).toList();

    return {
      'request': req,
      'offers': offers,
      'contracts': contracts,
      'invites': invites,
      'linkedProperty': linkedProperty,
    };
  }

  /// أحدث عقار مرتبط بالطلب (رقم الإعلان، السعر، صورة الغلاف).
  Future<Map<String, dynamic>?> linkedPropertyForListingRequest(
    String requestId,
  ) async {
    try {
      final rows = await sb
          .from('properties')
          .select(
            'id,price,listing_public_code,title,city,location,address_line,'
            'property_images(path,file_name,sort_order)',
          )
          .eq('request_id', requestId)
          .order('created_at', ascending: false)
          .limit(1);
      final list = _asListOfMaps(rows);
      if (list.isEmpty) return null;
      return list.first;
    } catch (_) {
      return null;
    }
  }

  /// ينشئ `listing_contracts` بحالة `draft` ويبقي `workflow_stage = marketer_selected`.
  Future<String> createListingContractFromOffer(String offerId) async {
    final res = await sb.rpc(
      'create_listing_contract_from_offer',
      params: {'p_offer_id': offerId},
    );
    if (res == null) {
      throw Exception('create_listing_contract_from_offer: empty response');
    }
    return res.toString();
  }

  /// يملأ نص مسودة العقد بعد إنشاء الصف عبر RPC؛ لا ينشئ عقداً جديداً.
  Future<void> ensureListingContractDraftText({
    required String contractId,
    required String requestId,
    required String offerId,
    required bool isAr,
  }) async {
    final req = await sb
        .from('listing_requests')
        .select('owner_id,title,city,selected_marketer_id')
        .eq('id', requestId)
        .maybeSingle();
    final offer = await sb
        .from('listing_offers')
        .select('price,notes,marketer_id')
        .eq('id', offerId)
        .eq('request_id', requestId)
        .maybeSingle();
    if (req == null || offer == null) return;

    final fee = (offer['price'] is num)
        ? (offer['price'] as num).toDouble()
        : double.tryParse('${offer['price']}') ?? 0.0;
    final notes = (offer['notes'] ?? '').toString();
    final now = DateTime.now().toUtc();
    final parties = await _contractPartiesContext(
      ownerId: (req['owner_id'] ?? '').toString(),
      marketerId: (offer['marketer_id'] ?? req['selected_marketer_id'] ?? '')
          .toString(),
      isAr: isAr,
    );
    final body = MarketingContractTemplate.build(
      isAr: isAr,
      contractId: contractId,
      requestId: requestId,
      listingTitle: (req['title'] ?? '').toString(),
      city: (req['city'] ?? '').toString(),
      marketingFee: fee,
      currency: 'SAR',
      ownerName: parties.ownerName,
      marketerName: parties.marketerName,
      marketerEntityType: parties.marketerEntityType,
      marketerLicenseNo: parties.marketerLicenseNo,
      offerNotes: notes.isEmpty ? null : notes,
      signatureDateIso: now.toIso8601String().split('T').first,
    );

    await sb.from('listing_contracts').update({
      'contract_text': body,
      'updated_at': now.toIso8601String(),
    }).eq('id', contractId);
  }

  Future<void> ownerSelectOffer({
    required String requestId,
    required String offerId,
  }) async {
    await sb.rpc('owner_select_offer', params: {
      'p_request_id': requestId,
      'p_offer_id': offerId,
    });
  }

  // ----------------------------
  // Contracts
  // ----------------------------
  Future<Map<String, dynamic>?> contractById(String contractId) async {
    final row = await sb
        .from('listing_contracts')
        .select(
          'id,request_id,owner_id,marketer_id,offer_id,status,'
          'contract_text,contract_pdf_url,'
          'owner_signed_at,marketer_signed_at,sent_at,returned_at,returned_reason,'
          'cancelled_at,cancelled_reason,created_at,updated_at',
        )
        .eq('id', contractId)
        .maybeSingle();

    if (row == null) return null;
    return _asMap(row);
  }

  Future<void> sendListingContractToOwner(String contractId) async {
    await sb.rpc(
      'send_listing_contract_to_owner',
      params: {'p_contract_id': contractId},
    );
  }

  Future<void> ownerReturnListingContract({
    required String contractId,
    String? reason,
  }) async {
    await sb.rpc(
      'owner_return_listing_contract',
      params: {
        'p_contract_id': contractId,
        'p_reason': reason,
      },
    );
  }

  Future<void> ownerSignListingContract(String contractId) async {
    await sb.rpc(
      'owner_sign_listing_contract',
      params: {'p_contract_id': contractId},
    );
  }

  Future<void> cancelListingContract({
    required String contractId,
    String? reason,
  }) async {
    await sb.rpc(
      'cancel_listing_contract',
      params: {
        'p_contract_id': contractId,
        'p_reason': reason,
      },
    );
  }

  /// بلاغ عدم مطابقة ترخيص الإعلان مع فال/REGA — يزيد العداد؛ عند 3 يُفسَخ العقد غير الموقّع (خادم).
  Future<Map<String, dynamic>> reportRegaLicenseMismatch(
      String requestId) async {
    final res = await sb.rpc(
      'report_rega_license_mismatch',
      params: {'p_request_id': requestId},
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) {
      return Map<String, dynamic>.from(
        res.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return <String, dynamic>{'ok': res != null};
  }

  /// بعد `contract_signed`: إنشاء/ترقية `properties` و`workflow_stage = published`.
  Future<String> publishPropertyFromContract(String contractId) async {
    final res = await sb.rpc(
      'publish_property_from_contract',
      params: {'p_contract_id': contractId},
    );
    if (res == null) {
      throw Exception('publish_property_from_contract: empty response');
    }
    return res.toString();
  }

  /// @deprecated Use [ownerSignListingContract] (RPC `owner_sign_listing_contract`).
  Future<void> ownerSignContract(String contractId) async {
    await ownerSignListingContract(contractId);
  }

  /// غير مستخدم في مسار `contract_status` الحالي (التوقيع عبر [ownerSignListingContract] فقط لهذه المرحلة).
  Future<void> marketerSignContract(String contractId) async {
    throw UnsupportedError(
      'marketerSignContract is not part of the current listing contract_status flow',
    );
  }

  // ----------------------------
  // Marketer: Invites (list)
  // ----------------------------
  Future<List<Map<String, dynamic>>> marketerInvites() async {
    final uid = _uidOrThrow();
    final rows = await sb
        .from('listing_request_invites')
        .select(
          'id,request_id,status,created_at,'
          'listing_requests(id,title,city,status,workflow_stage)',
        )
        .eq('marketer_id', uid)
        .order('created_at', ascending: false);

    return _asListOfMaps(rows);
  }

  Future<void> markInviteSeen(String inviteId) async {
    try {
      await sb.rpc('mark_invite_seen', params: {'p_invite_id': inviteId});
    } catch (e, st) {
      // الدالة قد لا تكون منشورة بعد على مشروع Supabase (404) — لا نكسر التدفق.
      if (kDebugMode) {
        debugPrint('mark_invite_seen skipped: $e\n$st');
      }
    }
  }

  // ----------------------------
  // Marketer: Invite details + accept + direct offer (NEW)
  // ملاحظة: هذه الدوال "مباشرة" بدون RPC، لتخدم صفحات التفاصيل بسهولة.
  // إذا تفضل كل شيء عبر RPC، يمكن لاحقًا تحويلها لاستدعاء دوالك الموجودة.
  // ----------------------------

  /// يرجع: { invite: {...}, request: {...} }
  /// يعتمد على وجود relationship FK بين invites.request_id و requests.id.
  ///
  /// إن كان [inviteId] غير صالح (مثلاً وُضع `id` لصف عرض بدل دعوة)، يُعاد البحث
  /// بـ [fallbackRequestId] + `marketer_id` ثم تحميل الطلب مباشرة إن لزم.
  Future<Map<String, dynamic>> marketerInviteDetails(
    String inviteId, {
    String? fallbackRequestId,
  }) async {
    final uid = _uidOrThrow();

    final reqEmbed = SupabaseSchemaSelects.listingRequestsLookup
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final invCols =
        'id, request_id, marketer_id, status, created_at, updated_at, listing_requests ($reqEmbed)';
    final invColsAlt =
        'id, listing_request_id, marketer_id, status, created_at, updated_at, listing_requests ($reqEmbed)';

    dynamic inv;
    final idTrim = inviteId.trim();
    if (idTrim.isNotEmpty) {
      try {
        inv = await sb
            .from('listing_request_invites')
            .select(invCols)
            .eq('id', idTrim)
            .eq('marketer_id', uid)
            .maybeSingle();
      } catch (_) {
        try {
          inv = await sb
              .from('listing_request_invites')
              .select(invColsAlt)
              .eq('id', idTrim)
              .eq('marketer_id', uid)
              .maybeSingle();
        } catch (_) {}
      }
    }

    final reqTrim = (fallbackRequestId ?? '').trim();
    if (inv == null && reqTrim.isNotEmpty) {
      try {
        inv = await sb
            .from('listing_request_invites')
            .select(invCols)
            .eq('request_id', reqTrim)
            .eq('marketer_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {
        try {
          inv = await sb
              .from('listing_request_invites')
              .select(invColsAlt)
              .eq('listing_request_id', reqTrim)
              .eq('marketer_id', uid)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (_) {}
      }
    }

    Map<String, dynamic>? reqOnly;
    if (inv == null && reqTrim.isNotEmpty) {
      try {
        final row = await sb
            .from('listing_requests')
            .select(reqEmbed)
            .eq('id', reqTrim)
            .maybeSingle();
        if (row != null) {
          reqOnly = Map<String, dynamic>.from(row as Map);
        }
      } catch (_) {}
    }

    if (inv == null) {
      if (reqOnly != null) {
        return {
          'invite': <String, dynamic>{
            'id': '',
            'request_id': reqTrim,
            'marketer_id': uid,
            'status': 'seen',
          },
          'request': reqOnly,
        };
      }
      throw Exception('Invite not found');
    }

    final invMap = (inv as Map).cast<String, dynamic>();
    final rid = invMap['request_id'] ?? invMap['listing_request_id'];
    if (rid != null) {
      invMap['request_id'] = rid;
    }
    final reqMap =
        (invMap['listing_requests'] as Map?)?.cast<String, dynamic>();

    return {
      'invite': invMap,
      'request': reqMap,
    };
  }

  /// قبول الدعوة بتحديث جدول listing_request_invites
  Future<void> acceptInvite(String inviteId) async {
    final uid = _uidOrThrow();

    await sb
        .from('listing_request_invites')
        .update({
          // enum invite_status في البيئة الحالية لا يحتوي accepted.
          // seen تعني أن المسوق اطّلع/اعتمد الدعوة قبل إرسال العرض.
          'status': 'seen',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', inviteId)
        .eq('marketer_id', uid);
  }

  /// إرسال عرض مباشرة عبر insert ثم تحديث حالة الدعوة
  /// افتراض الحقول: listing_offers(request_id, invite_id, marketer_id, price, notes/message, created_at)
  /// عدّل keys حسب جدولك (عندك في الخدمة السابقة notes).
  Future<void> submitOfferDirect({
    required String inviteId,
    required String requestId,
    required double price,
    required String notes,
  }) async {
    final uid = _uidOrThrow();

    await sb.from('listing_offers').insert({
      'request_id': requestId,
      'invite_id': inviteId,
      'marketer_id': uid,
      'price': price,
      'notes': notes, // عندك في ownerOffers اسمها notes
      'status': 'submitted',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    await sb
        .from('listing_request_invites')
        .update({
          'status': 'seen',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', inviteId)
        .eq('marketer_id', uid);
  }

  // ----------------------------
  // Marketer: Offers + Permits (RPC)
  // ----------------------------
  /// هل للمسوق الحالي عرض نشط في جولة الطلب الحالية؟
  Future<bool> marketerHasLiveOfferForRequestRound(String requestId) async {
    final uid = _uidOrThrow();
    final req = await sb
        .from('listing_requests')
        .select('marketing_round')
        .eq('id', requestId)
        .maybeSingle();
    final round =
        (req == null) ? 1 : ((req['marketing_round'] as num?)?.toInt() ?? 1);
    final rows = await sb
        .from('listing_offers')
        .select('id,round_no')
        .eq('request_id', requestId)
        .eq('marketer_id', uid)
        .inFilter('status', ['submitted', 'pending']);
    final list = _asListOfMaps(rows);
    for (final o in list) {
      final rno = (o['round_no'] as num?)?.toInt() ?? 1;
      if (rno == round) return true;
    }
    return false;
  }

  Future<String> marketerSubmitOffer({
    required String requestId,
    required double price,
    required String notes,
  }) async {
    try {
      final res = await sb.rpc(
        'submit_listing_offer',
        params: {
          'p_request_id': requestId,
          'p_offer_amount': price,
          'p_notes': notes,
        },
      );
      if (res is String) return res;
      if (res is Map && res['id'] != null) return res['id'].toString();
      return res.toString();
    } catch (_) {
      final res = await sb.rpc('marketer_submit_offer', params: {
        'p_request_id': requestId,
        'p_price': price,
        'p_notes': notes,
      });
      if (res is String) return res;
      if (res is Map && res['id'] != null) return res['id'].toString();
      return res.toString();
    }
  }

  /// قبول عرض (تحديث مرحلة الطلب) دون مسار العقد الكامل.
  Future<void> acceptListingOfferById(String offerId) async {
    // الإشعار يُنشأ داخل RPC `accept_listing_offer` (لا تكرار من Dart).
    await sb.rpc('accept_listing_offer', params: {'p_offer_id': offerId});
  }

  /// إعادة طرح طلب تسويق (listing_requests).
  Future<void> relistListingRequestForMarketing({
    required String requestId,
    bool allowPreviousMarketersRetry = false,
  }) async {
    await sb.rpc(
      'relist_property_for_marketing',
      params: {
        'p_request_id': requestId,
        'p_allow_previous_marketers_retry': allowPreviousMarketersRetry,
      },
    );
  }

  Future<void> marketerSubmitPermits({
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    await sb.rpc('submit_permits', params: {
      'p_request_id': requestId,
      'p_payload': payload,
    });
  }

  // ----------------------------
  // Permits Flow (new stage RPCs)
  // ----------------------------
  Future<String> createOrUpdateListingPermit({
    required String requestId,
    required String permitNo,
    required String authorityName,
    required String licenseNo,
    required String notes,
    required Map<String, dynamic> payload,
    DateTime? expiresAt,
  }) async {
    final res = await sb.rpc(
      'create_or_update_listing_permit',
      params: {
        'p_request_id': requestId,
        'p_permit_no': permitNo,
        'p_authority_name': authorityName,
        'p_license_no': licenseNo,
        'p_notes': notes,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_payload': payload,
      },
    );

    if (res == null) {
      throw Exception('create_or_update_listing_permit: empty response');
    }
    if (res is String) return res;
    if (res is Map && res['id'] != null) return res['id'].toString();
    return res.toString();
  }

  Future<String> issueListingPermit({
    required String requestId,
    String? permitId,
  }) async {
    final params = <String, dynamic>{
      'p_request_id': requestId,
    };
    if (permitId != null && permitId.trim().isNotEmpty) {
      params['p_permit_id'] = permitId;
    }

    final res = await sb.rpc(
      'issue_listing_permit',
      params: params,
    );

    if (res == null) throw Exception('issue_listing_permit: empty response');
    if (res is String) return res;
    return res.toString();
  }

  Future<String> publishPropertyAfterPermit(String requestId) async {
    final res = await sb.rpc(
      'publish_property_after_permit',
      params: {'p_request_id': requestId},
    );
    if (res == null) {
      throw Exception('publish_property_after_permit: empty response');
    }
    if (res is String) return res;
    if (res is Map && res['id'] != null) return res['id'].toString();
    return res.toString();
  }

  // ----------------------------
  // Owner: Approve & Publish
  // ----------------------------
  Future<String> ownerApproveAndPublish(String requestId) async {
    final res = await sb.rpc('approve_permits_and_publish', params: {
      'p_request_id': requestId,
    });

    if (res is String) return res;
    if (res is Map && res['id'] != null) return res['id'].toString();
    return res.toString();
  }

  /// توحيد استدعاءات النشر من الواجهة: تصريح → عقد موقّع → موافقة عامة.
  Future<String> publishListingDispatch({
    required String requestId,
    required bool preferPermitPath,
    String? contractId,
  }) async {
    final String outId;
    if (preferPermitPath) {
      outId = await publishPropertyAfterPermit(requestId);
    } else {
      final cid = (contractId ?? '').trim();
      if (cid.isNotEmpty) {
        outId = await publishPropertyFromContract(cid);
      } else {
        outId = await ownerApproveAndPublish(requestId);
      }
    }
    try {
      await _notifyListingPublishedParties(
          requestId: requestId, propertyId: outId);
    } catch (_) {}
    return outId;
  }

  /// تسجيل أول زيارة للمالك لشاشة عروض المسوقين (يتطلب migration الدالة في Supabase).
  Future<void> recordOwnerViewedListingOffers(String requestId) async {
    try {
      await sb.rpc('record_owner_viewed_listing_offers', params: {
        'p_request_id': requestId,
      });
    } catch (_) {}
  }

  /// طلب مراجعة إدارية / إيقاف التسويق من المالك.
  Future<void> ownerRequestMarketingAdminEscalation({
    required String requestId,
    String? reason,
  }) async {
    await sb.rpc('owner_request_marketing_admin_escalation', params: {
      'p_request_id': requestId,
      'p_reason': reason,
    });
  }

  /// بعد حجز فعّال: المشتري أو المالك أو المسوّق المنشّر يضع الإعلان كـ «مباع» (يتطلب RPC في Supabase).
  Future<void> completePropertySale(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) throw ArgumentError('propertyId');
    await sb.rpc('complete_property_sale', params: {'p_property_id': id});
  }

  /// يعيد نشر عقار من صفقة مكتملة كرحلة تسويق جديدة باسم المشتري الحالي.
  Future<String?> relistCompletedPropertyAsNew(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) throw ArgumentError('propertyId');
    final res = await sb.rpc(
      'relist_completed_property_as_new',
      params: {'p_property_id': id},
    );
    final out = (res ?? '').toString().trim();
    return out.isEmpty ? null : out;
  }

  /// يعيد نشر طلب عقاري مكتمل كطلب جديد باسم المستخدم الحالي.
  Future<String?> relistCompletedMarketRequestAsNew(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) throw ArgumentError('requestId');
    final res = await sb.rpc(
      'relist_completed_market_request_as_new',
      params: {'p_market_request_id': id},
    );
    final out = (res ?? '').toString().trim();
    return out.isEmpty ? null : out;
  }

  // ----------------------------
  // In-app notifications
  // ----------------------------
  Future<List<Map<String, dynamic>>> myInAppNotifications() async {
    final uid = _uidOrThrow();
    try {
      final rows = await sb
          .from('in_app_notifications')
          .select('id,username,type,title,body,data,created_at,is_read')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return _asListOfMaps(rows);
    } catch (_) {
      final rows = await sb
          .from('in_app_notifications')
          .select('id,username,type,title,body,data,created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return _asListOfMaps(rows);
    }
  }

  /// إشعارات صندوق الوارد داخل التطبيق — بدون رموز OTP/تحقق حتى لا تختلط بالعمليات.
  Future<List<Map<String, dynamic>>> myInAppNotificationsInbox() async {
    final all = await myInAppNotifications();
    return all.where((r) => !isSecurityNoiseNotificationRow(r)).toList();
  }

  static bool isSecurityNoiseNotificationRow(Map<String, dynamic> row) {
    final type = (row['type'] ?? '').toString().toLowerCase();
    if (type.contains('otp') ||
        type.contains('pin') ||
        type.contains('verify') ||
        type.contains('verification') ||
        type.contains('recovery') ||
        type.contains('password_reset') ||
        type.contains('mfa') ||
        type.contains('2fa')) {
      return true;
    }
    dynamic data = row['data'];
    if (data is String && data.trim().isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final dr = (m['deep_route'] ?? '').toString().toLowerCase();
      if (dr.contains('otp') || dr.contains('verify')) return true;
      final cat = (m['category'] ?? '').toString().toLowerCase();
      if (cat == 'security' || cat == 'auth') return true;
    }
    final title = (row['title'] ?? '').toString().toLowerCase();
    final body = (row['body'] ?? '').toString().toLowerCase();
    if (title.contains('رمز') && title.contains('تحقق')) return true;
    if (body.contains('otp') || body.contains('verification code')) return true;
    return false;
  }

  Future<void> deleteInAppNotification(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    await sb.from('in_app_notifications').delete().eq('id', sid);
  }

  Future<void> markNotificationRead(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return;
    final uid = _uidOrThrow();
    try {
      await sb
          .from('in_app_notifications')
          .update({'is_read': true})
          .eq('id', sid)
          .eq('user_id', uid);
    } catch (_) {}
  }

  static bool _notificationDataRefsProperty(
      Map<String, dynamic> data, String pid) {
    for (final k in ['property_id', 'preview_property_id']) {
      if ((data[k] ?? '').toString().trim() == pid) return true;
    }
    final eid = (data['entity_id'] ?? '').toString().trim();
    if (eid == pid) return true;
    final et = (data['entity_type'] ?? '').toString().toLowerCase().trim();
    if (et == 'property' && eid == pid) return true;
    return false;
  }

  /// يعلّم إشعارات المستخدم غير المقروءة المرتبطة بعقار كمقروءة (عند فتح بطاقة الإعلان).
  Future<void> markUnreadNotificationsForProperty(String propertyId) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return;
    final uid = _uidOrThrow();
    try {
      final rows = await sb
          .from('in_app_notifications')
          .select('id,data')
          .eq('user_id', uid)
          .eq('is_read', false)
          .limit(100);
      final list = _asListOfMaps(rows);
      for (final r in list) {
        final sid = (r['id'] ?? '').toString().trim();
        if (sid.isEmpty) continue;
        final raw = r['data'];
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (_notificationDataRefsProperty(m, pid)) {
          await markNotificationRead(sid);
        }
      }
    } catch (_) {}
  }

  Future<void> markAllInAppNotificationsRead() async {
    final uid = _uidOrThrow();
    try {
      await sb
          .from('in_app_notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (_) {}
  }

  /// عدد غير المقروء (بدون إشعارات أمن/OTP).
  Future<int> unreadInAppNotificationCount() async {
    try {
      final uid = _uidOrThrow();
      final rows = await sb
          .from('in_app_notifications')
          .select('id,type,title,body,data,is_read')
          .eq('user_id', uid)
          .eq('is_read', false)
          .limit(300);
      final list = _asListOfMaps(rows);
      var n = 0;
      for (final r in list) {
        if (!isSecurityNoiseNotificationRow(r)) n++;
      }
      return n;
    } catch (_) {
      final inbox = await myInAppNotificationsInbox();
      return inbox.length;
    }
  }

  /// إشعار المعلن داخل التطبيق عند تقديم مسوق عرضًا (مسار تفاصيل الدعوة / RPC).
  Future<void> notifyOwnerNewMarketingOffer({
    required String requestId,
    String? previewPropertyId,
  }) async {
    final row = await sb
        .from('listing_requests')
        .select('owner_id,title,status')
        .eq('id', requestId)
        .maybeSingle();
    if (row == null) return;

    final ownerId = (row['owner_id'] ?? '').toString().trim();
    if (ownerId.isEmpty) return;

    final data = <String, dynamic>{
      'role': 'owner',
      'status': 'offers_received',
      'main_tab': 'my_ads',
      WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.ownerOffers,
      'title_ar': 'وصلك عرض تسويق جديد',
      'title_en': 'New marketing offer',
      'body_ar':
          'قدّم مسوق عقاري عرضًا على طلبك. افتح «عروض المسوقين» للموافقة أو الرفض.',
      'body_en':
          'A marketer submitted an offer. Open marketer offers to approve or decline.',
      'request_id': requestId,
      if (previewPropertyId != null && previewPropertyId.trim().isNotEmpty)
        'preview_property_id': previewPropertyId.trim(),
    };

    await InAppNotificationWriter.insert(
      sb,
      userId: ownerId,
      type: InAppNotifTypes.offerSubmitted,
      data: data,
      entityType: InAppEntityTypes.listingOffer,
      entityId: requestId,
    );
  }

  /// رفض عرض أو اعتذار — `owner_decline_listing_offer` (مع `p_decline_kind`: reject | apology).
  /// الاعتذار لا يُحسب ضمن حدّ 3 رفض لمسوّقين مميزين (بعد ترحيل SQL 20260418120000).
  Future<void> ownerDeclineOffer({
    required String offerId,
    required String requestId,
    String? ownerReason,

    /// `reject` = رفض يُحسب في الحدّ؛ `apology` = اعتذار للمسوّق دون إيقاف الطلب بهذا العدّاد.
    String declineKind = 'reject',
  }) async {
    final reason = (ownerReason ?? '').trim();
    final kind = declineKind.trim().toLowerCase();
    final k = kind == 'apology' ? 'apology' : 'reject';
    try {
      await sb.rpc(
        'owner_decline_listing_offer',
        params: {
          'p_offer_id': offerId,
          'p_reason': reason.isEmpty ? null : reason,
          'p_decline_kind': k,
        },
      );
      return;
    } catch (_) {
      // قاعدة قديمة بدون باراميتر النوع / RPC: تحديث مباشر + إشعار (قد تفشل حسب RLS).
    }
    await sb
        .from('listing_offers')
        .update({
          'status': 'declined',
          if (reason.isNotEmpty) 'owner_decline_reason': reason,
          if (k == 'apology') 'decline_kind': 'apology',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', offerId)
        .eq('request_id', requestId);
    try {
      final offer = await sb
          .from('listing_offers')
          .select('marketer_id')
          .eq('id', offerId)
          .maybeSingle();
      final mid = (offer?['marketer_id'] ?? '').toString().trim();
      if (mid.isNotEmpty) {
        await notifyMarketerOfferDeclined(
          marketerId: mid,
          requestId: requestId,
          ownerReason: reason.isEmpty ? null : reason,
          isApology: k == 'apology',
        );
      }
    } catch (_) {}
  }

  /// نص العقد للمعاينة قبل الموافقة (بدون استدعاء `owner_select_offer`).
  Future<String> ownerMarketingContractDraftText({
    required String requestId,
    required String offerId,
    required bool isAr,
  }) async {
    final uid = _uidOrThrow();

    final req = await sb
        .from('listing_requests')
        .select('owner_id,title,city')
        .eq('id', requestId)
        .maybeSingle();
    if (req == null) throw Exception('Request not found');
    if ((req['owner_id'] ?? '').toString().trim() != uid) {
      throw Exception('Not allowed');
    }

    final offer = await sb
        .from('listing_offers')
        .select('price,notes,status,marketer_id')
        .eq('id', offerId)
        .eq('request_id', requestId)
        .maybeSingle();
    if (offer == null) throw Exception('Offer not found');

    final st = (offer['status'] ?? '').toString().toLowerCase().trim();
    const open = {'submitted', 'pending', ''};
    if (!open.contains(st)) {
      throw Exception('Offer is not pending');
    }

    final fee = (offer['price'] is num)
        ? (offer['price'] as num).toDouble()
        : double.tryParse('${offer['price']}') ?? 0.0;
    final notes = (offer['notes'] ?? '').toString();
    final title = (req['title'] ?? '').toString();
    final city = (req['city'] ?? '').toString();
    final now = DateTime.now().toUtc();
    final dateStr = now.toIso8601String().split('T').first;
    final parties = await _contractPartiesContext(
      ownerId: (req['owner_id'] ?? '').toString(),
      marketerId: (offer['marketer_id'] ?? '').toString(),
      isAr: isAr,
    );

    return MarketingContractTemplate.build(
      isAr: isAr,
      requestId: requestId,
      listingTitle: title,
      city: city,
      marketingFee: fee,
      currency: 'SAR',
      ownerName: parties.ownerName,
      marketerName: parties.marketerName,
      marketerEntityType: parties.marketerEntityType,
      marketerLicenseNo: parties.marketerLicenseNo,
      offerNotes: notes.isEmpty ? null : notes,
      signatureDateIso: dateStr,
    );
  }

  /// حفظ بيانات ترخيص الإعلان/QR على سجل العقار المرتبط بالطلب (للعرض في تفاصيل الإعلان).
  Future<void> syncPropertyMarketingLicenseSnapshot({
    required String requestId,
    required Map<String, dynamic> permitPayload,
  }) async {
    final pid = await _resolvePropertyIdForListingRequest(requestId);
    if (pid.isEmpty) return;

    final snapshot = Map<String, dynamic>.from(permitPayload);
    snapshot['captured_at'] = DateTime.now().toUtc().toIso8601String();
    snapshot['listing_request_id'] = requestId;

    try {
      Map<String, dynamic> merged = <String, dynamic>{};
      final cur = await sb
          .from('properties')
          .select('rega_payload')
          .eq('id', pid)
          .maybeSingle();
      final prev = cur?['rega_payload'];
      if (prev is Map) {
        merged.addAll(Map<String, dynamic>.from(prev));
      }
      merged.addAll(snapshot);
      await sb
          .from('properties')
          .update({'rega_payload': merged}).eq('id', pid);
    } catch (_) {}
  }

  /// تحديث إظهار اسم المالك على الإعلان (صلاحية المسوق).
  Future<void> updatePropertyShowAdvertiserNameForRequest({
    required String requestId,
    required bool showAdvertiserName,
  }) async {
    final pid = await _resolvePropertyIdForListingRequest(requestId);
    if (pid.isEmpty) return;
    try {
      await sb.from('properties').update({
        'show_advertiser_name': showAdvertiserName,
      }).eq('id', pid);
    } catch (_) {}
  }

  /// جلب إعداد إظهار اسم المالك لعقار مرتبط بالطلب (لشاشة التصاريح).
  Future<bool> propertyShowAdvertiserNameForRequest(
    String requestId,
  ) async {
    final pid = await _resolvePropertyIdForListingRequest(requestId);
    if (pid.isEmpty) return true;
    try {
      final row = await sb
          .from('properties')
          .select('show_advertiser_name, show_owner_name')
          .eq('id', pid)
          .maybeSingle();
      if (row == null) return true;
      final v = row['show_advertiser_name'] ?? row['show_owner_name'];
      if (v == null) return true;
      if (v is bool) return v;
      final s = v.toString().trim().toLowerCase();
      if (s == 'false' || s == '0') return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<String> _resolvePropertyIdForListingRequest(
    String requestId,
  ) async {
    final p = await sb
        .from('properties')
        .select('id')
        .eq('request_id', requestId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return (p?['id'] ?? '').toString().trim();
  }

  /// بعد [ownerSelectOffer]: إنشاء/تحديث العقد، توقيع المعلن بتاريخ اليوم، وإشعار المسوق.
  Future<Map<String, dynamic>> ownerAcceptOfferSealContract({
    required String requestId,
    required String offerId,
    required bool isAr,
  }) async {
    final uid = _uidOrThrow();

    await ownerSelectOffer(
      requestId: requestId,
      offerId: offerId,
    );

    final offer = await sb
        .from('listing_offers')
        .select('marketer_id,price,notes')
        .eq('id', offerId)
        .maybeSingle();
    if (offer == null) {
      throw Exception('Offer not found');
    }
    final marketerId = (offer['marketer_id'] ?? '').toString().trim();
    if (marketerId.isEmpty) {
      throw Exception('Invalid marketer on offer');
    }

    final req = await sb
        .from('listing_requests')
        .select('owner_id,title,city,contract_id')
        .eq('id', requestId)
        .maybeSingle();
    if (req == null) throw Exception('Request not found');
    if ((req['owner_id'] ?? '').toString().trim() != uid) {
      throw Exception('Not allowed');
    }

    try {
      await sb
          .from('listing_offers')
          .update({
            'status': 'owner_rejected',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('request_id', requestId)
          .neq('id', offerId)
          .inFilter('status', ['submitted', 'pending']);
    } catch (_) {}

    try {
      await sb.from('listing_offers').update({
        'status': 'owner_accepted',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', offerId);
    } catch (_) {}

    final fee = (offer['price'] is num)
        ? (offer['price'] as num).toDouble()
        : double.tryParse('${offer['price']}') ?? 0.0;
    final notes = (offer['notes'] ?? '').toString();
    final title = (req['title'] ?? '').toString();
    final city = (req['city'] ?? '').toString();
    final now = DateTime.now().toUtc();
    final dateStr = now.toIso8601String().split('T').first;
    final parties = await _contractPartiesContext(
      ownerId: (req['owner_id'] ?? '').toString(),
      marketerId: marketerId,
      isAr: isAr,
    );

    var contractId = (req['contract_id'] ?? '').toString().trim();
    var body = MarketingContractTemplate.build(
      isAr: isAr,
      contractId: contractId.isEmpty ? null : contractId,
      requestId: requestId,
      listingTitle: title,
      city: city,
      marketingFee: fee,
      currency: 'SAR',
      ownerName: parties.ownerName,
      marketerName: parties.marketerName,
      marketerEntityType: parties.marketerEntityType,
      marketerLicenseNo: parties.marketerLicenseNo,
      offerNotes: notes.isEmpty ? null : notes,
      signatureDateIso: dateStr,
    );

    if (contractId.isNotEmpty) {
      await sb.from('listing_contracts').update({
        'contract_text': body,
        'marketer_id': marketerId,
        'status': 'draft',
        'updated_at': now.toIso8601String(),
      }).eq('id', contractId);
    } else {
      final ins = await sb
          .from('listing_contracts')
          .insert({
            'request_id': requestId,
            'owner_id': uid,
            'marketer_id': marketerId,
            'status': 'draft',
            'contract_text': body,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .select('id')
          .maybeSingle();
      contractId = (ins?['id'] ?? '').toString().trim();
      if (contractId.isEmpty) {
        throw Exception('Could not create marketing contract');
      }
      body = MarketingContractTemplate.build(
        isAr: isAr,
        contractId: contractId,
        requestId: requestId,
        listingTitle: title,
        city: city,
        marketingFee: fee,
        currency: 'SAR',
        ownerName: parties.ownerName,
        marketerName: parties.marketerName,
        marketerEntityType: parties.marketerEntityType,
        marketerLicenseNo: parties.marketerLicenseNo,
        offerNotes: notes.isEmpty ? null : notes,
        signatureDateIso: dateStr,
      );
      await sb.from('listing_contracts').update({
        'contract_text': body,
        'updated_at': now.toIso8601String(),
      }).eq('id', contractId);
      await sb.from('listing_requests').update({
        'contract_id': contractId,
        'selected_marketer_id': marketerId,
        'workflow_stage': 'marketer_selected',
        'updated_at': now.toIso8601String(),
      }).eq('id', requestId);
    }

    await notifyMarketerContractPendingSignature(
      marketerId: marketerId,
      requestId: requestId,
      contractId: contractId,
    );

    return <String, dynamic>{
      'contract_id': contractId,
    };
  }

  Future<void> notifyMarketerContractPendingSignature({
    required String marketerId,
    required String requestId,
    required String contractId,
  }) async {
    final mid = marketerId.trim();
    if (mid.isEmpty) return;

    final data = <String, dynamic>{
      'role': 'marketer',
      // لا تستخدم القيمة "contract" هنا حتى لا تُخلط مع enum قاعدة البيانات عند أي مسار خادم.
      'status': ListingStatus.pendingMarketer,
      'main_tab': 'my_ads',
      WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.listingRequestStatus,
      'title_ar': 'عقد تسويق بانتظار توقيعك',
      'title_en': 'Marketing contract awaiting your signature',
      'body_ar':
          'وافق المعلن على العرض ووُقِع الطرف الأول إلكترونياً. أكمل التوقيع من تبويب العقود.',
      'body_en':
          'The owner approved the offer and signed. Please complete your signature in the contracts tab.',
      'request_id': requestId,
      'contract_id': contractId,
    };

    await InAppNotificationWriter.insert(
      sb,
      userId: mid,
      type: InAppNotifTypes.contractPendingSignature,
      data: data,
      entityType: InAppEntityTypes.listingContract,
      entityId: contractId,
    );
  }

  /// رسائل الدردشة المرتبطة بعقد تسويق (المالك + المسوق فقط عبر RLS).
  Future<List<Map<String, dynamic>>> listingContractMessages(
    String contractId,
  ) async {
    final cid = contractId.trim();
    if (cid.isEmpty) return const [];
    try {
      final rows = await sb
          .from('listing_contract_messages')
          .select(
            'id,contract_id,sender_id,body,message_type,created_at',
          )
          .eq('contract_id', cid)
          .order('created_at', ascending: true);
      return _asListOfMaps(rows);
    } catch (_) {
      return const [];
    }
  }

  Future<void> sendListingContractMessage({
    required String contractId,
    required String body,
    String messageType = 'chat',
  }) async {
    final uid = _uidOrThrow();
    final cid = contractId.trim();
    final t = body.trim();
    if (cid.isEmpty || t.isEmpty) return;
    await sb.from('listing_contract_messages').insert({
      'contract_id': cid,
      'sender_id': uid,
      'body': t,
      'message_type': messageType,
    });
    try {
      final c = await sb
          .from('listing_contracts')
          .select('owner_id,marketer_id,request_id')
          .eq('id', cid)
          .maybeSingle();
      if (c == null) return;
      final oid = (c['owner_id'] ?? '').toString().trim();
      final mid = (c['marketer_id'] ?? '').toString().trim();
      final rid = (c['request_id'] ?? '').toString().trim();
      final target = uid == oid ? mid : oid;
      if (target.isEmpty || rid.isEmpty) return;
      final typeLabel = messageType == 'chat' ? 'chat' : messageType;
      await InAppNotificationWriter.insert(
        sb,
        userId: target,
        type: InAppNotifTypes.chatMessage,
        data: {
          'role': target == mid ? 'marketer' : 'owner',
          WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
          WorkflowNotificationKeys.deepRoute:
              InAppDeepRoutes.listingRequestStatus,
          'title_ar': 'رسالة جديدة على عقد التسويق',
          'title_en': 'New contract message',
          'body_ar': 'لديك رسالة ($typeLabel) على عقد مرتبط بطلبك.',
          'body_en':
              'You have a new message ($typeLabel) on a listing contract.',
          'request_id': rid,
          'contract_id': cid,
        },
        entityType: InAppEntityTypes.listingContract,
        entityId: cid,
      );
    } catch (_) {}
  }

  Future<void> notifyMarketerOfferAccepted({
    required String marketerId,
    required String requestId,
  }) async {
    final mid = marketerId.trim();
    final rid = requestId.trim();
    if (mid.isEmpty || rid.isEmpty) return;
    await InAppNotificationWriter.insert(
      sb,
      userId: mid,
      type: InAppNotifTypes.offerAccepted,
      data: {
        'role': 'marketer',
        WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
        WorkflowNotificationKeys.deepRoute:
            InAppDeepRoutes.listingRequestStatus,
        'title_ar': 'قبِل المعلن عرضك',
        'title_en': 'Your offer was accepted',
        'body_ar': 'تابع من تفاصيل طلب التسويق لإكمال العقد والخطوات التالية.',
        'body_en':
            'Open the marketing request to continue with the contract and next steps.',
        'request_id': rid,
      },
      entityType: InAppEntityTypes.listingRequest,
      entityId: rid,
    );
  }

  Future<void> notifyMarketerOfferDeclined({
    required String marketerId,
    required String requestId,
    String? ownerReason,
    bool isApology = false,
  }) async {
    final mid = marketerId.trim();
    final rid = requestId.trim();
    if (mid.isEmpty || rid.isEmpty) return;
    final r = (ownerReason ?? '').trim();
    await InAppNotificationWriter.insert(
      sb,
      userId: mid,
      type: InAppNotifTypes.offerDeclined,
      data: {
        'role': 'marketer',
        WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
        WorkflowNotificationKeys.deepRoute:
            InAppDeepRoutes.listingRequestStatus,
        'decline_kind': isApology ? 'apology' : 'reject',
        'title_ar': isApology ? 'اعتذار من المعلن' : 'تم رفض عرضك',
        'title_en':
            isApology ? 'Apology from the owner' : 'Your offer was declined',
        'body_ar': isApology
            ? (r.isEmpty
                ? 'سجّل المعلن اعتذاراً دون احتسابه ضمن حد الرفض. يمكنك متابعة طلبات أخرى.'
                : 'اعتذار من المالك عن عدم المتابعة. ملاحظة: $r')
            : (r.isEmpty
                ? 'يمكنك متابعة طلبات أخرى أو انتظار جولة عروض جديدة.'
                : 'رفض المالك عرضك. السبب: $r'),
        'body_en': isApology
            ? (r.isEmpty
                ? 'The owner sent an apology (not counted as a decline). You can pursue other requests.'
                : 'The owner apologized for not proceeding. Note: $r')
            : (r.isEmpty
                ? 'You can focus on other requests or wait for a new offer round.'
                : 'The owner declined your offer. Reason: $r'),
        'request_id': rid,
        if (r.isNotEmpty) 'owner_decline_reason': r,
      },
      entityType: InAppEntityTypes.listingRequest,
      entityId: rid,
    );
  }

  Future<void> notifyOwnerListingRequestSubmitted({
    required String ownerId,
    required String requestId,
    String? titleHint,
  }) async {
    final oid = ownerId.trim();
    final rid = requestId.trim();
    if (oid.isEmpty || rid.isEmpty) return;
    final hint = (titleHint ?? '').trim();
    await InAppNotificationWriter.insert(
      sb,
      userId: oid,
      type: InAppNotifTypes.listingRequestSubmitted,
      data: {
        'role': 'owner',
        WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
        WorkflowNotificationKeys.deepRoute:
            InAppDeepRoutes.listingRequestStatus,
        'title_ar': 'تم استلام طلب التسويق',
        'title_en': 'Marketing request received',
        'body_ar': hint.isNotEmpty
            ? 'طلبك «$hint» قيد المراجعة. تابع الحالة من «إعلاناتي».'
            : 'طلب تسويق جديد قيد المراجعة. تابع الحالة من «إعلاناتي».',
        'body_en': hint.isNotEmpty
            ? 'Your request "$hint" is being processed. Track it under My ads.'
            : 'Your marketing request is being processed. Track it under My ads.',
        'request_id': rid,
      },
      entityType: InAppEntityTypes.listingRequest,
      entityId: rid,
    );
  }

  Future<void> notifyOwnerPropertyListed({
    required String ownerId,
    required String propertyId,
    String? titleHint,
  }) async {
    final oid = ownerId.trim();
    final pid = propertyId.trim();
    if (oid.isEmpty || pid.isEmpty) return;
    final hint = (titleHint ?? '').trim();
    await InAppNotificationWriter.insert(
      sb,
      userId: oid,
      type: InAppNotifTypes.propertyCreated,
      data: {
        'role': 'owner',
        WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
        WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.userDashboard,
        'title_ar': 'تم إنشاء إعلانك',
        'title_en': 'Your listing was created',
        'body_ar': hint.isNotEmpty
            ? 'الإعلان «$hint» أصبح في مسار التسويق أو النشر حسب نوع حسابك.'
            : 'أصبح إعلانك في مسار التسويق أو النشر حسب نوع حسابك.',
        'body_en': hint.isNotEmpty
            ? 'Listing "$hint" is now in marketing or publishing flow.'
            : 'Your listing is now in marketing or publishing flow.',
        'preview_property_id': pid,
        'property_id': pid,
      },
      entityType: InAppEntityTypes.property,
      entityId: pid,
    );
  }

  Future<void> notifyOwnerPermitPackageSubmitted({
    required String ownerId,
    required String requestId,
  }) async {
    final oid = ownerId.trim();
    final rid = requestId.trim();
    if (oid.isEmpty || rid.isEmpty) return;
    await InAppNotificationWriter.insert(
      sb,
      userId: oid,
      type: InAppNotifTypes.permitPackageSubmitted,
      data: {
        'role': 'owner',
        WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
        WorkflowNotificationKeys.deepRoute:
            InAppDeepRoutes.listingRequestStatus,
        'title_ar': 'رفع المسوّق بيانات التصاريح',
        'title_en': 'Marketer submitted permit details',
        'body_ar':
            'راجع الترخيص والبيانات ثم أكمل الموافقة أو النشر عند الجاهزية.',
        'body_en':
            'Review the permit details and proceed with approval or publishing.',
        'request_id': rid,
      },
      entityType: InAppEntityTypes.listingPermit,
      entityId: rid,
    );
  }

  Future<void> _notifyListingPublishedParties({
    required String requestId,
    required String propertyId,
  }) async {
    final rid = requestId.trim();
    final pid = propertyId.trim();
    if (rid.isEmpty) return;

    final req = await sb
        .from('listing_requests')
        .select('owner_id,title,selected_marketer_id')
        .eq('id', rid)
        .maybeSingle();
    if (req == null) return;

    final ownerId = (req['owner_id'] ?? '').toString().trim();
    final mk = (req['selected_marketer_id'] ?? '').toString().trim();
    final t = (req['title'] ?? '').toString().trim();

    final dataOwner = <String, dynamic>{
      'role': 'owner',
      WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
      WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.userDashboard,
      'title_ar': 'تم نشر إعلانك',
      'title_en': 'Your listing is live',
      'body_ar': t.isNotEmpty
          ? 'الإعلان «$t» أصبح منشورًا للجميع.'
          : 'أصبح إعلانك منشورًا للجميع.',
      'body_en': t.isNotEmpty
          ? 'Listing "$t" is now published.'
          : 'Your listing is now published.',
      'request_id': rid,
      if (pid.isNotEmpty) 'preview_property_id': pid,
      if (pid.isNotEmpty) 'property_id': pid,
    };

    if (ownerId.isNotEmpty) {
      await InAppNotificationWriter.insert(
        sb,
        userId: ownerId,
        type: InAppNotifTypes.listingPublished,
        data: dataOwner,
        entityType: InAppEntityTypes.property,
        entityId: pid.isNotEmpty ? pid : rid,
      );
    }

    if (mk.isNotEmpty && mk != ownerId) {
      await InAppNotificationWriter.insert(
        sb,
        userId: mk,
        type: InAppNotifTypes.listingPublished,
        data: {
          'role': 'marketer',
          WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
          WorkflowNotificationKeys.deepRoute:
              InAppDeepRoutes.listingRequestStatus,
          'title_ar': 'نُشر الإعلان',
          'title_en': 'Listing published',
          'body_ar': t.isNotEmpty
              ? 'الإعلان «$t» أصبح منشورًا.'
              : 'أصبح الإعلان المرتبط بطلبك منشورًا.',
          'body_en': t.isNotEmpty
              ? 'Listing "$t" is now live.'
              : 'The listing for your request is now live.',
          'request_id': rid,
          if (pid.isNotEmpty) 'preview_property_id': pid,
        },
        entityType: InAppEntityTypes.listingRequest,
        entityId: rid,
      );
    }
  }
}
