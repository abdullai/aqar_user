import '../workflow/app_role_helper.dart';

/// حدود مقاعد الفريق حسب نوع المنشأة (المالك + الأعضاء ضمن الحد).
class OrgTeamCapacity {
  OrgTeamCapacity._();

  /// مكتب 3، مؤسسة 6، شركة 9 (يشمل المالك ضمن العدد).
  static int baseSeatLimitForAccountType(String? accountType) {
    switch (AppRoleHelper.fromAccountType(accountType)) {
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.agency:
        return 3;
      case AppRoleKind.realEstateInstitution:
        return 6;
      case AppRoleKind.realEstateCompany:
        return 9;
      default:
        return 0;
    }
  }

  /// مسوّق/مكتب/مؤسسة/شركة — إدارة فريق (المسوّق بمقعد إضافي مدفوع).
  static bool canManageTeamMembers(String? accountType) {
    return AppRoleHelper.isMarketingAccountType(accountType);
  }

  static int includedMembersOnPlan(String? accountType, int? planMaxMembers) {
    if (AppRoleHelper.isStandaloneMarketer(accountType)) {
      return planMaxMembers ?? 0;
    }
    return planMaxMembers ?? baseSeatLimitForAccountType(accountType);
  }

  static String baseLimitLabelAr(String? accountType) {
    final n = baseSeatLimitForAccountType(accountType);
    if (n <= 0) return '';
    switch (AppRoleHelper.fromAccountType(accountType)) {
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.agency:
        return 'مكتب عقاري — حتى $n مستخدمين في الفريق';
      case AppRoleKind.realEstateInstitution:
        return 'مؤسسة عقارية — حتى $n مستخدمين في الفريق';
      case AppRoleKind.realEstateCompany:
        return 'شركة عقارية — حتى $n مستخدمين في الفريق';
      default:
        return 'حتى $n مستخدمين';
    }
  }

  static String baseLimitLabelEn(String? accountType) {
    final n = baseSeatLimitForAccountType(accountType);
    if (n <= 0) return '';
    switch (AppRoleHelper.fromAccountType(accountType)) {
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.agency:
        return 'Real estate office — up to $n team seats';
      case AppRoleKind.realEstateInstitution:
        return 'Institution — up to $n team seats';
      case AppRoleKind.realEstateCompany:
        return 'Company — up to $n team seats';
      default:
        return 'Up to $n team seats';
    }
  }
}
