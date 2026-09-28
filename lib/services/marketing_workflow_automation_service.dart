import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة أتمتة دورة حياة العرض/التصريح/العقد (v8).
///
/// تُغلِّف الـRPCs الجديدة:
///   - `marketer_send_offer_last_call` / `marketer_can_send_last_call`
///   - `owner_return_request_to_market`
///   - `cron_run_72h_workflow_expirations` (لاستدعاء يدوي عند الحاجة)
class MarketingWorkflowAutomationService {
  MarketingWorkflowAutomationService(this._sb);

  final SupabaseClient _sb;

  /// هل يحقّ للمسوّق الحالي ضغط زر «إشعار آخر» على هذا العرض؟
  ///
  /// يُرجِع: `{ok, allow, reason, next_at?, last_call_count}`
  /// `reason` المحتمل:
  /// - `auth_required` / `offer_not_found` / `not_owner` / `offer_not_active`
  /// - `request_not_found` / `owner_selected_other` (المالك اختار مسوّقاً آخر)
  /// - `cooldown` (مع `next_at`) / `before_first_window` (لم تمر 48h على التقديم)
  Future<Map<String, dynamic>> canSendLastCall(String offerId) async {
    try {
      final res = await _sb.rpc(
        'marketer_can_send_last_call',
        params: {'p_offer_id': offerId},
      );
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {
        'ok': false,
        'allow': false,
        'reason': 'rpc_error',
        'error': '$e'
      };
    }
    return const {'ok': false, 'allow': false};
  }

  /// إرسال «إشعار آخر» للمالك (إعادة تجديد العرض + إشعار صوتي مميّز).
  ///
  /// يُرجِع: `{ok, offer_id, expires_at, last_call_count}` عند النجاح،
  /// أو `{ok: false, error: <code>}` عند الفشل.
  Future<Map<String, dynamic>> sendLastCall(String offerId) async {
    try {
      final res = await _sb.rpc(
        'marketer_send_offer_last_call',
        params: {'p_offer_id': offerId},
      );
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'ok': true, 'offer_id': offerId};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// المالك يُعيد الطلب إلى السوق بعد انقضاء 72 ساعة.
  ///
  /// [allowSameMarketer] = `true` يَسمح للمسوّق السابق بتقديم عرض جديد،
  /// `false` (الافتراضي) يُسجِّل الاستثناء في
  /// `listing_request_marketer_exclusions`.
  Future<Map<String, dynamic>> returnRequestToMarket({
    required String requestId,
    bool allowSameMarketer = false,
    required bool legalAcknowledged,
  }) async {
    try {
      final res = await _sb.rpc(
        'owner_return_request_to_market_with_ack',
        params: {
          'p_request_id': requestId,
          'p_allow_same_marketer': allowSameMarketer,
          'p_legal_acknowledged': legalAcknowledged,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'ok': true, 'request_id': requestId};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  /// (اختياري) تشغيل دورة الانتهاء يدوياً — للاختبار فقط.
  /// في الإنتاج يُستدعى من Edge Function أو pg_cron كل 10 دقائق.
  Future<Map<String, dynamic>> runExpirations() async {
    try {
      final res = await _sb.rpc('cron_run_72h_workflow_expirations');
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }
}
