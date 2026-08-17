import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// مدفوعات وعربون/ضمان للإعلانات — سجل في `listing_payment_events` + Checkout عبر Edge (Stripe).
///
/// **السياق السعودي:** Moyasar/مدى شائع للبطاقات المحلية؛ Stripe للدولية.
/// المفاتيح السرية تبقى في Supabase Edge secrets فقط — لا تضعها في تطبيق العميل.
abstract final class ListingPaymentService {
  static final SupabaseClient _sb = Supabase.instance.client;

  static const String checkoutFunctionName = 'create_listing_checkout';

  static Future<List<Map<String, dynamic>>> fetchEventsForProperty(
    String propertyId, {
    int limit = 15,
  }) async {
    final pid = propertyId.trim();
    if (pid.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('listing_payment_events')
          .select(
            'id,initiator_id,kind,provider,amount_sar,status,recorded_as_role,escrow_notes,external_payment_id,created_at,auction_session_id',
          )
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

  /// يعيد معرف الحدث عند النجاح.
  static Future<String?> registerEvent({
    required String propertyId,
    required String kind,
    required String provider,
    required double amountSar,
    String? auctionSessionId,
    String? escrowNotes,
    Map<String, dynamic>? metadata,
  }) async {
    final pid = propertyId.trim();
    if (pid.isEmpty || amountSar <= 0) return null;
    try {
      final res = await _sb.rpc<dynamic>(
        'register_listing_payment_event',
        params: {
          'p_property_id': pid,
          'p_kind': kind,
          'p_provider': provider,
          'p_amount_sar': amountSar,
          'p_auction_session_id': auctionSessionId,
          'p_escrow_notes': escrowNotes,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );
      if (res == null) return null;
      return res.toString();
    } on PostgrestException {
      rethrow;
    }
  }

  static String? userFacingRegisterError(PostgrestException e, {required bool isAr}) {
    final m = e.message.toLowerCase();
    if (m.contains('not_authorized_to_record_payment_event')) {
      return isAr
          ? 'لا صلاحية لتسجيل هذا الحدث (المالك/المنشّر/المشرف أو مشتري لعربون حسن النية فقط).'
          : 'Not allowed to record this payment event.';
    }
    if (m.contains('invalid_payment_amount')) {
      return isAr ? 'المبلغ غير صالح' : 'Invalid amount';
    }
    if (m.contains('auction_session_mismatch')) {
      return isAr ? 'جلسة المزاد لا تتبع هذا العقار' : 'Auction session does not match this listing';
    }
    if (m.contains('not_authenticated')) {
      return isAr ? 'سجّل الدخول أولاً' : 'Sign in required';
    }
    return null;
  }

  /// يستدعي Edge Function؛ يفتح رابط Stripe عند `checkout_url`.
  static Future<CheckoutLaunchResult> openStripeCheckoutIfAvailable({
    required String paymentEventId,
  }) async {
    final id = paymentEventId.trim();
    if (id.isEmpty) {
      return CheckoutLaunchResult(
        ok: false,
        messageEn: 'Missing payment id',
        messageAr: 'معرّف الدفع مفقود',
      );
    }
    try {
      final res = await _sb.functions.invoke(
        checkoutFunctionName,
        body: <String, String>{'payment_event_id': id},
      );
      final data = res.data;
      if (data is! Map) {
        return CheckoutLaunchResult(
          ok: false,
          messageEn: 'Unexpected response',
          messageAr: 'استجابة غير متوقعة',
        );
      }
      final map = Map<String, dynamic>.from(
        data.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (map['configured'] == false) {
        final hint = '${map['hint'] ?? map['message'] ?? ''}';
        return CheckoutLaunchResult(
          ok: false,
          messageEn: hint.isNotEmpty
              ? hint
              : 'Payment gateway not configured (set STRIPE_SECRET_KEY).',
          messageAr: hint.isNotEmpty
              ? hint
              : 'بوابة الدفع غير مهيأة (أضف STRIPE_SECRET_KEY في أسرار الدالة).',
        );
      }
      final url = (map['checkout_url'] ?? '').toString().trim();
      if (url.isEmpty) {
        return CheckoutLaunchResult(
          ok: false,
          messageEn: 'No checkout URL returned',
          messageAr: 'لم يُرجَع رابط دفع',
        );
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return CheckoutLaunchResult(
          ok: false,
          messageEn: 'Invalid checkout URL',
          messageAr: 'رابط الدفع غير صالح',
        );
      }
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return CheckoutLaunchResult(
        ok: launched,
        messageEn: launched ? 'Opening checkout…' : 'Could not open browser',
        messageAr: launched ? 'جاري فتح صفحة الدفع…' : 'تعذّر فتح المتصفح',
      );
    } catch (e) {
      return CheckoutLaunchResult(
        ok: false,
        messageEn: e.toString(),
        messageAr: 'تعذّر بدء الدفع',
      );
    }
  }
}

class CheckoutLaunchResult {
  final bool ok;
  final String messageEn;
  final String messageAr;

  const CheckoutLaunchResult({
    required this.ok,
    required this.messageEn,
    required this.messageAr,
  });
}
