import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ربط قبول الشروط/الكوكيز مع [regc_user_legal_acceptances] و [regc_consent_preferences] على الخادم.
class ComplianceLegalService {
  ComplianceLegalService._();

  /// يُستدعى بعد نجاح [accept_terms_v1] وبنفس إصدار الشروط النشط.
  static Future<void> recordAfterTermsAccepted({
    required String version,
    required String lang,
  }) async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    final l = lang.trim().toLowerCase();
    final langCode = l == 'en' ? 'en' : 'ar';
    final ua = kIsWeb ? 'flutter_web' : 'flutter_mobile';
    try {
      await sb.rpc(
        'record_legal_acceptances_after_terms_v1',
        params: {
          'p_version': version.trim(),
          'p_lang': langCode,
          'p_user_agent': ua,
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[compliance_legal] recordAfterTermsAccepted: $e\n$st');
      }
    }
  }

  static Future<void> upsertConsentPreferences({
    required bool analyticsCookies,
    required bool marketingCookies,
    bool essentialAck = true,
  }) async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    try {
      await sb.rpc(
        'upsert_consent_preferences_v1',
        params: {
          'p_analytics': analyticsCookies,
          'p_marketing': marketingCookies,
          'p_essential_ack': essentialAck,
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[compliance_legal] upsertConsentPreferences: $e\n$st');
      }
    }
  }
}
