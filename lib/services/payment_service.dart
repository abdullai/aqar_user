import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:moyasar/moyasar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../core/notifications/in_app_notification_writer.dart';
import '../core/pdf/pdf_readable_qr.dart';
import '../core/session/account_role_cache.dart';
import '../core/subscription/card_scheme.dart';
import '../core/workflow/listing_workflow.dart';
import 'payment_gateway_mock.dart';

/// مدفوعات + بطاقات محفوظة (توكنات). عند ضبط [MOYASAR_PUBLISHABLE_KEY] يُكمَل الدفع عبر ميسّر
/// مع تمرير [billing_transaction_id] في metadata ليتلقّاه Webhook على Supabase.
class PaymentService {
  PaymentService(this._sb);

  final SupabaseClient _sb;

  static const _cards = 'saved_cards';
  static const _tx = 'billing_transactions';
  static const chargeSavedCardFunction = 'moyasar-charge-saved-card';

  /// جهة اتصال رسمية تُسجَّل في metadata عمليات ميسّر (للتدقيق والامتثال).
  static const String billingAuthorizedContactName =
      'Abdullah Issa Ahmed Abuhia';

  User? get _user => _sb.auth.currentUser;

  /// مفتاح `pk_test_…` أو `pk_live_…` من لوحة ميسّر (قابل للنشر فقط — لا تضع المفتاح السري هنا).
  static String? get moyasarPublishableKey {
    final k = (dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '').trim();
    return k.isEmpty ? null : k;
  }

  static bool get useMoyasarLiveFlow {
    final k = moyasarPublishableKey ?? '';
    return k.startsWith('pk_test_') || k.startsWith('pk_live_');
  }

  /// بوابة وهمية للتجربة المحلية حتى تفعيل ميسّر.
  /// — مع مفتاح ميسّر: تُعطَّل تلقائياً.
  /// — بدون مفتاح: مفعّلة (debug/release) ما لم يُضبط `ALLOW_PAYMENT_MOCK=false`.
  static bool get allowMockGateway {
    if (useMoyasarLiveFlow) return false;
    final v = (dotenv.env['ALLOW_PAYMENT_MOCK'] ?? '').trim().toLowerCase();
    if (v == '0' || v == 'false' || v == 'no') return false;
    return true;
  }

  static Map<String, dynamic> get _mockGatewayBlocked =>
      const {'ok': false, 'error': 'payment_gateway_not_configured'};

  /// وضع الاختبار — بطاقات ميسّر الوهمية (4111…) تعمل مع pk_test_ / sk_test_.
  static bool get isMoyasarTestMode =>
      (moyasarPublishableKey ?? '').startsWith('pk_test_');

  /// معرّف التاجر في Apple (مطلوب لـ Apple Pay مع ميسّر).
  static String? get moyasarApplePayMerchantId {
    final k = (dotenv.env['MOYASAR_APPLE_PAY_MERCHANT_ID'] ?? '').trim();
    return k.isEmpty ? null : k;
  }

  static String? get moyasarSamsungPayServiceId {
    final k = (dotenv.env['MOYASAR_SAMSUNG_PAY_SERVICE_ID'] ?? '').trim();
    return k.isEmpty ? null : k;
  }

  /// رابط callback لـ 3DS (يجب أن يكون https؛ يُعرَّف في لوحة ميسّر/التوثيق عند الحاجة).
  static void configureMoyasarCallbackUrlFromEnv() {
    final u = (dotenv.env['MOYASAR_CALLBACK_URL'] ?? '').trim();
    if (u.isNotEmpty) {
      PaymentConfig.callbackUrl = u;
    }
  }

  static int amountToHalalas(double amountSar) => (amountSar * 100).round();

