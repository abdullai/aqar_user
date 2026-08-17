import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة دورة حياة الاشتراك: تشغيل/إيقاف الدفع التلقائي + الإلغاء العادل + الاستبقاء.
///
/// هذه الخدمة تستدعي RPCs:
///   • set_subscription_auto_pay
///   • request_subscription_cancellation
///   • confirm_subscription_cancellation
///   • compute_plan_quote
class SubscriptionLifecycleService {
  final SupabaseClient _sb;
  SubscriptionLifecycleService([SupabaseClient? client])
      : _sb = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Auto-pay
  // ---------------------------------------------------------------------------

  /// تفعيل/إيقاف الدفع التلقائي. يطبّق خصم 5% عند التفعيل، أو يلغيه عند الإيقاف.
  Future<AutoPayResult> setAutoPay({
    required String subscriptionId,
    required bool enabled,
    String? paymentMethodId,
  }) async {
    try {
      final dynamic res = await _sb.rpc(
        'set_subscription_auto_pay',
        params: {
          'p_subscription_id': subscriptionId,
          'p_enabled': enabled,
          if (paymentMethodId != null && paymentMethodId.isNotEmpty)
            'p_payment_method_id': paymentMethodId,
        },
      );
        if (res is Map) {
        final m = Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (m['ok'] != true) {
          return AutoPayResult(
            ok: false,
            enabled: false,
            discountPercent: 0,
            error: '${m['error'] ?? 'failed'}',
          );
        }
        final disc = double.tryParse('${m['discount_percent'] ?? 0}') ?? 0;
        return AutoPayResult(
          ok: true,
          enabled: m['auto_pay_enabled'] == true,
          discountPercent: disc,
        );
      }
      return const AutoPayResult(ok: false, enabled: false, discountPercent: 0);
    } catch (e) {
      return AutoPayResult(
        ok: false,
        enabled: false,
        discountPercent: 0,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Quote (price preview with auto-pay / retention)
  // ---------------------------------------------------------------------------

  Future<PlanQuote?> computeQuote({
    required String planId,
    String period = 'monthly',
    bool withAutoPay = false,
    bool applyRetentionDiscount = false,
  }) async {
    try {
      final dynamic res = await _sb.rpc(
        'compute_plan_quote',
        params: {
          'p_plan_id': planId,
          'p_period': period,
          'p_with_auto_pay': withAutoPay,
          'p_apply_retention_discount': applyRetentionDiscount,
        },
      );
      if (res is Map) {
        return PlanQuote.fromMap(
          Map<String, dynamic>.from(res.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  /// تحميل أسباب الإلغاء النشطة لعرضها في حوار اللطيف.
  Future<List<CancellationReason>> loadReasons() async {
    try {
      final dynamic rows = await _sb
          .from('subscription_cancellation_reasons')
          .select('code,label_ar,label_en,sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      if (rows is List) {
        return rows
            .cast<Map>()
            .map((m) => CancellationReason.fromMap(
                  Map<String, dynamic>.from(
                    m.map((k, v) => MapEntry(k.toString(), v)),
                  ),
                ))
            .toList(growable: false);
      }
    } catch (_) {}
    return CancellationReason.fallbackList();
  }

  /// الخطوة 1: طلب الإلغاء — يُسجّل السبب ويُرجع عرض الاستبقاء إن كان مؤهلاً.
  Future<CancellationOffer> requestCancellation({
    required String subscriptionId,
    required String reasonCode,
    String? reasonNote,
  }) async {
    try {
      final dynamic res = await _sb.rpc(
        'request_subscription_cancellation',
        params: {
          'p_subscription_id': subscriptionId,
          'p_reason_code': reasonCode,
          if (reasonNote != null && reasonNote.trim().isNotEmpty)
            'p_reason_note': reasonNote.trim(),
        },
      );
      if (res is Map) {
        return CancellationOffer.fromMap(
          Map<String, dynamic>.from(res.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
      return CancellationOffer.failure('unexpected_response');
    } catch (e) {
      return CancellationOffer.failure(e.toString());
    }
  }

  /// الخطوة 2: تأكيد القرار النهائي — قبول الاستبقاء أو إكمال الإلغاء.
  Future<CancellationConfirmation> confirmCancellation({
    required String requestId,
    required bool acceptRetention,
  }) async {
    try {
      final dynamic res = await _sb.rpc(
        'confirm_subscription_cancellation',
        params: {
          'p_request_id': requestId,
          'p_accept_retention': acceptRetention,
        },
      );
      if (res is Map) {
        return CancellationConfirmation.fromMap(
          Map<String, dynamic>.from(res.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
      return CancellationConfirmation.failure('unexpected_response');
    } catch (e) {
      return CancellationConfirmation.failure(e.toString());
    }
  }
}

class AutoPayResult {
  final bool ok;
  final bool enabled;
  final double discountPercent;
  final String? error;

  const AutoPayResult({
    required this.ok,
    required this.enabled,
    required this.discountPercent,
    this.error,
  });
}

class PlanQuote {
  final String planId;
  final String period;
  final double base;
  final double subtotal;
  final double autoPayDiscountPercent;
  final double retentionDiscountPercent;
  final double yearlyImplicitDiscountPercent;
  final double totalDiscountPercent;
  final double totalDue;
  final double savings;

  const PlanQuote({
    required this.planId,
    required this.period,
    required this.base,
    required this.subtotal,
    required this.autoPayDiscountPercent,
    required this.retentionDiscountPercent,
    required this.yearlyImplicitDiscountPercent,
    required this.totalDiscountPercent,
    required this.totalDue,
    required this.savings,
  });

  factory PlanQuote.fromMap(Map<String, dynamic> m) {
    double _d(dynamic v) => double.tryParse('$v') ?? 0;
    return PlanQuote(
      planId: '${m['plan_id'] ?? ''}',
      period: '${m['period'] ?? 'monthly'}',
      base: _d(m['base']),
      subtotal: _d(m['subtotal']),
      autoPayDiscountPercent: _d(m['auto_pay_discount_percent']),
      retentionDiscountPercent: _d(m['retention_discount_percent']),
      yearlyImplicitDiscountPercent: _d(m['yearly_implicit_discount_percent']),
      totalDiscountPercent: _d(m['total_discount_percent']),
      totalDue: _d(m['total_due']),
      savings: _d(m['savings']),
    );
  }
}

class CancellationReason {
  final String code;
  final String labelAr;
  final String labelEn;
  final int sortOrder;

  const CancellationReason({
    required this.code,
    required this.labelAr,
    required this.labelEn,
    required this.sortOrder,
  });

  String label({required bool isAr}) => isAr ? labelAr : labelEn;

  factory CancellationReason.fromMap(Map<String, dynamic> m) {
    return CancellationReason(
      code: '${m['code'] ?? ''}',
      labelAr: '${m['label_ar'] ?? ''}',
      labelEn: '${m['label_en'] ?? ''}',
      sortOrder: int.tryParse('${m['sort_order'] ?? 0}') ?? 0,
    );
  }

  /// قائمة احتياطيّة في حال تعذُّر القراءة من القاعدة.
  static List<CancellationReason> fallbackList() {
    return const [
      CancellationReason(
        code: 'price_too_high',
        labelAr: 'الباقة تفوق احتياجي حالياً',
        labelEn: 'Plan exceeds my current need',
        sortOrder: 1,
      ),
      CancellationReason(
        code: 'not_using',
        labelAr: 'لا أستخدم الخدمة بشكل كافٍ',
        labelEn: "I'm not using the service enough",
        sortOrder: 2,
      ),
      CancellationReason(
        code: 'found_alternative',
        labelAr: 'وجدت بديلاً مناسباً',
        labelEn: 'I found a better alternative',
        sortOrder: 3,
      ),
      CancellationReason(
        code: 'technical_issue',
        labelAr: 'واجهت مشاكل تقنية',
        labelEn: 'I experienced technical issues',
        sortOrder: 4,
      ),
      CancellationReason(
        code: 'temporary_pause',
        labelAr: 'أحتاج إيقافاً مؤقتاً',
        labelEn: 'I need a temporary pause',
        sortOrder: 5,
      ),
      CancellationReason(
        code: 'change_business',
        labelAr: 'تغيّر نشاطي/خطتي',
        labelEn: 'My business or plans changed',
        sortOrder: 6,
      ),
      CancellationReason(
        code: 'other',
        labelAr: 'سبب آخر',
        labelEn: 'Other',
        sortOrder: 99,
      ),
    ];
  }
}

class CancellationOffer {
  final bool ok;
  final String? requestId;
  final bool retentionAvailable;
  final double retentionDiscountPercent;
  final String retentionMessageAr;
  final String retentionMessageEn;
  final DateTime? effectiveAt;
  final String noteAr;
  final String noteEn;
  final String? error;

  const CancellationOffer({
    required this.ok,
    this.requestId,
    required this.retentionAvailable,
    required this.retentionDiscountPercent,
    required this.retentionMessageAr,
    required this.retentionMessageEn,
    this.effectiveAt,
    required this.noteAr,
    required this.noteEn,
    this.error,
  });

  factory CancellationOffer.failure(String error) => CancellationOffer(
        ok: false,
        retentionAvailable: false,
        retentionDiscountPercent: 0,
        retentionMessageAr: '',
        retentionMessageEn: '',
        noteAr: '',
        noteEn: '',
        error: error,
      );

  factory CancellationOffer.fromMap(Map<String, dynamic> m) {
    final retOffer = m['retention_offer'];
    final ro = retOffer is Map
        ? Map<String, dynamic>.from(
            retOffer.map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{};
    DateTime? _ts(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse('$v').toLocal();
      } catch (_) {
        return null;
      }
    }

    return CancellationOffer(
      ok: m['ok'] == true,
      requestId: m['request_id']?.toString(),
      retentionAvailable: ro['available'] == true,
      retentionDiscountPercent:
          double.tryParse('${ro['discount_percent'] ?? 0}') ?? 0,
      retentionMessageAr: '${ro['message_ar'] ?? ''}',
      retentionMessageEn: '${ro['message_en'] ?? ''}',
      effectiveAt: _ts(m['effective_at']),
      noteAr: '${m['note_ar'] ?? ''}',
      noteEn: '${m['note_en'] ?? ''}',
    );
  }
}

class CancellationConfirmation {
  final bool ok;
  final bool cancelled;
  final bool retentionApplied;
  final double discountPercent;
  final DateTime? effectiveAt;
  final String messageAr;
  final String messageEn;
  final String? error;

  const CancellationConfirmation({
    required this.ok,
    required this.cancelled,
    required this.retentionApplied,
    required this.discountPercent,
    this.effectiveAt,
    required this.messageAr,
    required this.messageEn,
    this.error,
  });

  factory CancellationConfirmation.failure(String error) =>
      CancellationConfirmation(
        ok: false,
        cancelled: false,
        retentionApplied: false,
        discountPercent: 0,
        messageAr: '',
        messageEn: '',
        error: error,
      );

  factory CancellationConfirmation.fromMap(Map<String, dynamic> m) {
    DateTime? _ts(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse('$v').toLocal();
      } catch (_) {
        return null;
      }
    }

    return CancellationConfirmation(
      ok: m['ok'] == true,
      cancelled: m['cancelled'] == true,
      retentionApplied: m['retention_applied'] == true,
      discountPercent: double.tryParse('${m['discount_percent'] ?? 0}') ?? 0,
      effectiveAt: _ts(m['effective_at']),
      messageAr: '${m['message_ar'] ?? ''}',
      messageEn: '${m['message_en'] ?? ''}',
    );
  }
}
