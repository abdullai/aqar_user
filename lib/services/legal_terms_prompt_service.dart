import 'package:supabase_flutter/supabase_flutter.dart';

import 'org_team_service.dart';

/// إقرار الشروط لمرة واحدة لكل حساب على لوحة التحكم.
/// يُعرض فقط إن لم يُقبل الإصدار النشط عبر [PostAuthShell] (تجنّب التكرار بعد البوابة).
abstract final class LegalTermsPromptService {
  /// مؤهل لعرض حوار الإقرار إن وُجدت جلسة ولم تُقبل النسخة النشطة بعد.
  static Future<bool> isEligibleForLegalTermsCoach(SupabaseClient sb) async {
    try {
      final uid = sb.auth.currentUser?.id.trim() ?? '';
      if (uid.isEmpty) return false;

      final svc = OrgTeamService(sb);
      final legal = await svc.activeLegalVersion();
      final active = legal?['version']?.toString().trim() ?? '';
      // بلا نسخة نشطة على الخادم: حوار محلي اختياري مرة واحدة (يُدار بمفتاح one-time).
      if (active.isEmpty) return true;

      final g = await svc.myProfileGates();
      final accepted = g?['terms_version_accepted']?.toString().trim() ?? '';
      // بعد قبول PostAuthShell (أو أي مسار) للنسخة النشطة: لا تُعاد الشروط على اللوحة.
      if (accepted.isNotEmpty && accepted == active) return false;
      // نسخة قديمة أو بلا قبول: PostAuthShell يعرض الشاشة الإلزامية؛ لا تكرار حوار المدرب.
      return false;
    } catch (_) {
      // عند فشل الشبكة: لا تُظهر حواراً ثانياً فوق بوابة ما بعد الدخول.
      return false;
    }
  }
}
