part of 'user_dashboard.dart';

mixin MarketingStateMixin on State<UserDashboard> {
  // =========================================================
  // Base state contract from _UserDashboardState
  // =========================================================
  bool get _isGuest;

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

  bool get _isMarketerRole {
    if (_isGuest) return false;
    if (!_verified) return false;

    final role = _accountType.trim().toLowerCase();

    return role == 'marketer' ||
        role == 'office' ||
        role == 'company' ||
        role == 'institution';
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
    if (!_accountRoleLoaded || !_orgNavResolved) return false;
    return _middleNavDeskLike;
  }

  /// تبويب + في الشريط السفلي (إضافة إعلان/طلب) — يعتمد على الصلاحيات وليس على نوع الحساب وحده.
  bool get _showBottomNavAddSlot {
    if (_isGuest) return false;
    if (!_accountRoleLoaded || !_orgNavResolved) return false;

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

  bool get _isOwner => !_isGuest && !_isMarketerRole;

  // =========================================================
  // Sub tab controllers
  // =========================================================
  TabController? _ownerTabsCtrl;
  TabController? _marketerTabsCtrl;

  // =========================================================
  // Owner listing requests (طلبات التسويق — المصدر قبل النشر)
  // =========================================================
  bool _loadingRequests = false;
  String? _errorRequests;

  List<Map<String, dynamic>> _ownerListingRequests = <Map<String, dynamic>>[];

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

  // =========================================================
  // Convenience counts
  // =========================================================
  int get _marketerInvitesCount => _mkInvites.length;
  int get _marketerOffersCount => _mkOffers.length;
  int get _marketerContractsCount => _mkContracts.length;
  int get _marketerPermitsCount => _mkPermits.length;
  int get _marketerPublishedCount => _mkPublished.length;

  bool get _hasOwnerRequestsData => _ownerListingRequests.isNotEmpty;

  bool get _hasMarketingData =>
      _mkInvites.isNotEmpty ||
      _mkOffers.isNotEmpty ||
      _mkContracts.isNotEmpty ||
      _mkPermits.isNotEmpty ||
      _mkPublished.isNotEmpty;

  bool get _hasMarketingAnyError =>
      (_errorRequests?.trim().isNotEmpty == true) ||
      (_errorMarketing?.trim().isNotEmpty == true);

  // =========================================================
  // Reset helpers
  // =========================================================
  void _resetOwnerRequestBuckets() {
    _ownerListingRequests = <Map<String, dynamic>>[];
    _loadingRequests = false;
    _errorRequests = null;
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

    _ownerTabsCtrl = null;
    _marketerTabsCtrl = null;
  }

  void _clearMarketingStateOnLogout() {
    unawaited(AccountRoleCache.clear());
    _accountType = 'user';
    _verified = false;
    _accountRoleLoaded = false;
    _orgNavResolved = false;
    _orgNavIsOwner = false;
    _orgMembershipPermissions = null;

    _resetOwnerRequestBuckets();
    _resetMarketerBuckets();
    _disposeMarketingTabControllers();
  }
}