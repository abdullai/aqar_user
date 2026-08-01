part of 'user_dashboard.dart';

mixin MarketingStateMixin on State<UserDashboard> {
  // =========================================================
  // Base state contract from _UserDashboardState
  // =========================================================
  bool get _isGuest;

  /// اسم التحية من الكاش — يظهر فوراً قبل اكتمال جلب الملف الشخصي.
  /// يُعرَّف هنا لأن [MarketingStateMixin] يمسحه عند تسجيل الخروج.
  String _greetingNameCache = '';

  // =========================================================
  // Account role state
  // =========================================================
  String _accountType = 'user';
  bool _verified = false;
  /// بعد أول جلب لنوع الحساب + سياق المؤسسة (زر + يعتمد عليها؛ تبويبات الشريط السفلي ثابتة العدد).
  bool _accountRoleLoaded = false;
  bool _orgNavResolved = false;
  bool _orgNavIsOwner = false;
  Map<String, dynamic>? _orgMembershipPermissions;

  /// مسوّق/مكتب/مؤسسة/شركة/وكالة — تبويبات «صفحتي» السبعة (سوق، عروض، تعاقد، تصريح، منشور…).
  /// لا يشترط [verified]؛ التحقق يُطبَّق عند **تقديم عرض** وليس عند عرض التبويبات.
  bool get _usesMarketerMyPageHub {
    if (_isGuest) return false;
    return _isMarketingAccountType;
  }

  bool get _isMarketerRole {
    if (_isGuest) return false;
    if (!_verified) return false;
    // مسوّق، مكتب، مؤسسة، شركة، وكالة — نفس تبويبات «صفحتي» ومسار السوق/العروض.
    return AppRoleHelper.isMarketingRole(
      AppRoleHelper.fromAccountType(_accountType),
    );
  }

  /// جهات تسويق (مكتب/مسوق/…) — للتنقل والسلة: يُخفى دون الاعتماد على verified.
  bool get _isMarketingAccountType {
    if (_isGuest) return false;
    final role = _accountType.trim().toLowerCase();
    return role == 'marketer' ||
        role == 'office' ||
        role == 'company' ||
        role == 'institution' ||
        role == 'agency';
  }

  /// تبويب السلة في الشريط السفلي — لكل المسجّلين (عرض الحالة والوصول).
  bool get _showBottomNavCart => !_isGuest;

  /// حجز «إضافة للسلة» من البطاقات: لا يُفعّل لحسابات التسويق/المؤسسة.
  bool get _cartReservationFeaturesEnabled =>
      !_isGuest && !_isMarketingAccountType;

  /// تبويب «إدارتي» في الشريط السفلي (لوحة المنشأة/المسوّق/المعلن الفردي).
  bool get _showBottomNavMyDeskSlot {
    if (_isGuest) return false;
    // قبل اكتمال الصلاحيات: أظهر التبويب (كان الإخفاء المبكر يجمّد النقرة بعد الدخول).
    if (!_accountRoleLoaded || !_orgNavResolved) return true;
    return _middleNavDeskLike;
  }

  /// تبويب + في الشريط السفلي (إضافة إعلان/طلب) — يعتمد على الصلاحيات وليس على نوع الحساب وحده.
  bool get _showBottomNavAddSlot {
    if (_isGuest) return true;
    if (!_accountRoleLoaded || !_orgNavResolved) return true;

    if (_orgNavIsOwner) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return true;

    if (AppRoleHelper.isOrgEntity(_accountType)) {
      return AppRoleHelper.orgPermissionsAllowMiddleNav(
        _orgMembershipPermissions,
      );
    }

    return AppRoleHelper.orgPermissionsAllowMiddleNav(
      _orgMembershipPermissions,
    );
  }

  /// هل يُستخدم زر «إدارتي» كلوحة (مكتب/مسوّق/معلن فردي) — يظهر الآن كتبويب منفصل عن +.
  bool get _middleNavDeskLike {
    if (_isGuest) return false;
    if (_isMarketingAccountType) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (_orgNavIsOwner) return true;
    return AppRoleHelper.orgPermissionsOpenDeskShell(_orgMembershipPermissions);
  }

  // =========================================================
  // Sub tab controllers
  // =========================================================
  TabController? _ownerTabsCtrl;
  TabController? _marketerTabsCtrl;

  /// تبديل «كمسوّق / كمعن» — طول ثابت 2؛ لا يُعاد إنشاؤه مع دلاء المسوّق/المالك.
  TabController? _marketerPublisherRoleTabsCtrl;

  /// آخر تبويب فرعي تمت زيارته داخل «صفحتي» — لإعادة فتحه عند الرجوع للتبويب
  /// من تبويب رئيسي آخر (الرئيسية/السلة/الدعم…). نُحدّثها عبر Listener على كل من
  /// `_ownerTabsCtrl` و`_marketerTabsCtrl` ونحفظها في `SharedPreferences` أيضاً
  /// لتذكّرها بين الجلسات.
  int _lastOwnerSubTabIndex = 0;
  int _lastMarketerSubTabIndex = 0;
  bool _subTabIndicesPrefsRestored = false;

  static const String _kPrefOwnerSubTabIndex = 'dash_owner_sub_tab_index_v1';
  static const String _kPrefMarketerSubTabIndex =
      'dash_marketer_sub_tab_index_v1';

  // =========================================================
  // Owner listing requests (طلبات التسويق — المصدر قبل النشر)
  // =========================================================
  List<Map<String, dynamic>> _ownerListingRequests = <Map<String, dynamic>>[];

  /// true أثناء جلب صفوف [listing_requests] للمالك من قاعدة البيانات.
  /// بدونها تبويبات «صفحتي» للمعلن الفردي تعرض «لا يوجد» قبل اكتمال التحميل،
  /// فيشاهد المستخدم: فاضي → سكيلتون قصير → فاضي مع أن لديه طلبات فعلية.
  bool _loadingOwnerRequests = false;

  // =========================================================
  // Marketer buckets
  // =========================================================
  bool _loadingMarketing = false;
  String? _errorMarketing;

  List<Map<String, dynamic>> _mkInvites = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _mkOffers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _mkContracts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _mkPermits = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _mkPublished = <Map<String, dynamic>>[];

  /// طلبات أخفاها المسوّق من «السوق العقاري» بعد إلغاء عرضه.
  Set<String> _marketerHiddenMarketRequestIds = {};

  /// بطاقات مفسوخ/ملغى أخفاها المسوّق يدوياً من صفحتي.
  Set<String> _marketerDismissedCancelledIds = {};

  /// طلبات استُنفدت فيها محاولات «إتاحة فرصة» (حد 4) لهذا المستخدم.
  Set<String> _exhaustedOpportunityRequestIds = {};

  /// عدّاد «إتاحة فرصة» لكل طلب (للشارة/التلميح على بطاقة المالك).
  Map<String, int> _opportunityGrantCountsByRequestId = {};

  /// 0 = صفحتي كمسوّق، 1 = صفحتي كمعلن (طلبات طرحها للسوق).
  int _marketerPublisherHubMode = 0;

  bool get _hasMarketingData =>
      _mkInvites.isNotEmpty ||
      _mkOffers.isNotEmpty ||
      _mkContracts.isNotEmpty ||
      _mkPermits.isNotEmpty ||
      _mkPublished.isNotEmpty;

  bool get _hasOwnerRequestsData => _ownerListingRequests.isNotEmpty;

  /// شارة قائمة الاشتراكات (منتهٍ أو يقترب من الانتهاء).
  int _subscriptionMenuBadge = 0;

  bool get _showBottomNavMyAdsSlot {
    if (_isGuest) return true;
    if (!_accountRoleLoaded || !_orgNavResolved) return true;
    if (_orgNavIsOwner) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return true;
    return OrgPermissionManager.can(
          _orgMembershipPermissions,
          OrgPermissionKeys.addAds,
        ) ||
        OrgPermissionManager.can(
          _orgMembershipPermissions,
          OrgPermissionKeys.manageTeam,
        ) ||
        OrgPermissionManager.can(
          _orgMembershipPermissions,
          OrgPermissionKeys.viewAnalytics,
        );
  }

  bool get _showBottomNavMySubmissionsSlot {
    if (_isGuest) return true;
    if (!_accountRoleLoaded || !_orgNavResolved) return true;
    if (_orgNavIsOwner) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return true;
    return OrgPermissionManager.can(
      _orgMembershipPermissions,
      OrgPermissionKeys.addListingRequests,
    );
  }

  bool get _canPlusSheetAddProperty {
    if (_isGuest) return false;
    if (!_accountRoleLoaded || !_orgNavResolved) return true;
    if (_orgNavIsOwner) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return true;
    return OrgPermissionManager.can(
      _orgMembershipPermissions,
      OrgPermissionKeys.addProperties,
    );
  }

  bool get _canPlusSheetAddRequest {
    if (_isGuest) return false;
    if (!_accountRoleLoaded || !_orgNavResolved) return true;
    if (_orgNavIsOwner) return true;
    if (AppRoleHelper.isOwnerIndividual(_accountType)) return true;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return true;
    return OrgPermissionManager.can(
      _orgMembershipPermissions,
      OrgPermissionKeys.addListingRequests,
    );
  }
  void _resetOwnerRequestBuckets() {
    _ownerListingRequests = <Map<String, dynamic>>[];
    _loadingOwnerRequests = false;
  }

  void _resetMarketerBuckets() {
    _mkInvites = <Map<String, dynamic>>[];
    _mkOffers = <Map<String, dynamic>>[];
    _mkContracts = <Map<String, dynamic>>[];
    _mkPermits = <Map<String, dynamic>>[];
    _mkPublished = <Map<String, dynamic>>[];
    _loadingMarketing = false;
    _errorMarketing = null;
  }

  void _disposeMarketingTabControllers() {
    try {
      _ownerTabsCtrl?.dispose();
    } catch (_) {}

    try {
      _marketerTabsCtrl?.dispose();
    } catch (_) {}

    try {
      _marketerPublisherRoleTabsCtrl?.dispose();
    } catch (_) {}

    _ownerTabsCtrl = null;
    _marketerTabsCtrl = null;
    _marketerPublisherRoleTabsCtrl = null;
  }

  void _clearMarketingStateOnLogout() {
    unawaited(AccountRoleCache.clear());
    unawaited(DashboardGreetingCache.clear());
    _greetingNameCache = '';
    _accountType = 'user';
    _verified = false;
    _accountRoleLoaded = false;
    _orgNavResolved = false;
    _orgNavIsOwner = false;
    _orgMembershipPermissions = null;
    _subscriptionMenuBadge = 0;

    _resetOwnerRequestBuckets();
    _resetMarketerBuckets();
    _exhaustedOpportunityRequestIds = {};
    _opportunityGrantCountsByRequestId = {};
    _marketerPublisherHubMode = 0;
    _disposeMarketingTabControllers();
  }
}