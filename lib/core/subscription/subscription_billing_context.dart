/// سياق الفوترة المحسوب من الخادم عند دخول «الاشتراكات والمدفوعات».
class SubscriptionBillingContext {
  const SubscriptionBillingContext({
    required this.ok,
    this.accountType = '',
    this.billingMode = 'solo',
    this.isTeamMember = false,
    this.isOrgOwner = false,
    this.isOrgEntity = false,
    this.isMarketingRole = false,
    this.orgId,
    this.orgOwnerUserId,
    this.memberRole,
    this.trialUsedBySelf = false,
    this.trialUsedByOrgOwner = false,
    this.canShowTrialTab = false,
    this.showTeamMemberNote = false,
    this.teamMemberDiscountPercent = 50,
    this.seatUnitPriceSar,
    this.planMaxMembers,
    this.hasActivePaidSubscription = false,
    this.hasActiveTrial = false,
    this.hasMarketingFeatureAccess = false,
    this.falStatus = 'ok',
    this.falLicenseExpiresAt,
    this.falComplianceHold = false,
    this.paymentBlockedFal = false,
    this.error,
  });

  final bool ok;
  final String accountType;
  /// `solo` | `team_member` | `org_owner`
  final String billingMode;
  final bool isTeamMember;
  final bool isOrgOwner;
  final bool isOrgEntity;
  final bool isMarketingRole;
  final String? orgId;
  final String? orgOwnerUserId;
  final String? memberRole;
  final bool trialUsedBySelf;
  final bool trialUsedByOrgOwner;
  final bool canShowTrialTab;
  final bool showTeamMemberNote;
  final double teamMemberDiscountPercent;
  final double? seatUnitPriceSar;
  final int? planMaxMembers;
  final bool hasActivePaidSubscription;
  /// تجربة 3 أيام فعّالة الآن (من الخادم).
  final bool hasActiveTrial;
  /// مدفوع أو تجربة — يفتح نشر/تصاريح/تعاقد.
  final bool hasMarketingFeatureAccess;
  /// `ok` | `warn` | `blocked`
  final String falStatus;
  final DateTime? falLicenseExpiresAt;
  final bool falComplianceHold;
  final bool paymentBlockedFal;
  final String? error;

  factory SubscriptionBillingContext.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const SubscriptionBillingContext(ok: false, error: 'bad_response');
    }
    final m = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (m['ok'] != true) {
      return SubscriptionBillingContext(
        ok: false,
        error: m['error']?.toString(),
      );
    }
    final exp = m['fal_license_expires_at'];
    DateTime? expDt;
    if (exp != null) {
      expDt = DateTime.tryParse(exp.toString());
    }
    final disc = m['team_member_discount_percent'];
    return SubscriptionBillingContext(
      ok: true,
      accountType: '${m['account_type'] ?? ''}',
      billingMode: '${m['billing_mode'] ?? 'solo'}',
      isTeamMember: m['is_team_member'] == true,
      isOrgOwner: m['is_org_owner'] == true,
      isOrgEntity: m['is_org_entity'] == true,
      isMarketingRole: m['is_marketing_role'] == true,
      orgId: m['org_id']?.toString(),
      orgOwnerUserId: m['org_owner_user_id']?.toString(),
      memberRole: m['member_role']?.toString(),
      trialUsedBySelf: m['trial_used_by_self'] == true,
      trialUsedByOrgOwner: m['trial_used_by_org_owner'] == true,
      canShowTrialTab: m['can_show_trial_tab'] == true,
      showTeamMemberNote: m['show_team_member_note'] == true,
      teamMemberDiscountPercent: disc is num
          ? disc.toDouble()
          : double.tryParse('$disc') ?? 50,
      seatUnitPriceSar: _num(m['seat_unit_price_sar']),
      planMaxMembers: int.tryParse('${m['plan_max_members'] ?? ''}'),
      hasActivePaidSubscription: m['has_active_paid_subscription'] == true,
      hasActiveTrial: m['has_active_trial'] == true,
      hasMarketingFeatureAccess: m['has_marketing_feature_access'] == true,
      falStatus: '${m['fal_status'] ?? 'ok'}',
      falLicenseExpiresAt: expDt,
      falComplianceHold: m['fal_compliance_hold'] == true,
      paymentBlockedFal: m['payment_blocked_fal'] == true,
    );
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  bool get falBlocksPayment =>
      paymentBlockedFal || falStatus == 'blocked' || falComplianceHold;

  bool get falWarnsSoon => falStatus == 'warn';
}
