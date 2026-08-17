import 'package:supabase_flutter/supabase_flutter.dart';

import '../workflow/app_role_helper.dart';
import '../../services/org_team_service.dart';
import '../../services/subscription_service.dart';

/// فحص اشتراك التسويق من أي شاشة (لوحة، تفاصيل عقار، …) دون الاعتماد على حالة [UserDashboard].
class MarketingSubscriptionAccess {
  MarketingSubscriptionAccess._();

  static Future<(String accountType, String? organizationId)>
      loadBillingContext(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return ('user', null);
    var at = 'user';
    try {
      final row = await sb
          .from('users_profiles')
          .select('account_type')
          .eq('user_id', uid)
          .maybeSingle();
      at = (row?['account_type'] ?? 'user').toString().trim();
      if (at.isEmpty) at = 'user';
    } catch (_) {}

    String? oid;
    if (AppRoleHelper.isMarketingAccountType(at) &&
        !AppRoleHelper.isStandaloneMarketer(at)) {
      try {
        final org = OrgTeamService(sb);
        final ctx = await org.myOrgContext();
        oid = '${ctx?['org_id'] ?? ''}'.trim();
        if (oid.isEmpty) {
          final o = await org.orgUnitForOwner();
          final s = o?['id']?.toString().trim() ?? '';
          oid = s.isEmpty ? null : s;
        }
      } catch (_) {
        oid = null;
      }
    }
    return (at, oid);
  }

  /// `true` إذا لم يكن المستخدم ضمن أدوار التسويق التجاري، أو لديه اشتراك/فترة سارية.
  static Future<bool> hasActiveMarketingPackage(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return false;
    final (at, oid) = await loadBillingContext(sb);
    if (!AppRoleHelper.isMarketingAccountType(at)) return true;
    return SubscriptionService(sb)
        .hasActiveMarketingSubscriptionAccess(organizationId: oid);
  }
}
