import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// طبقة تدقيق امتثال: تستدعي RPC [compliance_append_audit] (SECURITY DEFINER على الخادم).
///
/// لا تُعتمد وحدها للأدلة القانونية؛ تُكمّل سجلات الخادم وواجهات الربط الحكومي عند التفعيل.
class ComplianceAuditService {
  ComplianceAuditService._();
  static final ComplianceAuditService instance = ComplianceAuditService._();

  /// يسجّل حدثاً للمستخدم الحالي؛ يتجاهل الضيوف والأخطاء الصامتة لتجنّب كسر التدفقات.
  Future<void> log(String eventType, [Map<String, dynamic>? metadata]) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'compliance_append_audit',
        params: {
          'p_event_type': eventType,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[compliance_audit] $eventType skipped: $e\n$st');
      }
    }
  }

  /// سجل أحداث أمنية منفصل (جدول [regc_security_events] عبر RPC).
  Future<void> logSecurity(String action, [Map<String, dynamic>? metadata]) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'append_security_event_v1',
        params: {
          'p_action': action,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[security_event] $action skipped: $e\n$st');
      }
    }
  }
}
