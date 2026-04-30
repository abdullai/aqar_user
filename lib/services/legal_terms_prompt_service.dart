import 'package:supabase_flutter/supabase_flutter.dart';

import 'org_team_service.dart';

/// تذكير «مرة واحدة» للشروط في لوحة التحكم: يُعرض فقط عندما يكون الملف متوافقاً مع الخادم
/// (`terms_version_accepted` = النسخة النشطة). من لم يقبل النسخة الحالية يمرّ عبر [PostAuthShell].
abstract final class LegalTermsPromptService {
  static Future<bool> isEligibleForLegalTermsCoach(SupabaseClient sb) async {
    final svc = OrgTeamService(sb);
    final legal = await svc.activeLegalVersion();
    final active = legal?['version']?.toString().trim() ?? '';
    if (active.isEmpty) return false;
    final g = await svc.myProfileGates();
    final accepted = g?['terms_version_accepted']?.toString().trim() ?? '';
    return accepted.isNotEmpty && accepted == active;
  }
}
