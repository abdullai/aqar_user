import 'package:supabase_flutter/supabase_flutter.dart';

class ReservationItem {
  /// ✅ id في التطبيق = id في قاعدة البيانات (جدول reservations)
  final String id;
  final String propertyId;
  final String status;
  final DateTime expiresAt;

  /// ✅ التسعير (محسوب من DB عبر Trigger)
  final double basePrice;
  final double platformFeeAmount; // 5%
  final double extraFeeAmount; // 2.5%
  final double totalAmount;

  /// اسم الحاجز (اختياري – للمعلن)
  final String? reserverName;

  /// ✅ conversation المرتبطة بالحجز/العقار
  final String? conversationId;

  ReservationItem({
    required this.id,
    required this.propertyId,
    required this.status,
    required this.expiresAt,
    required this.basePrice,
    required this.platformFeeAmount,
    required this.extraFeeAmount,
    required this.totalAmount,
    this.reserverName,
    this.conversationId,
  });

  String get expiresAtIso => expiresAt.toIso8601String();
}

class ReservationsService {
  static final SupabaseClient _sb = Supabase.instance.client;

  // =========================
  // Utils
  // =========================

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static bool _isPostgresUniqueViolation(PostgrestException e) =>
      e.code == '23505';

  /// طرف محادثة العقار للمستخدمين: المسوّق المنشّر/المختار فقط (لا رقم المالك).
  static String? marketerCounterpartyIdForPropertyChat(
    Map<String, dynamic> prop,
  ) {
    final pub = _s(prop['published_by_marketer_id']);
    if (pub.isNotEmpty) return pub;
    final sel = _s(prop['selected_marketer_id']);
    if (sel.isNotEmpty) return sel;
    return null;
  }

  // ===========================================================================
  // 1) إنشاء الحجز + (اختياري) إنشاء/ربط محادثة العقار
  // ===========================================================================

  /// ✅ إنشاء حجز 72 ساعة
  ///
  /// - لا يكسر الحجز لو فشلت الدردشة
  /// - DB Trigger يحسب الرسوم
  static Future<bool> createReservation({
    required String userId,
    required String propertyId,
    required double basePrice,
    bool createConversation = true,
    String? conversationTitle,
  }) async {
    try {
      // Use RPC to keep properties.workflow_stage + reservation_expires_at in sync.
      final res = await _sb.rpc(
        'reserve_property',
        params: {
          'p_property_id': propertyId,
          'p_base_price': basePrice,
        },
      );

      final reservationId = res is String
          ? res
          : (res is Map
              ? _s(res.values.isNotEmpty ? res.values.first : null)
              : _s(res));

      if (createConversation && reservationId.isNotEmpty) {
        // best-effort: لا نكسر الحجز لو فشلت الدردشة
        try {
          await getOrCreatePropertyConversation(
            propertyId: propertyId,
            reservationId: reservationId,
            title: conversationTitle,
          );
        } catch (_) {}
      }

      return true;
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('property_already_reserved') ||
          msg.contains('user_already_has_active_reservation') ||
          msg.contains('property_not_published') ||
          msg.contains('cannot_reserve_own_listing') ||
          msg.contains('cannot_reserve_publisher_listing') ||
          msg.contains('not_allowed_reserve') ||
          _isPostgresUniqueViolation(e)) {
        return false;
      }
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// ✅ إلغاء الحجز (للمستخدم)
  static Future<void> cancelReservation(String reservationId) async {
    await _sb.rpc(
      'release_or_expire_reservation',
      params: {
        'p_reservation_id': reservationId,
        'p_set_status': 'cancelled',
      },
    );
  }

  // ===========================================================================
  // 2) محادثات العقار (متوافقة مع ChatPage الجديد)
  // ===========================================================================

  /// ✅ يجلب أو ينشئ conversation(kind='property')
  ///
  /// التوافق مع ChatPage:
  /// - user_id = المستخدم الحالي
  /// - counterparty_id = المسوّق (published_by_marketer_id أو selected_marketer_id) — لا المالك
  /// - نفس المحادثة تعاد دائماً (بدون تكرار)
  static Future<String> getOrCreatePropertyConversation({
    required String propertyId,
    String? reservationId,
    String? title,
  }) async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      throw Exception('Auth required');
    }

