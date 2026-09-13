import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:moyasar/moyasar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../shared/core/app_flags.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../core/notifications/in_app_notification_writer.dart';
import '../core/payment/invoice_pdf_page.dart';
import '../core/payment/payment_security.dart';
import '../core/pdf/pdf_readable_qr.dart';
import '../core/utils/date_helper.dart';
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
  /// إنتاج (`PROD` / release): ممنوعة دائماً. Debug فقط وبلا مفتاح ميسّر.
  static bool get allowMockGateway {
    if (useMoyasarLiveFlow) return false;
    // إنتاج أو بناء إطلاق: ممنوع المحاكاة حتى لو غاب المفتاح.
    if (kIsProd || kReleaseMode) return false;
    final v = (dotenv.env['ALLOW_PAYMENT_MOCK'] ?? '').trim().toLowerCase();
    if (v == '0' || v == 'false' || v == 'no') return false;
    if (v == '1' || v == 'true' || v == 'yes') return kDebugMode;
    return kDebugMode;
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

  /// إنشاء سجل pending عبر الخادم فقط (لا مبلغ من العميل).
  Future<Map<String, dynamic>> createPendingBillingTransaction({
    required double amount,
    String currency = 'SAR',
    String? subscriptionId,
    String? titleAr,
    String? titleEn,
    required String paymentMethod,
    String? cardId,
    String? purpose,
    Map<String, dynamic>? gatewayPendingMeta,
    String? planId,
    String? period,
    bool withAutoPay = false,
    String? upgradeSubscriptionId,
    String? idempotencyKey,
    String? promoCode,
  }) async {
    final uid = _user?.id;
    if (uid == null) {
      return {'ok': false, 'error': 'auth'};
    }
    final purposeTrim =
        (purpose ?? gatewayPendingMeta?['purpose']?.toString() ?? '').trim();
    final pid = (planId ?? '').trim();
    try {
      if (pid.isNotEmpty) {
        final res = await _sb.rpc(
          'create_pending_billing_from_intent',
          params: {
            'p_plan_id': pid,
            'p_period': (period ?? 'monthly').trim(),
            'p_with_auto_pay': withAutoPay,
            'p_upgrade_subscription_id': upgradeSubscriptionId,
            'p_subscription_id': subscriptionId,
            'p_payment_method': paymentMethod,
            'p_card_id': cardId,
            'p_purpose': purposeTrim.isEmpty ? 'subscribe' : purposeTrim,
            'p_title_ar': titleAr,
            'p_title_en': titleEn,
            if ((idempotencyKey ?? '').trim().isNotEmpty)
              'p_idempotency_key': idempotencyKey!.trim(),
            if ((promoCode ?? '').trim().isNotEmpty)
              'p_promo_code': promoCode!.trim(),
          },
        );
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
        return {'ok': false, 'error': 'bad_response'};
      }
      if (purposeTrim == 'save_card_only' || purposeTrim == 'save_card_verify') {
        final res = await _sb.rpc(
          'create_pending_billing_catalog_fee',
          params: {
            'p_fee_key': 'save_card_verify',
            'p_payment_method': paymentMethod,
            'p_card_id': cardId,
          },
        );
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
        return {'ok': false, 'error': 'bad_response'};
      }
      return {'ok': false, 'error': 'client_amount_forbidden'};
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

  /// رسالة واجهة — لا تُعرض رموز داخلية مثل payment_gateway_not_configured.
  static String userFacingError(dynamic code, {required bool isAr}) {
    final c = '$code'.trim();
    if (c.isEmpty || c == 'null') {
      return isAr ? 'تعذّر إتمام العملية.' : 'Could not complete this action.';
    }
    switch (c) {
      case 'payment_gateway_not_configured':
      case 'moyasar_config_error':
        return isAr
            ? 'تعذّر تفعيل الدفع حالياً. حاول مرة أخرى لاحقاً أو تواصل مع الدعم.'
            : 'Payments are unavailable right now. Try again later or contact support.';
      case 'apple_pay_merchant_missing':
        return isAr
            ? 'Apple Pay غير متاح حالياً على هذا الجهاز. استخدم بطاقة أو طريقة أخرى.'
            : 'Apple Pay is not available on this device. Use a card or another method.';
      case 'google_pay_wallet_unavailable':
        return isAr
            ? 'Google Pay غير متاح حالياً على هذا الجهاز. استخدم بطاقة أو طريقة أخرى.'
            : 'Google Pay is not available on this device. Use a card or another method.';
      case 'luhn':
        return isAr
            ? 'رقم البطاقة غير صحيح — تحقق من الأرقام'
            : 'Invalid card number — check the digits';
      case 'expired':
        return isAr ? 'تاريخ الانتهاء منتهٍ' : 'Card has expired';
      case 'cvv':
        return isAr ? 'رمز الأمان غير صحيح' : 'Invalid security code';
      case 'max_cards_reached':
        return isAr
            ? 'الحد الأقصى $maxSavedCards بطاقات.'
            : 'Maximum $maxSavedCards cards reached.';
      case 'moyasar_widget_error':
        return isAr
            ? 'تعذّر فتح نموذج البطاقة. حدّث الصفحة وحاول مجدداً.'
            : 'Could not open the card form. Refresh and try again.';
      case 'moyasar_failed':
      case 'moyasar_cancelled_or_failed':
      case 'moyasar_rejected':
      case 'moyasar_validation_error':
        return isAr
            ? 'رفض البنك أو بوابة الدفع العملية. تحقق من البيانات أو جرّب بطاقة أخرى.'
            : 'The bank or payment gateway declined this charge. Check the details or try another card.';
      case 'cors_or_function_unreachable':
        return isAr
            ? 'تعذّر الاتصال بخادم الدفع. تحقق من الشبكة ثم أعد المحاولة.'
            : 'Could not reach the payment server. Check your network and retry.';
      case 'moyasar_account_inactive':
        return isAr
            ? 'خدمة الدفع غير جاهزة حالياً. حاول لاحقاً أو تواصل مع الدعم.'
            : 'The payment service is not ready yet. Try later or contact support.';
      case 'moyasar_auth_error':
        return isAr
            ? 'تعذّر التحقق من بوابة الدفع. حاول لاحقاً أو تواصل مع الدعم.'
            : 'Could not verify the payment gateway. Try later or contact support.';
      case 'plan_account_mismatch':
        return isAr
            ? 'هذه الباقة غير متاحة لنوع حسابك.'
            : 'This plan is not available for your account type.';
      case 'amount_mismatch':
        return isAr
            ? 'المبلغ غير متطابق، تم إيقاف العملية للمراجعة.'
            : 'The amount did not match. The payment was stopped for review.';
      case 'webhook_timeout':
        return isAr
            ? 'تم استلام الدفع من البوابة، وجارٍ تأكيد السجل. أعد فتح الباقات خلال دقيقة.'
            : 'The gateway accepted the payment. Confirming the ledger — reopen plans in a minute.';
      case 'billing_not_paid':
      case 'billing_not_success':
        return isAr
            ? 'تعذر إكمال الدفع، ولم يتم تفعيل الاشتراك.'
            : 'Payment could not be completed, and the subscription was not activated.';
      case 'partial_refund_unsupported':
        return isAr
            ? 'لا يمكن استرجاع رصيد مستخدم جزئياً.'
            : 'A partially used credit cannot be refunded.';
      case 'unmounted':
        return isAr ? 'أُغلقت الشاشة قبل اكتمال العملية.' : 'The screen closed before finishing.';
      case 'payment_failed':
        return isAr ? 'تعذّر إتمام الدفع.' : 'Payment failed.';
      default:
        if (c.startsWith('moyasar_validation:') || c.startsWith('moyasar_api:')) {
          final detail = c.contains(':') ? c.split(':').skip(1).join(':').trim() : '';
          if (detail.isNotEmpty) {
            return isAr
                ? 'رفض البنك أو البوابة: $detail'
                : 'Bank or gateway declined: $detail';
          }
          return isAr
              ? 'بيانات الدفع مرفوضة من البنك أو البوابة.'
              : 'The bank or payment gateway rejected these details.';
        }
        if (RegExp(r'^[a-z0-9_]+$', caseSensitive: false).hasMatch(c) &&
            !c.contains(' ')) {
          return isAr
              ? 'تعذّر إتمام العملية. حاول مرة أخرى.'
              : 'Could not complete this action. Try again.';
        }
        return c;
    }
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
    await PaymentSecurity.isolateForUid(uid);
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

  /// البطاقات تُحفظ من الـwebhook بعد تحقق Moyasar — لا إدراج من العميل.
  Future<Map<String, dynamic>> persistMoyasarCardFromPaymentResponse(
    PaymentResponse response, {
    bool setDefault = false,
  }) async {
    if (!moyasarPaymentSucceeded(response)) {
      return {'ok': false, 'error': 'not_paid'};
    }
    return const {'ok': true, 'deferred': true};
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
  static String formatLatinDateTime(DateTime dt) {
    final raw = DateHelper.fmtCivilDateTime(dt.toLocal(), isAr: false);
    return raw.replaceAll(RegExp(r'[\u200e\u200f\u2066-\u2069]'), '');
  }

  static PdfColor get _invoiceBrand => kDocumentBrandPdfColor;
  static PdfColor get _invoiceBrandLight => PdfColor.fromInt(0xFFCCFBF1);

  static Future<({pw.Font base, pw.Font bold, List<pw.Font> fallback})>
      _invoiceFonts() async {
    pw.Font? cairo;
    pw.Font? cairoBold;
    pw.Font? arabic;
    try {
      cairo = pw.Font.ttf(await rootBundle.load('fonts/Cairo-Regular.ttf'));
    } catch (_) {}
    try {
      cairoBold = pw.Font.ttf(await rootBundle.load('fonts/Cairo-Bold.ttf'));
    } catch (_) {}
    try {
      arabic =
          pw.Font.ttf(await rootBundle.load('assets/fonts/arabic_pdf_regular.ttf'));
    } catch (_) {}
    pw.Font? noto;
    try {
      noto = pw.Font.ttf(await rootBundle.load('fonts/NotoNaskhArabic_wght.ttf'));
    } catch (_) {}
    final helv = pw.Font.helvetica();
    final helvBold = pw.Font.helveticaBold();
    final fallback = <pw.Font>[
      if (cairo != null) cairo,
      if (cairoBold != null) cairoBold,
      if (arabic != null) arabic,
      if (noto != null) noto,
      helv,
      helvBold,
    ];
    final base = cairo ?? arabic ?? helv;
    final bold = cairoBold ?? cairo ?? arabic ?? helvBold;
    return (base: base, bold: bold, fallback: fallback);
  }

  static pw.ThemeData _invoiceTheme(
    ({pw.Font base, pw.Font bold, List<pw.Font> fallback}) fonts,
  ) {
    return pw.ThemeData.withFont(
      base: fonts.base,
      bold: fonts.bold,
      fontFallback: fonts.fallback,
    );
  }

  static Future<pw.ImageProvider?> _invoiceLogo() => loadBrandingPdfLogo();

  /// فاتورة PDF — ترويسة سعودية، رقم رسمي واحد، بدون UUID.
  static Future<Uint8List> buildInvoicePdf({
    required String title,
    required String txnId,
    required String amountLine,
    required String statusLine,
    String? footer,
    String? planName,
    String? descriptionLabel,
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
    String? calendarLine,
    bool isAr = true,
    String? subtotalLine,
    String? discountLine,
    String? discountLabel,
    String? autoPayDiscountLine,
    String? autoPayDiscountLabel,
    String? promoDiscountLine,
    String? promoDiscountLabel,
    String? vatLine,
    String? feesLine,
    String? refundLine,
    String? vatNote,
    String? paymentReference,
    String? periodStart,
    String? periodEnd,
    String? currencyLabel,
    String? qrPayload,
  }) async {
    final fonts = await _invoiceFonts();
    final logo = await _invoiceLogo();
    final riyalSvg = await loadInvoiceRiyalSvg();
    final doc = pw.Document(theme: _invoiceTheme(fonts));
    _addOfficialInvoicePage(
      doc: doc,
      base: fonts.base,
      bold: fonts.bold,
      fontFallback: fonts.fallback,
      logo: logo,
      title: title,
      txnId: txnId,
      amountLine: amountLine,
      statusLine: statusLine,
      footer: footer,
      planName: planName,
      descriptionLabel: descriptionLabel,
      periodLabel: periodLabel,
      paymentMethod: paymentMethod,
      paidAtFormatted: paidAtFormatted,
      payerName: payerName,
      purposeLabel: purposeLabel,
      userFullName: userFullName,
      userEmail: userEmail,
      userPhone: userPhone,
      invoiceDateFormatted: invoiceDateFormatted,
      calendarLine: calendarLine,
      isAr: isAr,
      subtotalLine: subtotalLine,
      discountLine: discountLine,
      discountLabel: discountLabel,
      autoPayDiscountLine: autoPayDiscountLine,
      autoPayDiscountLabel: autoPayDiscountLabel,
      promoDiscountLine: promoDiscountLine,
      promoDiscountLabel: promoDiscountLabel,
      vatLine: vatLine,
      feesLine: feesLine,
      refundLine: refundLine,
      vatNote: vatNote,
      paymentReference: paymentReference,
      periodStart: periodStart,
      periodEnd: periodEnd,
      currencyLabel: currencyLabel,
      qrPayload: qrPayload,
      riyalSvg: riyalSvg,
    );
    return doc.save();
  }

  /// طباعة مجموعة: كل فاتورة تبدأ في صفحة مستقلة داخل نفس المستند.
  static Future<Uint8List> mergeInvoicePdfs(List<Uint8List> pages) async {
    if (pages.isEmpty) return Uint8List(0);
    if (pages.length == 1) return pages.first;
    return pages.first;
  }

  static Future<Uint8List> buildInvoiceBookPdf({
    required List<Map<String, dynamic>> invoices,
    required bool isAr,
  }) async {
    final fonts = await _invoiceFonts();
    final logo = await _invoiceLogo();
    final riyalSvg = await loadInvoiceRiyalSvg();
    final doc = pw.Document(theme: _invoiceTheme(fonts));
    for (final inv in invoices) {
      _addOfficialInvoicePage(
        doc: doc,
        base: fonts.base,
        bold: fonts.bold,
        fontFallback: fonts.fallback,
        logo: logo,
        title: '${inv['title'] ?? ''}',
        txnId: '${inv['txnId'] ?? ''}',
        amountLine: '${inv['amountLine'] ?? ''}',
        statusLine: '${inv['statusLine'] ?? ''}',
        footer: inv['footer'] as String?,
        planName: inv['planName'] as String?,
        descriptionLabel: inv['descriptionLabel'] as String?,
        periodLabel: inv['periodLabel'] as String?,
        paymentMethod: inv['paymentMethod'] as String?,
        paidAtFormatted: inv['paidAtFormatted'] as String?,
        payerName: inv['payerName'] as String?,
        purposeLabel: inv['purposeLabel'] as String?,
        userFullName: inv['userFullName'] as String?,
        userEmail: inv['userEmail'] as String?,
        userPhone: inv['userPhone'] as String?,
        invoiceDateFormatted: inv['invoiceDateFormatted'] as String?,
        calendarLine: inv['calendarLine'] as String?,
        isAr: isAr,
        subtotalLine: inv['subtotalLine'] as String?,
        discountLine: inv['discountLine'] as String?,
        discountLabel: inv['discountLabel'] as String?,
        autoPayDiscountLine: inv['autoPayDiscountLine'] as String?,
        autoPayDiscountLabel: inv['autoPayDiscountLabel'] as String?,
        promoDiscountLine: inv['promoDiscountLine'] as String?,
        promoDiscountLabel: inv['promoDiscountLabel'] as String?,
        vatLine: inv['vatLine'] as String?,
        feesLine: inv['feesLine'] as String?,
        refundLine: inv['refundLine'] as String?,
        vatNote: inv['vatNote'] as String?,
        paymentReference: inv['paymentReference'] as String?,
        periodStart: inv['periodStart'] as String?,
        periodEnd: inv['periodEnd'] as String?,
        currencyLabel: inv['currencyLabel'] as String?,
        qrPayload: inv['qrPayload'] as String?,
        riyalSvg: riyalSvg,
      );
    }
    return doc.save();
  }

  static void _addOfficialInvoicePage({
    required pw.Document doc,
    required pw.Font base,
    required pw.Font bold,
    required List<pw.Font> fontFallback,
    required pw.ImageProvider? logo,
    required String title,
    required String txnId,
    required String amountLine,
    required String statusLine,
    String? footer,
    String? planName,
    String? descriptionLabel,
    String? periodLabel,
    String? paymentMethod,
    String? paidAtFormatted,
    String? payerName,
    String? purposeLabel,
    String? userFullName,
    String? userEmail,
    String? userPhone,
    String? invoiceDateFormatted,
    String? calendarLine,
    required bool isAr,
    String? subtotalLine,
    String? discountLine,
    String? discountLabel,
    String? autoPayDiscountLine,
    String? autoPayDiscountLabel,
    String? promoDiscountLine,
    String? promoDiscountLabel,
    String? vatLine,
    String? feesLine,
    String? refundLine,
    String? vatNote,
    String? paymentReference,
    String? periodStart,
    String? periodEnd,
    String? currencyLabel,
    String? qrPayload,
    String? riyalSvg,
  }) {
    addOfficialInvoicePage(
      doc: doc,
      base: base,
      bold: bold,
      fontFallback: fontFallback,
      logo: logo,
      title: title,
      txnId: txnId,
      amountLine: amountLine,
      statusLine: statusLine,
      footer: footer,
      planName: planName,
      descriptionLabel: descriptionLabel,
      periodLabel: periodLabel,
      paymentMethod: paymentMethod,
      paidAtFormatted: paidAtFormatted,
      payerName: payerName,
      purposeLabel: purposeLabel,
      userFullName: userFullName,
      userEmail: userEmail,
      userPhone: userPhone,
      invoiceDateFormatted: invoiceDateFormatted,
      calendarLine: calendarLine,
      isAr: isAr,
      subtotalLine: subtotalLine,
      discountLine: discountLine,
      discountLabel: discountLabel,
      autoPayDiscountLine: autoPayDiscountLine,
      autoPayDiscountLabel: autoPayDiscountLabel,
      promoDiscountLine: promoDiscountLine,
      promoDiscountLabel: promoDiscountLabel,
      vatLine: vatLine,
      feesLine: feesLine,
      refundLine: refundLine,
      vatNote: vatNote,
      paymentReference: paymentReference,
      periodStart: periodStart,
      periodEnd: periodEnd,
      currencyLabel: currencyLabel,
      qrPayload: qrPayload,
      riyalSvg: riyalSvg,
    );
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
    final doc = pw.Document(theme: _invoiceTheme(fonts));
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
          brandingPdfHeader(
            base: base,
            bold: bold,
            logo: logo,
            isAr: isAr,
            docTitle: reportTitle,
            brandColor: _invoiceBrand,
            metaLine: '${t('التاريخ', 'Date')}: $issuedAt',
            fontFallback: fonts.fallback,
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxWidth: 500),
              child: pw.TableHelper.fromTextArray(
                headers: [
                  '#',
                  t('رقم الفاتورة', 'Invoice number'),
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
              data: documentQrPlainText(
                isAr: isAr,
                kind: reportTitle,
                paidAt: issuedAt,
                rowCount: rows.length,
              ),
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
    final doc = pw.Document(theme: _invoiceTheme(fonts));
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
              fontFallback: fonts.fallback,
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