  /// إنشاء سجل [billing_transactions] بحالة `pending` **قبل** بدء الدفع (ميسّر أو وهمي).
  Future<Map<String, dynamic>> createPendingBillingTransaction({
    required double amount,
    String currency = 'SAR',
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
    required String paymentMethod,
    String? cardId,
    Map<String, dynamic>? gatewayPendingMeta,
  }) async {
    final uid = _user?.id;
    if (uid == null) {
      return {'ok': false, 'error': 'auth'};
    }
    try {
      final row = await _sb.from(_tx).insert({
        'user_id': uid,
        'subscription_id': subscriptionId,
        'amount': amount,
        'currency': currency,
        'status': 'pending',
        'payment_method': paymentMethod,
        'card_id': cardId,
        'title_ar': titleAr,
        'title_en': titleEn,
        'gateway_response': {
          'pending_gateway': 'moyasar',
          'merchant_contact': billingAuthorizedContactName,
          ...?gatewayPendingMeta,
        },
      }).select('id').single();
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) return {'ok': false, 'error': 'no_id'};
      return {'ok': true, 'transaction_id': id, 'row': row};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Map<String, String> buildMoyasarSubscriptionMetadata({
    required String billingTransactionId,
    required String purpose,
  }) {
    final uid = _user?.id ?? '';
    return {
      'billing_transaction_id': billingTransactionId,
      'user_id': uid,
      'purpose': purpose,
      'merchant_contact': billingAuthorizedContactName,
      'product': 'aqar_reliable',
    };
  }

  PaymentConfig buildMoyasarPaymentConfig({
    required int amountHalalas,
    required String description,
    required Map<String, String> metadata,
    required bool madaPreferredNetworksOnly,
    ApplePayConfig? applePay,
    SamsungPayConfig? samsungPay,
  }) {
    configureMoyasarCallbackUrlFromEnv();
    final callback = PaymentConfig.callbackUrl.trim();
    if (callback.isEmpty || callback.contains('example.com')) {
      throw StateError('MOYASAR_CALLBACK_URL missing or invalid');
    }
    final key = moyasarPublishableKey;
    if (key == null || key.isEmpty) {
      throw StateError('MOYASAR_PUBLISHABLE_KEY missing');
    }
    final halalas = amountHalalas < 100 ? 100 : amountHalalas;
    final networks = madaPreferredNetworksOnly
        ? <PaymentNetwork>[
            PaymentNetwork.mada,
            PaymentNetwork.visa,
            PaymentNetwork.masterCard,
          ]
        : <PaymentNetwork>[
            PaymentNetwork.visa,
            PaymentNetwork.mada,
            PaymentNetwork.masterCard,
          ];
    final k = key.trim();
    return PaymentConfig(
      publishableApiKey: k,
      amount: halalas,
      currency: 'SAR',
      description: description,
      metadata: Map<String, dynamic>.from(metadata),
      supportedNetworks: networks,
      applePay: applePay,
      samsungPay: samsungPay,
      creditCard: CreditCardConfig(saveCard: true, manual: false),
      // pk_test_ و pk_live_ يستخدمان نفس api.moyasar.com — التمييز من بادئة المفتاح.
      baseUrl: null,
    );
  }

  /// هل اكتمل الدفع عبر ميسّر (بما فيه 3DS)؟
  static bool moyasarPaymentSucceeded(PaymentResponse response) =>
      response.status == PaymentStatus.paid ||
      response.status == PaymentStatus.authorized ||
      response.status == PaymentStatus.captured;

  /// يحوّل نتيجة نموذج ميسّر إلى رمز خطأ داخلي.
  static String? mapMoyasarResultToError(dynamic result) {
    if (result is PaymentResponse) {
      if (moyasarPaymentSucceeded(result)) return null;
      if (result.status == PaymentStatus.failed) return 'moyasar_failed';
      return 'moyasar_cancelled_or_failed';
    }
    if (result is AuthError) return 'moyasar_auth_error';
    if (result is ValidationError) {
      final msg = result.message.trim();
      final lower = msg.toLowerCase();
      if (lower.contains('inactive') || lower.contains('activated')) {
        return 'moyasar_account_inactive';
      }
      if (msg.isNotEmpty) return 'moyasar_validation:$msg';
      return 'moyasar_validation_error';
    }
    if (result is ApiError) {
      final msg = result.message.trim();
      final lower = msg.toLowerCase();
      if (lower.contains('inactive') || lower.contains('activated')) {
        return 'moyasar_account_inactive';
      }
      if (msg.isNotEmpty) return 'moyasar_api:$msg';
    }
    final raw = '$result'.toLowerCase();
    if (raw.contains('inactive') || raw.contains('405')) {
      return 'moyasar_account_inactive';
    }
    return 'moyasar_cancelled_or_failed';
  }

  /// يحذف البطاقات الوهمية (mock_*) — لا تصلح للدفع عبر ميسّر.
  Future<int> purgeMockSavedCards() async {
    final uid = _user?.id;
    if (uid == null) return 0;
    try {
      final rows = await _sb
          .from(_cards)
          .select('id,card_token')
          .eq('user_id', uid);
      var n = 0;
      for (final row in rows as List) {
        final m = Map<String, dynamic>.from(row as Map);
        if (!isMockCardToken(m['card_token'])) continue;
        await _sb.from(_cards).delete().eq('id', '${m['id']}').eq('user_id', uid);
        n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// فحص ترابط إعدادات ميسّر على الخادم (بدون كشف الأسرار).
  Future<Map<String, dynamic>> checkMoyasarServerHealth() async {
    try {
      final res = await _sb.functions.invoke(
        'moyasar-payment-health',
        body: {
          'publishable_prefix': (moyasarPublishableKey ?? '').length >= 7
              ? (moyasarPublishableKey ?? '').substring(0, 7)
              : '',
        },
      );
      if (res.data is Map) {
        return Map<String, dynamic>.from(
          (res.data as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// يتحقق لمرة واحدة من نجاح السجل ومبلغه (بعد Webhook أو تحديث الخادم).
  Future<Map<String, dynamic>> verifyBillingTransactionPaid({
    required String billingTransactionId,
    required double expectedAmountSar,
    String expectedCurrency = 'SAR',
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      final row = await _sb
          .from(_tx)
          .select('id,user_id,status,amount,currency,gateway_transaction_id')
          .eq('id', billingTransactionId)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return {'ok': false, 'error': 'not_found'};
      if (row['status'] != 'success') {
        return {'ok': false, 'error': 'pending', 'status': row['status']};
      }
      final amt = _toDouble(row['amount']);
      final cur = '${row['currency'] ?? 'SAR'}'.toUpperCase();
      if (cur != expectedCurrency.toUpperCase()) {
        return {'ok': false, 'error': 'currency_mismatch'};
      }
      if ((amt - expectedAmountSar).abs() > 0.009) {
        return {'ok': false, 'error': 'amount_mismatch'};
      }
      return {
        'ok': true,
        'gateway_transaction_id': row['gateway_transaction_id'],
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// ينتظر تأكيد Webhook على `billing_transactions` (حتى ~30 ثانية).
  Future<Map<String, dynamic>> pollUntilBillingTransactionPaid({
    required String billingTransactionId,
    required double expectedAmountSar,
    int maxAttempts = 30,
    Duration step = const Duration(seconds: 1),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final v = await verifyBillingTransactionPaid(
        billingTransactionId: billingTransactionId,
        expectedAmountSar: expectedAmountSar,
      );
      if (v['ok'] == true) return v;
      if ('${v['error']}' == 'not_found') return v;
      final st = '${v['status'] ?? ''}';
      if (st == 'failed' || v['error'] == 'amount_mismatch') {
        return {'ok': false, 'error': v['error'] ?? 'failed'};
      }
      await Future<void>.delayed(step);
    }
    return {'ok': false, 'error': 'webhook_timeout'};
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static const int maxSavedCards = 8;

  Future<int> savedCardCount() async {
    final cards = await getSavedCards();
    return cards.length;
  }

  Future<bool> canAddMoreCards() async =>
      (await savedCardCount()) < maxSavedCards;

  Future<List<Map<String, dynamic>>> getSavedCards() async {
    final uid = _user?.id;
    if (uid == null) return [];
    try {
      final rows = await _sb
          .from(_cards)
          .select()
          .eq('user_id', uid)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    return [];
  }

  /// هل البطاقة المحفوظة تستخدم رمزاً وهمياً (mock) وليس رمز ميسّر؟
  Future<bool> savedCardUsesMockGateway(String cardId) async {
    final uid = _user?.id;
    if (uid == null || cardId.trim().isEmpty) return true;
    try {
      final row = await _sb
          .from(_cards)
          .select('card_token')
          .eq('id', cardId)
          .eq('user_id', uid)
          .maybeSingle();
      final token = row?['card_token']?.toString() ?? '';
      return token.isEmpty || token.startsWith('mock_');
    } catch (_) {
      return true;
    }
  }

  /// هل رمز البطاقة المحفوظة وهمي (قبل ربط ميسّر)؟
  static bool isMockCardToken(dynamic token) {
    final t = '${token ?? ''}'.trim();
    return t.isEmpty || t.startsWith('mock_');
  }

  /// هل يمكن خصم هذه البطاقة عبر ميسّر (token حقيقي من البوابة)؟
  static bool isMoyasarReadyCardToken(dynamic token) =>
      !isMockCardToken(token);

  /// هل انتهت صلاحية البطاقة المحفوظة؟
  static bool isCardExpired(Map<String, dynamic> row) {
    final mm = int.tryParse('${row['expiry_month']}') ?? 0;
    var yy = int.tryParse('${row['expiry_year']}') ?? 0;
    if (yy < 100) yy += 2000;
    // رموز ميسّر المحفوظة عبر البوابة قد لا تتضمن تاريخاً حقيقياً.
    if (isMoyasarReadyCardToken(row['card_token']) && yy >= 2090) {
      return false;
    }
    if (mm < 1 || mm > 12 || yy < 2000) return true;
    final endOfMonth = DateTime(yy, mm + 1, 0, 23, 59, 59);
    return DateTime.now().isAfter(endOfMonth);
  }

  /// هل يمكن خصم البطاقة مباشرة (رمز ميسّر صالح وغير منتهٍ)؟
  static bool canChargeSavedCard(Map<String, dynamic> row) =>
      isMoyasarReadyCardToken(row['card_token']) && !isCardExpired(row);

  static String _lastFourFromMaskedNumber(String masked) {
    final digits = masked.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    return digits.isEmpty ? '0000' : digits;
  }

  static String _schemeFromMoyasarCompany(CardCompany? company) {
    if (company == null) return 'visa';
    switch (company) {
      case CardCompany.mada:
        return 'mada';
      case CardCompany.master:
        return 'mastercard';
      case CardCompany.amex:
        return 'amex';
      case CardCompany.visa:
        return 'visa';
    }
  }

  /// يحفظ أو يحدّث بطاقة من استجابة دفع ميسّر ناجحة (رمز token للخصم لاحقاً).
  Future<Map<String, dynamic>> persistMoyasarCardFromPaymentResponse(
    PaymentResponse response, {
    bool setDefault = false,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    if (response.status != PaymentStatus.paid) {
      return {'ok': false, 'error': 'not_paid'};
    }
    final src = response.source;
    if (src is! CardPaymentResponseSource) {
      return {'ok': false, 'error': 'not_card_source'};
    }
    final token = src.token?.trim() ?? '';
    if (token.isEmpty || isMockCardToken(token)) {
      return {'ok': false, 'error': 'no_token'};
    }
    final last4 = _lastFourFromMaskedNumber(src.number);
    final scheme = _schemeFromMoyasarCompany(src.company);
    final holder = src.name.trim();
    try {
      final existing = await _sb
          .from(_cards)
          .select('id')
          .eq('user_id', uid)
          .eq('card_token', token)
          .maybeSingle();
      if (existing != null) {
        return {'ok': true, 'card_id': '${existing['id']}', 'duplicate': true};
      }
      final countRows =
          await _sb.from(_cards).select('id').eq('user_id', uid);
      if ((countRows as List).length >= maxSavedCards) {
        return {'ok': false, 'error': 'max_cards_reached'};
      }
      await _sb
          .from(_cards)
          .delete()
          .eq('user_id', uid)
          .like('card_token', 'mock_%')
          .eq('last_four', last4);
      if (setDefault) {
        await _sb.from(_cards).update({'is_default': false}).eq('user_id', uid);
      }
      final hasAny = await _sb.from(_cards).select('id').eq('user_id', uid).limit(1);
      final makeDefault = setDefault || (hasAny as List).isEmpty;
      final row = await _sb.from(_cards).insert({
        'user_id': uid,
        'card_token': token,
        'last_four': last4,
        'card_scheme': scheme,
        'card_holder_name': holder.isEmpty ? null : holder,
        'expiry_month': 12,
        'expiry_year': 2099,
        'is_default': makeDefault,
      }).select().maybeSingle();
      return {'ok': true, 'row': row};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// خصم مباشر عبر رمز البطاقة المحفوظة (ميسّر token API على الخادم).
  Future<Map<String, dynamic>> chargeSavedCardViaMoyasar({
    required String billingTransactionId,
    required String cardId,
    required String purpose,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      final res = await _sb.functions.invoke(
        chargeSavedCardFunction,
        body: {
          'billing_transaction_id': billingTransactionId,
          'card_id': cardId,
          'purpose': purpose,
        },
      );
      final data = res.data;
      if (data is! Map) {
        return {'ok': false, 'error': 'unexpected_response'};
      }
      final out = Map<String, dynamic>.from(
        data.map((k, v) => MapEntry(k.toString(), v)),
      );
      final msg = '${out['moyasar_message'] ?? ''}'.trim();
      if (out['ok'] != true && msg.isNotEmpty) {
        out['error'] = 'moyasar_api:$msg';
      }
      return out;
    } on FunctionException catch (e) {
      final parsed = _parseEdgeFunctionErrorBody(e);
      if (parsed != null) {
        final msg = '${parsed['moyasar_message'] ?? ''}'.trim();
        if (parsed['ok'] != true && msg.isNotEmpty) {
          parsed['error'] = 'moyasar_api:$msg';
        }
        return parsed;
      }
      final msg = '${e.reasonPhrase ?? e.details ?? e}'.toLowerCase();
      if (msg.contains('mock_token')) {
        return {'ok': false, 'error': 'mock_token'};
      }
      if (msg.contains('502') || msg.contains('bad gateway')) {
        return {
          'ok': false,
          'error': 'moyasar_rejected',
          'detail': e.details,
        };
      }
      return {'ok': false, 'error': e.reasonPhrase ?? 'edge_function_error'};
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('mock_token')) {
        return {'ok': false, 'error': 'mock_token'};
      }
      if (msg.contains('cors') ||
          msg.contains('failed to fetch') ||
          msg.contains('clientexception')) {
        return {
          'ok': false,
          'error': 'cors_or_function_unreachable',
          'detail': e.toString(),
        };
      }
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Map<String, dynamic>? _parseEdgeFunctionErrorBody(FunctionException e) {
    final raw = e.details;
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>> addCard({
    required String cardNumberDigits,
    required String holderName,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    String? label,
    bool setDefault = false,
  }) async {
    final uid = _user?.id;
    if (uid == null) {
      return {'ok': false, 'error': 'auth'};
    }
    if (useMoyasarLiveFlow) {
      return {'ok': false, 'error': 'moyasar_cards_via_payment'};
    }
    if (!allowMockGateway) {
      return Map<String, dynamic>.from(_mockGatewayBlocked);
    }
    if (!(await canAddMoreCards())) {
      return {'ok': false, 'error': 'max_cards_reached'};
    }
    final err = PaymentGatewayMock.mockValidateCard(
      cardNumberDigits: cardNumberDigits,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: cvv,
      holderName: holderName,
    );
    if (err != null) {
      return {'ok': false, 'error': err};
    }
    final digits = cardNumberDigits.replaceAll(RegExp(r'\D'), '');
    final bin = digits.length >= 6 ? digits.substring(0, 6) : digits;
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    final scheme = detectCardSchemeFromPan(digits);
    final token = PaymentGatewayMock.issueCardToken(
      cardBin: bin,
      lastFour: last4,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
    );
    try {
      if (setDefault) {
        await _sb.from(_cards).update({'is_default': false}).eq('user_id', uid);
      }
      final row = await _sb.from(_cards).insert({
        'user_id': uid,
        'card_token': token,
        'card_bin': bin,
        'last_four': last4,
        'card_scheme': scheme,
        'card_holder_name': holderName.trim(),
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'label': label?.trim().isEmpty ?? true ? null : label!.trim(),
        'is_default': setDefault,
      }).select().maybeSingle();
      return {'ok': true, 'row': row};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteCard(String cardId) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      await _sb.from(_cards).delete().eq('id', cardId).eq('user_id', uid);
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> setDefaultCard(String cardId) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      final row = await _sb
          .from(_cards)
          .select('expiry_month,expiry_year,card_token')
          .eq('id', cardId)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return {'ok': false, 'error': 'not_found'};
      if (isCardExpired(Map<String, dynamic>.from(row as Map))) {
        return {'ok': false, 'error': 'card_expired'};
      }
      await _sb.from(_cards).update({'is_default': false}).eq('user_id', uid);
      await _sb
          .from(_cards)
          .update({'is_default': true})
          .eq('id', cardId)
          .eq('user_id', uid);
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateCardLabel({
    required String cardId,
    String? label,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    final trimmed = label?.trim();
    try {
      await _sb
          .from(_cards)
          .update({'label': (trimmed == null || trimmed.isEmpty) ? null : trimmed})
          .eq('id', cardId)
          .eq('user_id', uid);
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> processPayment({
    required double amount,
    String currency = 'SAR',
    String? cardId,
    String? cardTokenDirect,
    String? paymentMethod,
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    if (!useMoyasarLiveFlow && !allowMockGateway) {
      return Map<String, dynamic>.from(_mockGatewayBlocked);
    }
    String? token = cardTokenDirect;
    if (token == null && cardId != null) {
      try {
        final row = await _sb
            .from(_cards)
            .select('card_token')
            .eq('id', cardId)
            .eq('user_id', uid)
            .maybeSingle();
        token = row?['card_token']?.toString();
      } catch (_) {}
    }
    if (token == null || token.isEmpty) {
      return {'ok': false, 'error': 'no_card'};
    }
    Map<String, dynamic>? inserted;
    try {
      inserted = Map<String, dynamic>.from(
        (await _sb.from(_tx).insert({
          'user_id': uid,
          'subscription_id': subscriptionId,
          'amount': amount,
          'currency': currency,
          'status': 'pending',
          'payment_method': paymentMethod ?? 'card',
          'card_id': cardId,
          'title_ar': titleAr,
          'title_en': titleEn,
        }).select().single()) as Map,
      );
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    final txId = inserted['id']?.toString() ?? '';
    final ok = PaymentGatewayMock.mockProcessPayment(
      cardToken: token,
      amountKey: '${amount.toStringAsFixed(2)}_$currency',
    );
    final gatewayId = PaymentGatewayMock.mockGatewayTransactionId();
    try {
      await _sb.from(_tx).update({
        'status': ok ? 'success' : 'failed',
        'gateway_transaction_id': gatewayId,
        'gateway_response': {'mock': true, 'ok': ok},
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', txId);
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'transaction_id': txId};
    }
    if (ok) {
      unawaited(_notifyBillingSuccess(
        sb: _sb,
        userId: uid,
        amount: amount,
        currency: currency,
        gatewayId: gatewayId,
        titleAr: titleAr,
        titleEn: titleEn,
        txRowId: txId,
      ));
    }
    return {
      'ok': ok,
      'transaction_id': txId,
      'gateway_transaction_id': gatewayId,
    };
  }

  /// دفع مقابل صف [billing_transactions] موجود (pending) — طلب فوري، رسوم، …
  Future<Map<String, dynamic>> processPaymentAgainstExistingBilling({
    required String billingTransactionId,
    required double amount,
    String? cardId,
    String? cardTokenDirect,
    String? paymentMethod,
    String? titleAr,
    String? titleEn,
    String purpose = 'one_time',
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    if (!useMoyasarLiveFlow && !allowMockGateway) {
      return Map<String, dynamic>.from(_mockGatewayBlocked);
    }
    final bid = billingTransactionId.trim();
    if (bid.isEmpty) return {'ok': false, 'error': 'no_billing_id'};

    try {
      final existing = await _sb
          .from(_tx)
          .select('id,status,amount,user_id')
          .eq('id', bid)
          .eq('user_id', uid)
          .maybeSingle();
      if (existing == null) return {'ok': false, 'error': 'billing_not_found'};
      if ('${existing['status']}' != 'pending') {
        return {'ok': false, 'error': 'billing_not_pending'};
      }
      if ((_toDouble(existing['amount']) - amount).abs() > 0.05) {
        return {'ok': false, 'error': 'amount_mismatch'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }

    final cid = cardId?.trim() ?? '';
    if (cid.isEmpty && (cardTokenDirect == null || cardTokenDirect.isEmpty)) {
      return {'ok': false, 'error': 'no_card'};
    }

    if (useMoyasarLiveFlow && cid.isNotEmpty) {
      return chargeSavedCardViaMoyasar(
        billingTransactionId: bid,
        cardId: cid,
        purpose: purpose,
      );
    }

    String? token = cardTokenDirect;
    if (token == null && cid.isNotEmpty) {
      try {
        final row = await _sb
            .from(_cards)
            .select('card_token')
            .eq('id', cid)
            .eq('user_id', uid)
            .maybeSingle();
        token = row?['card_token']?.toString();
      } catch (_) {}
    }
    if (token == null || token.isEmpty) {
      return {'ok': false, 'error': 'no_card'};
    }

    final ok = PaymentGatewayMock.mockProcessPayment(
      cardToken: token,
      amountKey: '${amount.toStringAsFixed(2)}_$bid',
    );
    final gatewayId = PaymentGatewayMock.mockGatewayTransactionId();
    try {
      await _sb.from(_tx).update({
        'status': ok ? 'success' : 'failed',
        'payment_method': paymentMethod ?? 'card',
        'card_id': cardId,
        'title_ar': titleAr,
        'title_en': titleEn,
        'gateway_transaction_id': gatewayId,
        'gateway_response': {
          'mock': true,
          'ok': ok,
          'purpose': purpose,
        },
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', bid).eq('user_id', uid);
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'transaction_id': bid};
    }

    if (ok) {
      unawaited(_notifyBillingSuccess(
        sb: _sb,
        userId: uid,
        amount: amount,
        currency: 'SAR',
        gatewayId: gatewayId,
        titleAr: titleAr,
        titleEn: titleEn,
        txRowId: bid,
      ));
    }
    return {
      'ok': ok,
      'transaction_id': bid,
      'gateway_transaction_id': gatewayId,
    };
  }

  Future<Map<String, dynamic>> processApplePay({
    required double amount,
    String currency = 'SAR',
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return {'ok': false, 'error': 'apple_pay_platform'};
    }
    return _walletFlow(
      wallet: 'apple_pay',
      amount: amount,
      currency: currency,
      subscriptionId: subscriptionId,
      titleAr: titleAr,
      titleEn: titleEn,
    );
  }

  Future<Map<String, dynamic>> processMadaPay({
    required double amount,
    String currency = 'SAR',
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
  }) async {
    return _walletFlow(
      wallet: 'mada_pay',
      amount: amount,
      currency: currency,
      subscriptionId: subscriptionId,
      titleAr: titleAr,
      titleEn: titleEn,
    );
  }

  Future<Map<String, dynamic>> _walletFlow({
    required String wallet,
    required double amount,
    required String currency,
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    if (!useMoyasarLiveFlow && !allowMockGateway) {
      return Map<String, dynamic>.from(_mockGatewayBlocked);
    }
    Map<String, dynamic>? inserted;
    try {
      inserted = Map<String, dynamic>.from(
        (await _sb.from(_tx).insert({
          'user_id': uid,
          'subscription_id': subscriptionId,
          'amount': amount,
          'currency': currency,
          'status': 'pending',
          'payment_method': wallet,
          'title_ar': titleAr,
          'title_en': titleEn,
        }).select().single()) as Map,
      );
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    final txId = inserted['id']?.toString() ?? '';
    final ok = PaymentGatewayMock.mockWalletPay(walletKind: wallet);
    final gatewayId = PaymentGatewayMock.mockGatewayTransactionId();
    try {
      await _sb.from(_tx).update({
        'status': ok ? 'success' : 'failed',
        'gateway_transaction_id': gatewayId,
        'gateway_response': {'mock': true, 'wallet': wallet, 'ok': ok},
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', txId);
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'transaction_id': txId};
    }
    if (ok) {
      unawaited(_notifyBillingSuccess(
        sb: _sb,
        userId: uid,
        amount: amount,
        currency: currency,
        gatewayId: gatewayId,
        titleAr: titleAr,
        titleEn: titleEn,
        txRowId: txId,
      ));
    }
    return {
      'ok': ok,
      'transaction_id': txId,
      'gateway_transaction_id': gatewayId,
    };
  }

  Future<Map<String, dynamic>> deleteBillingTransaction(String txId) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    final id = txId.trim();
    if (id.isEmpty) return {'ok': false, 'error': 'no_id'};
    try {
      await _sb.from(_tx).delete().eq('id', id).eq('user_id', uid);
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> listTransactions({
    String? status,
    String? search,
    int limit = 100,
  }) async {
    final uid = _user?.id;
    if (uid == null) return [];
    try {
      var q = _sb
          .from(_tx)
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = await q;
      var list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (status != null && status.isNotEmpty && status != 'all') {
        list = list.where((e) => e['status'] == status).toList();
      }
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim().toLowerCase();
        list = list.where((e) {
          final id = '${e['gateway_transaction_id'] ?? ''}'.toLowerCase();
          final ta = '${e['title_ar'] ?? ''}'.toLowerCase();
          final te = '${e['title_en'] ?? ''}'.toLowerCase();
          return id.contains(s) || ta.contains(s) || te.contains(s);
        }).toList();
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _notifyBillingSuccess({
    required SupabaseClient sb,
    required String userId,
    required double amount,
    required String currency,
    required String? gatewayId,
    required String? titleAr,
    required String? titleEn,
    required String txRowId,
  }) async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      await InAppNotificationWriter.insert(
        sb,
        userId: userId,
        type: InAppNotifTypes.billingPaymentSuccess,
        data: {
          WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.subscriptionsHub,
          'account_type':
              AccountRoleCache.snapshot?.accountType ?? 'user',
          'title_ar': titleAr ?? 'تم تأكيد الدفع',
          'title_en': titleEn ?? 'Payment confirmed',
          'body_ar':
              'المبلغ ${amount.toStringAsFixed(2)} $currency — راجع سجل المدفوعات.',
          'body_en':
              'Amount ${amount.toStringAsFixed(2)} $currency — see payment history.',
          'gateway_transaction_id': gatewayId,
          'billing_tx_id': txRowId,
        },
        entityType: InAppEntityTypes.billingTransaction,
        entityId: txRowId,
      );
    } catch (_) {}
  }

  Future<void> linkBillingToSubscription({
    required String billingTransactionId,
    required String subscriptionId,
  }) async {
    final uid = _user?.id;
    if (uid == null) return;
    try {
      await _sb
          .from(_tx)
          .update({'subscription_id': subscriptionId})
          .eq('id', billingTransactionId)
          .eq('user_id', uid);
    } catch (_) {}
  }

  /// يُستدعى بعد نجاح ميسّر + تأكيد السجل في Supabase (Webhook).
  Future<void> notifyBillingSuccessForTransaction({
    required String billingTransactionId,
    required double amount,
    String currency = 'SAR',
    String? titleAr,
    String? titleEn,
  }) async {
    final uid = _user?.id;
    if (uid == null) return;
    final gid = await _sb
        .from(_tx)
        .select('gateway_transaction_id')
        .eq('id', billingTransactionId)
        .eq('user_id', uid)
        .maybeSingle();
    final g = gid?['gateway_transaction_id']?.toString();
    await _notifyBillingSuccess(
      sb: _sb,
      userId: uid,
      amount: amount,
      currency: currency,
      gatewayId: g,
      titleAr: titleAr,
      titleEn: titleEn,
      txRowId: billingTransactionId,
    );
  }

  /// تاريخ/وقت بأرقام لاتينية (للفواتير والتقارير).
  static String formatLatinDateTime(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm', 'en_US').format(dt.toLocal());

  static PdfColor get _invoiceBrand => PdfColor.fromInt(0xFF1A237E);
  static PdfColor get _invoiceBrandLight => PdfColor.fromInt(0xFFE8EAF6);

  static Future<({pw.Font base, pw.Font bold})> _invoiceFonts() async {
    pw.Font? arabicFont;
    try {
      final data = await rootBundle.load('assets/fonts/arabic_pdf_regular.ttf');
      arabicFont = pw.Font.ttf(data);
    } catch (_) {
      arabicFont = null;
    }
    final base = arabicFont ?? pw.Font.helvetica();
    return (base: base, bold: base);
  }

  static Future<pw.ImageProvider?> _invoiceLogo() => loadBrandingPdfLogo();

  static pw.Widget _invoiceHeader({
    required pw.Font base,
    required pw.Font bold,
    required pw.ImageProvider? logo,
    required bool isAr,
    required String invoiceRef,
    required String issuedAt,
    required String docTitle,
  }) {
    String t(String ar, String en) => isAr ? ar : en;
    final platformName = AppBranding.legalName(isAr: isAr);
    final shortBrand = AppBranding.brandName(isAr: isAr);
    final contactLine = isAr
        ? '${AppBranding.supportEmail} · ${AppBranding.supportPhone}'
        : '${AppBranding.supportEmail} · ${AppBranding.supportPhone}';

    final logoBox = pw.Container(
      width: 76,
      height: 76,
      padding: const pw.EdgeInsets.all(6),
      child: logo != null
          ? pw.Image(logo, fit: pw.BoxFit.contain)
          : pw.Center(
              child: pw.Text(
                shortBrand,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 11,
                  color: _invoiceBrand,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
    );

    final metaColumn = pw.Column(
      crossAxisAlignment: isAr
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          docTitle,
          style: pw.TextStyle(font: bold, fontSize: 12, color: _invoiceBrand),
          textAlign: isAr ? pw.TextAlign.start : pw.TextAlign.end,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${t('رقم الفاتورة', 'Invoice No.')}: $invoiceRef',
          style: pw.TextStyle(font: base, fontSize: 9, color: PdfColors.grey800),
          textAlign: isAr ? pw.TextAlign.start : pw.TextAlign.end,
        ),
        pw.Text(
          '${t('التاريخ', 'Date')}: $issuedAt',
          style: pw.TextStyle(font: base, fontSize: 9, color: PdfColors.grey800),
          textAlign: isAr ? pw.TextAlign.start : pw.TextAlign.end,
        ),
      ],
    );

    final brandColumn = pw.Column(
      crossAxisAlignment: isAr
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          platformName,
          style: pw.TextStyle(font: bold, fontSize: 11, color: _invoiceBrand),
          textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          AppBranding.legalNoticeLine(isAr: isAr),
          style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey700),
          textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
        ),
        pw.Text(
          contactLine,
          style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey700),
          textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            t('بسم الله الرحمن الرحيم', 'In the name of Allah, the Most Gracious'),
            style: pw.TextStyle(font: bold, fontSize: 10, color: _invoiceBrand),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: isAr
              ? [metaColumn, pw.SizedBox(width: 18), logoBox, pw.SizedBox(width: 18), pw.Expanded(child: brandColumn)]
              : [pw.Expanded(child: brandColumn), pw.SizedBox(width: 18), logoBox, pw.SizedBox(width: 18), metaColumn],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: _invoiceBrand),
      ],
    );
  }

  /// فاتورة PDF — شعار، بسملة، ترويسة، جدول، بيانات شريكنا العقاري.
  static Future<Uint8List> buildInvoicePdf({
    required String title,
    required String txnId,
    required String amountLine,
    required String statusLine,
    String? footer,
    String? planName,
    String? periodLabel,
    String? paymentMethod,
    String? paidAtFormatted,
    String? subscriptionId,
    String? payerName,
    String? purposeLabel,
    String? userFullName,
    String? userEmail,
    String? userPhone,
    String? invoiceDateFormatted,
    bool isAr = true,
  }) async {
    final fonts = await _invoiceFonts();
    final base = fonts.base;
    final bold = fonts.bold;
    final logo = await _invoiceLogo();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold));
    final issuedAt =
        invoiceDateFormatted ?? formatLatinDateTime(DateTime.now());

    String t(String ar, String en) => isAr ? ar : en;

    pw.Widget infoRow(String label, String? value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return pw.SizedBox();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 118,
              child: pw.Text(
                label,
                style: pw.TextStyle(font: bold, fontSize: 10),
                textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Text(
                v,
                style: pw.TextStyle(font: base, fontSize: 10),
                textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget tableCell(
      String text, {
      bool header = false,
      pw.TextAlign align = pw.TextAlign.center,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: header ? bold : base,
            fontSize: header ? 10 : 9,
            color: header ? PdfColors.white : PdfColors.black,
          ),
          textAlign: align,
        ),
      );
    }

    final clientName = (userFullName ?? payerName ?? '').trim();
    final clientEmail = (userEmail ?? '').trim();
    final clientPhone = (userPhone ?? '').trim();
    final lineDesc = AppBranding.billingDisplayTitle(
      rawTitle: (planName ?? title).trim(),
      isAr: isAr,
      periodHint: periodLabel,
    );
    final linePeriod = (periodLabel ?? '—').trim();
    final displayTitle = AppBranding.billingDisplayTitle(
      rawTitle: title,
      isAr: isAr,
      periodHint: periodLabel,
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _invoiceHeader(
              base: base,
              bold: bold,
              logo: logo,
              isAr: isAr,
              invoiceRef: txnId,
              issuedAt: issuedAt,
              docTitle: t('فاتورة رسمية', 'Official invoice'),
            ),
            pw.SizedBox(height: 18),
            pw.Center(
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 420),
                child: pw.Text(
                  displayTitle,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 16,
                    color: _invoiceBrand,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 460),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: _invoiceBrandLight,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        AppBranding.invoicePartnerSectionTitle(isAr: isAr),
                        style: pw.TextStyle(font: bold, fontSize: 11),
                        textAlign: isAr ? pw.TextAlign.end : pw.TextAlign.start,
                      ),
                      pw.SizedBox(height: 6),
                      infoRow(
                        AppBranding.invoicePartnerLabel(isAr: isAr),
                        clientName.isEmpty ? null : clientName,
                      ),
                      infoRow(t('البريد', 'Email'),
                          clientEmail.isEmpty ? null : clientEmail),
                      infoRow(t('الجوال', 'Phone'),
                          clientPhone.isEmpty ? null : clientPhone),
                      infoRow(t('طريقة الدفع', 'Payment method'), paymentMethod),
                      if ((paidAtFormatted ?? '').isNotEmpty)
                        infoRow(t('تاريخ الدفع', 'Paid at'), paidAtFormatted),
                      if ((subscriptionId ?? '').isNotEmpty)
                        infoRow(t('رقم الاشتراك', 'Subscription'), subscriptionId),
                      if ((purposeLabel ?? '').isNotEmpty)
                        infoRow(t('نوع العملية', 'Purpose'), purposeLabel),
                    ],
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 460),
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.55),
                    1: const pw.FlexColumnWidth(2.5),
                    2: const pw.FlexColumnWidth(1.1),
                    3: const pw.FlexColumnWidth(1.1),
                    4: const pw.FlexColumnWidth(0.95),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: _invoiceBrand),
                      children: [
                        tableCell('#', header: true),
                        tableCell(t('البيان', 'Description'), header: true),
                        tableCell(t('الفترة', 'Period'), header: true),
                        tableCell(t('المبلغ', 'Amount'), header: true),
                        tableCell(t('الحالة', 'Status'), header: true),
                      ],
                    ),
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.white),
                      children: [
                        tableCell('1'),
                        tableCell(
                          lineDesc,
                          align: isAr ? pw.TextAlign.end : pw.TextAlign.start,
                        ),
                        tableCell(linePeriod),
                        tableCell(amountLine),
                        tableCell(statusLine),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 460),
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        t('الإجمالي', 'Total'),
                        style: pw.TextStyle(font: bold, fontSize: 12),
                      ),
                      pw.Text(
                        amountLine,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 14,
                          color: _invoiceBrand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Center(
              child: pdfReadableQrBlock(
                data: 'TXN:$txnId|AMT:$amountLine|STATUS:$statusLine',
                isAr: isAr,
                font: base,
                fontBold: bold,
                size: 104,
                title: t('رمز التحقق من الفاتورة', 'Invoice verification QR'),
                hint: t(
                  'امسح الرمز للتحقق من رقم العملية',
                  'Scan to verify transaction reference',
                ),
                brandColor: _invoiceBrand,
              ),
            ),
            pw.Spacer(),
            if (footer != null && footer.isNotEmpty)
              pw.Text(
                footer,
                style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              AppBranding.copyrightLine(isAr: isAr),
              style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// تقرير PDF لكل الفواتير (طباعة الكل حسب التبويب).
  static Future<Uint8List> buildInvoicesReportPdf({
    required List<Map<String, String>> rows,
    required bool isAr,
    String? generatedAtFormatted,
    String? reportTitleAr,
    String? reportTitleEn,
  }) async {
    final fonts = await _invoiceFonts();
    final base = fonts.base;
    final bold = fonts.bold;
    final logo = await _invoiceLogo();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold));
    final issuedAt =
        generatedAtFormatted ?? formatLatinDateTime(DateTime.now());
    String t(String ar, String en) => isAr ? ar : en;
    final reportTitle = isAr
        ? (reportTitleAr ?? 'تقرير الفواتير')
        : (reportTitleEn ?? 'Invoices report');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (ctx) => [
          _invoiceHeader(
            base: base,
            bold: bold,
            logo: logo,
            isAr: isAr,
            invoiceRef: 'RPT-${DateTime.now().millisecondsSinceEpoch}',
            issuedAt: issuedAt,
            docTitle: reportTitle,
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxWidth: 500),
              child: pw.TableHelper.fromTextArray(
                headers: [
                  '#',
                  t('رقم العملية', 'Reference'),
                  t('التاريخ', 'Date'),
                  t('البيان', 'Description'),
                  t('المبلغ', 'Amount'),
                  t('الحالة', 'Status'),
                  t('طريقة الدفع', 'Method'),
                ],
                data: [
                  for (var i = 0; i < rows.length; i++)
                    [
                      '${i + 1}',
                      rows[i]['ref'] ?? '',
                      rows[i]['date'] ?? '',
                      AppBranding.billingDisplayTitle(
                        rawTitle: rows[i]['title'] ?? '',
                        isAr: isAr,
                      ),
                      rows[i]['amount'] ?? '',
                      rows[i]['status'] ?? '',
                      rows[i]['method'] ?? '',
                    ],
                ],
                headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: _invoiceBrand),
                cellStyle: pw.TextStyle(font: base, fontSize: 8),
                cellHeight: 24,
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: isAr ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
                  4: pw.Alignment.center,
                  5: pw.Alignment.center,
                  6: pw.Alignment.center,
                },
                oddRowDecoration: pw.BoxDecoration(color: _invoiceBrandLight),
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pdfReadableQrBlock(
              data:
                  'INVOICES_REPORT|${DateTime.now().toIso8601String()}|count=${rows.length}',
              isAr: isAr,
              font: base,
              fontBold: bold,
              size: 96,
              title: t('مرجع تقرير الفواتير', 'Invoices report QR'),
              brandColor: _invoiceBrand,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              AppBranding.copyrightLine(isAr: isAr),
              style: pw.TextStyle(font: base, fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// صفحة PDF عند عدم وجود فواتير للطباعة.
  static Future<Uint8List> buildNoInvoicesPdf({
    required bool isAr,
    String? titleAr,
    String? titleEn,
    String? bodyAr,
    String? bodyEn,
  }) async {
    final fonts = await _invoiceFonts();
    final base = fonts.base;
    final bold = fonts.bold;
    final logo = await _invoiceLogo();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold));
    final title = isAr ? (titleAr ?? 'لا توجد فواتير') : (titleEn ?? 'No invoices');
    final body = isAr
        ? (bodyAr ?? 'لا توجد فواتير للطباعة في هذا التبويب حالياً.')
        : (bodyEn ?? 'There are no invoices to print in this tab at the moment.');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            brandingPdfHeader(
              base: base,
              bold: bold,
              logo: logo,
              isAr: isAr,
              docTitle: title,
              brandColor: _invoiceBrand,
            ),
            pw.Spacer(),
            pw.Text(
              '﷽',
              style: pw.TextStyle(font: bold, fontSize: 22, color: _invoiceBrand),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              body,
              style: pw.TextStyle(font: base, fontSize: 12),
              textAlign: pw.TextAlign.center,
            ),
            pw.Spacer(),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
