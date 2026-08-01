/// Unified marketing-facing roles (maps DB account_type values).
enum AppRoleKind {
  ownerIndividual,
  marketer,
  realEstateOffice,
  realEstateCompany,
  realEstateInstitution,
  publicUser,
  agency,
}

class AppRoleHelper {
  static String normalizeType(String? accountType) {
    return (accountType ?? 'user').trim().toLowerCase();
  }

  static AppRoleKind fromAccountType(String? accountType) {
    final t = normalizeType(accountType);
    switch (t) {
      case 'individual_seller':
      case 'owner_individual':
        return AppRoleKind.ownerIndividual;
      case 'marketer':
        return AppRoleKind.marketer;
      case 'office':
        return AppRoleKind.realEstateOffice;
      case 'company':
        return AppRoleKind.realEstateCompany;
      case 'institution':
        return AppRoleKind.realEstateInstitution;
      case 'agency':
        return AppRoleKind.agency;
      case 'user':
      case '':
      default:
        return AppRoleKind.publicUser;
    }
  }

  /// مالك فرد / مستخدم عام: لا باقات اشتراك — الطلب الفوري 30 ر.س منفصل.
  static bool isOwnerFreeTierAccount(String? accountType) {
    final k = fromAccountType(accountType);
    return k == AppRoleKind.ownerIndividual || k == AppRoleKind.publicUser;
  }

  static bool isMarketingRole(AppRoleKind k) {
    return k == AppRoleKind.marketer ||
        k == AppRoleKind.realEstateOffice ||
        k == AppRoleKind.realEstateCompany ||
        k == AppRoleKind.realEstateInstitution ||
        k == AppRoleKind.agency;
  }

  /// مكتب / شركة / مؤسسة / وكالة — لوحة «إدارتي» الكاملة (فريق + مراقبة).
  static bool isOrgEntity(String? accountType) {
    final k = fromAccountType(accountType);
    return k == AppRoleKind.realEstateOffice ||
        k == AppRoleKind.realEstateCompany ||
        k == AppRoleKind.realEstateInstitution ||
        k == AppRoleKind.agency;
  }

  /// مسوّق حر (ليس صاحب مؤسسة بالضرورة).
  static bool isStandaloneMarketer(String? accountType) {
    return fromAccountType(accountType) == AppRoleKind.marketer;
  }

  /// Marketer desk / إدارتي — includes agency even if not verified (matches app behavior).
  static bool isMarketingAccountType(String? accountType) {
    return isMarketingRole(fromAccountType(accountType));
  }

  /// Strict marketer buckets (requires verified in dashboard mixin).
  static bool isVerifiedMarketerRole(String? accountType, {required bool verified}) {
    if (!verified) return false;
    final k = fromAccountType(accountType);
    return k == AppRoleKind.marketer ||
        k == AppRoleKind.realEstateOffice ||
        k == AppRoleKind.realEstateCompany ||
        k == AppRoleKind.realEstateInstitution ||
        k == AppRoleKind.agency;
  }

  static bool isOwnerIndividual(String? accountType) {
    final k = fromAccountType(accountType);
    return k == AppRoleKind.ownerIndividual;
  }

  /// Middle nav: add listing for owners, desk for marketing orgs — hide for generic public profile.
  static bool showMiddleNavActionSlot({
    required bool isGuest,
    required String? accountType,
  }) {
    if (isGuest) return false;
    final k = fromAccountType(accountType);
    return isOwnerIndividual(accountType) || isMarketingRole(k);
  }

  /// صلاحيات عضو الفريق (JSON من [org_memberships.permissions]): إظهار زر الوسط.
  static bool orgPermissionsAllowMiddleNav(Map<String, dynamic>? permissions) {
    if (permissions == null || permissions.isEmpty) return false;
    if (permissions['all'] == true) return true;
    if (permissions['desk'] == true) return true;
    if (permissions['middle_nav'] == true) return true;
    if (permissions['create_listing'] == true) return true;
    if (permissions['add_properties'] == true) return true;
    if (permissions['add_ads'] == true) return true;
    if (permissions['add_listing_requests'] == true) return true;
    if (permissions['edit_properties'] == true) return true;
    if (permissions['view_market'] == true) return true;
    final listing = permissions['listing'];
    if (listing is Map && listing['create'] == true) return true;
    return false;
  }

  /// فتح لوحة «إدارتي» (مراقبة/فريق) وليس إضافة عقار مباشرة.
  static bool orgPermissionsOpenDeskShell(Map<String, dynamic>? permissions) {
    if (permissions == null || permissions.isEmpty) return false;
    if (permissions['all'] == true) return true;
    if (permissions['desk'] == true) return true;
    if (permissions['middle_nav'] == true) return true;
    if (permissions['manage_team'] == true) return true;
    if (permissions['view_analytics'] == true) return true;
    if (permissions['view_reports'] == true) return true;
    if (permissions['access_chat'] == true) return true;
    return false;
  }
}
