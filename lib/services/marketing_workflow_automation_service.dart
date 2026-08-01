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
      return {'ok': false, 'allow': false, 'reason': 'rpc_error', 'error': '$e'};
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
  }) async {
    bool parseOk(dynamic v) {
      if (v == true) return true;
      if (v == false || v == null) return false;
      final s = v.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 't';
    }

    bool alreadyDone(String msg) {
      final s = msg.toLowerCase();
      return s.contains('invalid_stage_for_relist') ||
          s.contains('no_owner_action_pending');
    }

    try {
      final res = await _sb.rpc(
        'owner_return_request_to_market',
        params: {
          'p_request_id': requestId,
          'p_allow_same_marketer': allowSameMarketer,
        },
      );
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        if (parseOk(m['ok'])) return m;
        return m;
      }
      return {'ok': true, 'request_id': requestId};
    } catch (e) {
      final msg = e.toString();
      final low = msg.toLowerCase();
      final schemaGap = low.contains('round_no') ||
          low.contains('undefined_column') ||
          low.contains('42703') ||
          (low.contains('does not exist') && low.contains('column'));
      if (schemaGap || alreadyDone(msg)) {
        try {
          await _sb.rpc(
            'relist_property_for_marketing',
            params: {
              'p_request_id': requestId,
              'p_allow_previous_marketers_retry': allowSameMarketer,
            },
          );
          return {
            'ok': true,
            'request_id': requestId,
            'fallback': 'relist_property_for_marketing',
          };
        } catch (e2) {
          if (alreadyDone('$e2') || alreadyDone(msg)) {
            return {
              'ok': true,
              'request_id': requestId,
              'idempotent': true,
            };
          }
          return {'ok': false, 'error': '$e2'};
        }
      }
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
