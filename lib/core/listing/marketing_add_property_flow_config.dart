import '../workflow/app_role_helper.dart';

/// مسار إضافة إعلان من حساب مسوّق / مكتب / مؤسسة / شركة.
enum MarketingListingPath {
  /// لديه ترخيص إعلان REGA — معالج متعدد الخطوات بعد التحقق.
  licensed,

  /// بدون ترخيص — يُطرح للسوق لإيجاد مسوّق معتمد.
  noLicenseMarket,
}

class MarketingAddPropertyFlowConfig {
  const MarketingAddPropertyFlowConfig({
    required this.path,
    required this.accountType,
    this.initialRegaPayload,
    this.showOwnerPhoneOnMarket = false,
  });

  final MarketingListingPath path;
  final String accountType;
  final Map<String, dynamic>? initialRegaPayload;

  /// عند مسار بدون تصريح: إظهار جوال المعلن من بطاقة السوق قبل اختيار مسوّق.
  final bool showOwnerPhoneOnMarket;

  bool get skipLicenseStep => true;

  bool get licensedSplitSteps => path == MarketingListingPath.licensed;

  bool get simplifiedOwnerForm => path == MarketingListingPath.noLicenseMarket;

  bool get noLicenseMarketConsent => path == MarketingListingPath.noLicenseMarket;

  /// يظهر في الرئيسية فقط عند مسار «نعم» + ترخيص REGA مكتمل.
  bool get publishToHomeFeed => path == MarketingListingPath.licensed;

  /// يُرسل لسوق المسوّقين (listing_requests) دون ظهور في الرئيسية.
  bool get listingRequestOnly => path == MarketingListingPath.noLicenseMarket;

  /// بادئة رقم ترخيص الإعلان (10 أرقام): 71 فرد، 72 منشأة.
  static String adLicensePrefixForAccountType(String? accountType) {
    final k = AppRoleHelper.fromAccountType(accountType);
    switch (k) {
      case AppRoleKind.marketer:
      case AppRoleKind.ownerIndividual:
      case AppRoleKind.publicUser:
        return '71';
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.realEstateCompany:
      case AppRoleKind.realEstateInstitution:
      case AppRoleKind.agency:
        return '72';
    }
  }

  static bool isEntityAccount(String? accountType) {
    return adLicensePrefixForAccountType(accountType) == '72';
  }

  static const List<Map<String, String>> propertyCategoryOptions = [
    {'code': 'residential', 'ar': 'سكني', 'en': 'Residential'},
    {'code': 'commercial', 'ar': 'تجاري', 'en': 'Commercial'},
    {'code': 'administrative', 'ar': 'إداري', 'en': 'Administrative'},
    {'code': 'land', 'ar': 'أرض', 'en': 'Land'},
    {'code': 'farm', 'ar': 'مزارع', 'en': 'Farms'},
    {'code': 'project', 'ar': 'مشاريع', 'en': 'Projects'},
    {'code': 'other', 'ar': 'أخرى', 'en': 'Other'},
  ];
}