    // 1) جلب العقار + عنوان افتراضي + المسوّق المسؤول عن التواصل
    final prop = await _sb
        .from('properties')
        .select(
          'owner_id, title, published_by_marketer_id, selected_marketer_id',
        )
        .eq('id', propertyId)
        .single();

    final propTitle = _s(prop['title']);
    final marketerId =
        marketerCounterpartyIdForPropertyChat(Map<String, dynamic>.from(prop));

    if (marketerId == null || marketerId.isEmpty) {
      throw Exception(
        'No marketer assigned to this listing. Chat is only with the licensed marketer.',
      );
    }
    if (marketerId == uid) {
      throw Exception('Cannot chat with yourself');
    }

    // 2) البحث عن محادثة موجودة (مع المسوّق فقط)
    final existing = await _sb
        .from('conversations')
        .select('id, reservation_id')
        .eq('kind', 'property')
        .eq('property_id', propertyId)
        .or(
          'and(user_id.eq.$uid,counterparty_id.eq.$marketerId),and(user_id.eq.$marketerId,counterparty_id.eq.$uid)',
        )
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      final cid = _s(existing['id']);
      if (cid.isEmpty) {
        throw Exception('Invalid conversation row');
      }

      // ربط reservation_id إن كان فارغاً
      final curRes = _s(existing['reservation_id']);
      final wantedRes = (reservationId ?? '').trim();

      if (curRes.isEmpty && wantedRes.isNotEmpty) {
        await _sb.from('conversations').update({
          'reservation_id': wantedRes,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', cid);
      }

      return cid;
    }

    // 3) إنشاء محادثة جديدة
    final wantedRes = (reservationId ?? '').trim();

    final inserted = await _sb
        .from('conversations')
        .insert({
          'kind': 'property',
          'property_id': propertyId,
          'reservation_id': wantedRes.isEmpty ? null : wantedRes,
          'user_id': uid,
          'counterparty_id': marketerId,
          'title': (title ?? propTitle).trim().isEmpty
              ? 'Property chat'
              : (title ?? propTitle).trim(),
        })
        .select('id')
        .single();

    return _s(inserted['id']);
  }

