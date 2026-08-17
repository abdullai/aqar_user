import 'package:supabase_flutter/supabase_flutter.dart';

/// مزايدات العقار (جدول `property_auction_bids` + RPC `place_property_bid`).
abstract final class PropertyAuctionService {
  static final SupabaseClient _sb = Supabase.instance.client;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// جلسة مزاد `open` الأحدث لعقار (إن وُجدت). يفشل بصمت إن لم يُنشر الجدول بعد.
  static Future<Map<String, dynamic>?> fetchOpenSession(
    String propertyId,
  ) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return null;
    try {
      final row = await _sb
          .from('property_auction_sessions')
          .select(
            'id,status,ends_at,min_increment_sar,created_at,updated_at',
          )
          .eq('property_id', pid)
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// يعيد معرف الجلسة الجديدة عند النجاح.
  static Future<String?> openAuctionSession({
    required String propertyId,
    DateTime? endsAt,
    double? minIncrementSar,
  }) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return null;
    final res = await _sb.rpc<dynamic>(
      'open_property_auction_session',
      params: {
        'p_property_id': pid,
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
        'p_min_increment_sar': minIncrementSar,
      },
    );
    if (res == null) return null;
    return res.toString();
  }

  static Future<void> closeAuctionSession(String propertyId) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return;
    await _sb.rpc<void>(
      'close_property_auction_session',
      params: {'p_property_id': pid},
    );
  }

  /// آخر المزايدات (الأحدث أولاً). يفشل بصمت إن لم يُنشر الجدول بعد.
  static Future<List<Map<String, dynamic>>> fetchRecentBids(
    String propertyId, {
    int limit = 20,
  }) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('property_auction_bids')
          .select('id,bidder_id,amount,created_at')
          .eq('property_id', pid)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map<Map<String, dynamic>>(
            (e) => Map<String, dynamic>.from(e as Map),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// يعيد `true` عند النجاح. عند رفض السيرفر يعيد `false` أو يرمي استثناء غير متوقع.
  static Future<bool> placeBid({
    required String propertyId,
    required double amount,
  }) async {
    final pid = propertyId.trim();
    if (pid.isEmpty || amount <= 0) return false;
    try {
      await _sb.rpc<void>(
        'place_property_bid',
        params: {
          'p_property_id': pid,
          'p_amount': amount,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('not_authenticated') ||
          m.contains('property_not_found') ||
          m.contains('not_auction_listing') ||
          m.contains('listing_not_open_for_bids') ||
          m.contains('owner_cannot_bid') ||
          m.contains('marketer_cannot_bid_own_listing') ||
          m.contains('bid_too_low') ||
          m.contains('invalid_bid_amount') ||
          m.contains('auction_session_ended')) {
        return false;
      }
      rethrow;
    }
  }

  static String? userFacingErrorMessage(
    PostgrestException e, {
    required bool isAr,
  }) {
    final m = e.message.toLowerCase();
    if (m.contains('not_authenticated')) {
      return isAr ? 'سجّل الدخول للمزايدة' : 'Sign in to place a bid';
    }
    if (m.contains('bid_too_low')) {
      return isAr
          ? 'المبلغ أقل من الحد الأدنى المطلوب للزيادة'
          : 'Amount is below the minimum bid increment';
    }
    if (m.contains('owner_cannot_bid')) {
      return isAr ? 'لا يمكن للمالك المزايدة على إعلانه' : 'Owner cannot bid on own listing';
    }
    if (m.contains('marketer_cannot_bid_own_listing')) {
      return isAr
          ? 'لا يمكن للمسوّق المنشّر المزايدة على هذا الإعلان'
          : 'Publishing marketer cannot bid on this listing';
    }
    if (m.contains('auction_session_ended')) {
      return isAr ? 'انتهت جلسة المزاد لهذا الإعلان' : 'The auction session for this listing has ended';
    }
    if (m.contains('not_authorized_to_manage_auction')) {
      return isAr
          ? 'لا صلاحية لإدارة جلسة المزاد (المالك أو المسوّق المنشّر فقط)'
          : 'No permission to manage the auction session';
    }
    if (m.contains('auction_end_must_be_future')) {
      return isAr
          ? 'وقت انتهاء الجلسة يجب أن يكون في المستقبل'
          : 'Session end time must be in the future';
    }
    if (m.contains('invalid_min_increment')) {
      return isAr
          ? 'الحد الأدنى للزيادة غير صالح'
          : 'Minimum increment is invalid';
    }
    if (m.contains('listing_not_open_for_bids')) {
      return isAr ? 'هذا الإعلان غير مفتوح للمزايدة حالياً' : 'Bidding is not open for this listing';
    }
    if (m.contains('not_auction_listing')) {
      return isAr ? 'هذا الإعلان ليس مزاداً' : 'This listing is not an auction';
    }
    return null;
  }

  static double suggestedMinimumIncrement(double currentOrOpening) {
    final c = currentOrOpening < 0 ? 0.0 : currentOrOpening;
    final onePct = (c * 0.01).floor();
    return onePct > 100 ? onePct.toDouble() : 100.0;
  }

  static double minimumNextBid(double currentOrOpening) {
    final c = currentOrOpening < 0 ? 0.0 : currentOrOpening;
    return c + suggestedMinimumIncrement(c);
  }

  /// تحديث `current_bid` من الخادم بعد مزايدة ناجحة.
  static Future<double?> refreshCurrentBid(String propertyId) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return null;
    try {
      final row = await _sb
          .from('properties')
          .select('current_bid')
          .eq('id', pid)
          .maybeSingle();
      if (row == null) return null;
      final v = row['current_bid'];
      if (v == null) return null;
      return _toDouble(v);
    } catch (_) {
      return null;
    }
  }
}