  /// محادثة المسوّق (أو من له صلة بالطلب) مع **مالك** الإعلان قبل النشر.
  /// `kind=property` و`counterparty_id = owner_id` — منفصلة عن محادثة المسوّق للمشترين.
  static Future<String> getOrCreatePropertyOwnerConversation({
    required String propertyId,
    String? title,
  }) async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      throw Exception('Auth required');
    }

    final prop = await _sb
        .from('properties')
        .select('owner_id, title')
        .eq('id', propertyId)
        .single();

    final ownerId = _s(prop['owner_id']);
    if (ownerId.isEmpty) {
      throw Exception('Owner not found');
    }
    if (ownerId == uid) {
      throw Exception('Owner uses marketer chat channel');
    }

    final propTitle = _s(prop['title']);

    final existing = await _sb
        .from('conversations')
        .select('id, reservation_id')
        .eq('kind', 'property')
        .eq('property_id', propertyId)
        .or(
          'and(user_id.eq.$uid,counterparty_id.eq.$ownerId),and(user_id.eq.$ownerId,counterparty_id.eq.$uid)',
        )
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      final cid = _s(existing['id']);
      if (cid.isEmpty) {
        throw Exception('Invalid conversation row');
      }
      return cid;
    }

    final inserted = await _sb
        .from('conversations')
        .insert({
          'kind': 'property',
          'property_id': propertyId,
          'user_id': uid,
          'counterparty_id': ownerId,
          'title': (title ?? propTitle).trim().isEmpty
              ? 'Listing owner chat'
              : (title ?? propTitle).trim(),
        })
        .select('id')
        .single();

    return _s(inserted['id']);
  }

  // ===========================================================================
  // 3) السلة (حجوزاتي) + conversationId لكل عنصر
  // ===========================================================================

  /// هل لدى المستخدم حجزاً نشطاً (صفقة) على هذا الإعلان؟
  static Future<bool> userHasActiveReservationForProperty({
    required String userId,
    required String propertyId,
  }) async {
    final uid = userId.trim();
    final pid = propertyId.trim();
    if (uid.isEmpty || pid.isEmpty) return false;
    try {
      final res = await _sb
          .from('reservations')
          .select('id')
          .eq('user_id', uid)
          .eq('property_id', pid)
          .inFilter('status', ['pending', 'paid'])
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// ✅ سلة المستخدم
  static Future<List<ReservationItem>> loadMyCart(String userId) async {
    final res = await _sb
        .from('reservations')
        .select(
          'id, property_id, status, expires_at, base_price, platform_fee_amount, extra_fee_amount, total_amount',
        )
        .eq('user_id', userId)
        .inFilter('status', ['pending', 'paid']) // ✅ حسب CHECK constraint عندك
        .order('created_at', ascending: false);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];

    final propIds = rows
        .map((r) => _s(r['property_id']))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final convMap = await _fetchConversationIdsForUserProperties(
      userId: userId,
      propertyIds: propIds,
    );

    return rows.map<ReservationItem>((r) {
      final pid = _s(r['property_id']);
      return ReservationItem(
        id: _s(r['id']),
        propertyId: pid,
        status: _s(r['status']),
        expiresAt: DateTime.parse(_s(r['expires_at'])).toLocal(),
        basePrice: _toDouble(r['base_price']),
        platformFeeAmount: _toDouble(r['platform_fee_amount']),
        extraFeeAmount: _toDouble(r['extra_fee_amount']),
        totalAmount: _toDouble(r['total_amount']),
        conversationId: convMap[pid],
      );
    }).toList();
  }

  // ===========================================================================
  // 4) حجوزات على إعلاناتي (للمعلن) + ربط الدردشة
  // ===========================================================================

  static Future<List<ReservationItem>> loadOnMyProperties({
    String lang = 'ar',
  }) async {
    // ملاحظة: لو عندك RLS تمنع المعلن من رؤية كل reservations بدون فلترة،
    // لازم تعتمد على View/RPC. هذا الكود يفترض أنه مسموح.
    final res = await _sb.from('reservations').select('''
      id,
      property_id,
      user_id,
      status,
      expires_at,
      base_price,
      platform_fee_amount,
      extra_fee_amount,
      total_amount,
      users_profiles(
        full_name,
        name,
        username,
        email,
        full_name_ar,
        full_name_en,
        first_name_ar,
        fourth_name_ar,
        first_name_en,
        fourth_name_en
      )
    ''').order('created_at', ascending: false);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];

    String pick(dynamic v) => (v?.toString() ?? '').trim();

    String? buildName(Map<String, dynamic>? u) {
      if (u == null) return null;

      if (lang == 'ar') {
        final fl =
            '${pick(u['first_name_ar'])} ${pick(u['fourth_name_ar'])}'.trim();
        if (fl.isNotEmpty) return fl;
        final ar = pick(u['full_name_ar']);
        if (ar.isNotEmpty) return ar;
      } else {
        final fl =
            '${pick(u['first_name_en'])} ${pick(u['fourth_name_en'])}'.trim();
        if (fl.isNotEmpty) return fl;
        final en = pick(u['full_name_en']);
        if (en.isNotEmpty) return en;
      }

      for (final k in ['full_name', 'name', 'username', 'email']) {
        final v = pick(u[k]);
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    // key = "$propertyId|$userId"
    final keys = <String>{};
    for (final r in rows) {
      final pid = _s(r['property_id']);
      final uid = _s(r['user_id']);
      if (pid.isNotEmpty && uid.isNotEmpty) {
        keys.add('$pid|$uid');
      }
    }

    final convPairsMap = await _fetchConversationIdsForPairs(keys.toList());

    return rows.map<ReservationItem>((r) {
      final u = (r['users_profiles'] as Map?)?.cast<String, dynamic>();
      final name = buildName(u);

      final pid = _s(r['property_id']);
      final reserverId = _s(r['user_id']);
      final convId = convPairsMap['$pid|$reserverId'];

      return ReservationItem(
        id: _s(r['id']),
        propertyId: pid,
        status: _s(r['status']),
        expiresAt: DateTime.parse(_s(r['expires_at'])).toLocal(),
        basePrice: _toDouble(r['base_price']),
        platformFeeAmount: _toDouble(r['platform_fee_amount']),
        extraFeeAmount: _toDouble(r['extra_fee_amount']),
        totalAmount: _toDouble(r['total_amount']),
        reserverName: name,
        conversationId: convId,
      );
    }).toList();
  }

  // ===========================================================================
  // 5) Helpers (ربط الحجوزات بالمحادثات)
  // ===========================================================================

  static Future<Map<String, String>> _fetchConversationIdsForUserProperties({
    required String userId,
    required List<String> propertyIds,
  }) async {
    if (propertyIds.isEmpty) return {};

    final data = await _sb
        .from('conversations')
        .select('id, property_id')
        .eq('kind', 'property')
        .eq('user_id', userId)
        .inFilter('property_id', propertyIds);

    final rows = (data as List).cast<Map>();
    final out = <String, String>{};

    for (final r in rows) {
      final pid = _s(r['property_id']);
      final cid = _s(r['id']);
      if (pid.isNotEmpty && cid.isNotEmpty) {
        out[pid] = cid;
      }
    }
    return out;
  }

  /// keys: "$propertyId|$userId"
  static Future<Map<String, String>> _fetchConversationIdsForPairs(
    List<String> keys,
  ) async {
    if (keys.isEmpty) return {};

    final propIds = <String>{};
    final userIds = <String>{};

    for (final k in keys) {
      final parts = k.split('|');
      if (parts.length != 2) continue;
      if (parts[0].trim().isNotEmpty) propIds.add(parts[0].trim());
      if (parts[1].trim().isNotEmpty) userIds.add(parts[1].trim());
    }

    if (propIds.isEmpty || userIds.isEmpty) return {};

    final data = await _sb
        .from('conversations')
        .select('id, property_id, user_id')
        .eq('kind', 'property')
        .inFilter('property_id', propIds.toList())
        .inFilter('user_id', userIds.toList());

    final rows = (data as List).cast<Map>();
    final out = <String, String>{};

    for (final r in rows) {
      final pid = _s(r['property_id']);
      final uid = _s(r['user_id']);
      final cid = _s(r['id']);
      if (pid.isEmpty || uid.isEmpty || cid.isEmpty) continue;
      out['$pid|$uid'] = cid;
    }

    return out;
  }

  // ===========================================================================
  // 6) محادثات طلب السوق (صاحب الطلب ↔ مهتم)
  // ===========================================================================

  static Future<String> getOrCreateMarketRequestConversation({
    required String marketRequestId,
    String? counterpartyId,
  }) async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      throw Exception('Auth required');
    }

    final rid = marketRequestId.trim();
    if (rid.isEmpty) {
      throw Exception('Invalid request');
    }

    final params = <String, dynamic>{
      'p_request_id': rid,
    };
    final cp = (counterpartyId ?? '').trim();
    if (cp.isNotEmpty) {
      params['p_counterparty'] = cp;
    }

    final res = await _sb.rpc(
      'ensure_market_request_conversation',
      params: params,
    );

    final cid = res is String
        ? res
        : _s(res);
    if (cid.isEmpty) {
      throw Exception('Could not open conversation');
    }
    return cid;
  }
}
