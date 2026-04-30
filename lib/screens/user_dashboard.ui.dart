// ignore_for_file: unused_element, unused_field

part of 'user_dashboard.dart';

// === ملف: user_dashboard.ui.dart ===
// الهدف: يحتوي تعريف UserDashboard و _UserDashboardState
// (الحقول الأساسية + init/dispose وربط التبويبات).

class UserDashboard extends StatefulWidget {
  final String lang;

  const UserDashboard({
    super.key,
    required this.lang,
  });

  /// تحديد اللغة العربية
  bool get isAr => lang == 'ar';

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard>
    with TickerProviderStateMixin, MarketingStateMixin {
  // =========================
  // ✅ Loading watchdog (UI only)
  // =========================
  DateTime? _homeLoadingSince;
  DateTime? _mineLoadingSince;
  DateTime? _favLoadingSince;
  DateTime? _cartLoadingSince;
  DateTime? _offersLoadingSince;

  static const Duration _loadingWarnAfter = Duration(seconds: 12);

  bool _loadingTooLong(DateTime? since) {
    if (since == null) return false;
    return DateTime.now().difference(since) > _loadingWarnAfter;
  }

  // =========================
  // ✅ GPS (Nearest)
  // =========================
  double? _myLat;
  double? _myLng;

  // =========================
  // ثابتات/مراجع
  // =========================
  /// يتبع لون التمييز من الثيم (يتحدّث مع اختيار اللون في الإعدادات).
  Color _brandPrimary = const Color(0xFF0F766E);
  final _sb = Supabase.instance.client;
  final TextEditingController _inlineSearchCtrl = TextEditingController();
  final ScrollController _filterChipsHScrollCtrl = ScrollController();

  /// يُربَط بقائمة المحتوى أثناء جولة التعريف لتمرير العجلة من فوق الخلفية المعتمة.
  final ScrollController _dashboardOnboardingBackdropScroll =
      ScrollController();

  /// مساحة عرض تحت شريط التطبيق وفوق الشريط السفلي: تكديس الصفحات هنا يبقي التبويبات ظاهرة.
  final GlobalKey<NavigatorState> _dashboardBodyNavKey =
      GlobalKey<NavigatorState>();

  late final NavigatorObserver _dashboardBodyNavObserver =
      _DashboardBodyNavObserver(
    onChange: () {
      if (mounted) setState(() {});
    },
  );

  Offset? _dashboardSwipeStart;
  bool _swipeBackEnabled = true;
  bool _edgeOnlySwipeBack = false;
  bool _keyboardBackEnabled = true;

  // =========================
  // Auth + reload guards
  // =========================
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _workflowRtChannel;
  Timer? _workflowRtDebounce;
  RealtimeChannel? _homeFeedRealtimeChannel;
  Timer? _homeFeedRealtimeDebounce;
  bool _didInitialLoad = false;
  bool _reloading = false;
  String? _lastAuthUserId;

  // =========================
  // Tabs + filters
  // =========================
  int _tabIndex = 0;
  bool _showDashboardOnboarding = false;
  String _searchQuery = '';
  String _cityFilter = 'all';
  bool _didApplyPreferredExploreCity = false;
  PropertyType? _typeFilter;

  /// بيع / إيجار (مجمّع) / مزاد / استثمار — يطابق [PropertyListingDisplay.matchesPurposeFilter].
  String? _purposeFilter;

  /// `null` = الكل، `true` = مفروش فقط، `false` = غير مفروش (يشمل غير المحدد).
  bool? _furnishedFilter;
  double? _priceMinFilter;
  double? _priceMaxFilter;
  double? _areaMinFilter;
  double? _areaMaxFilter;
  HomeFeedKind _homeFeedKind = HomeFeedKind.all;
  String _sortBy = 'latest';
  Timer? _debounce;

  /// True while debounced search text is catching up to the applied query.
  bool _feedFilterBusy = false;

  /// إعلانات/طلبات أخفاها المستخدم محلياً (تظهر عند تفعيل شريط «المخفية»).
  bool _homeShowHiddenOnly = false;
  Set<String> _hiddenPropertyIds = {};
  Set<String> _hiddenMarketRequestIds = {};
  Set<String> _hiddenCompletedDealPropertyIds = {};

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isArabic => widget.isAr;
  String get _lang => widget.lang;
  String get _uid => _sb.auth.currentUser?.id ?? '';
  @override
  bool get _isGuest {
    if (_uid.isEmpty) return true;
    try {
      return context.read<AppSession>().isGuest;
    } catch (_) {
      return false;
    }
  }

  bool get _isNearestMode => _sortBy == 'nearest';

  double? _parseFilterNumber(String raw) {
    final normalized = raw
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9')
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .trim();
    if (normalized.isEmpty) return null;
    final v = double.tryParse(normalized);
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _hasActiveTopFilters {
    return _searchQuery.trim().isNotEmpty ||
        (_cityFilter.trim().isNotEmpty && _cityFilter != 'all') ||
        _typeFilter != null ||
        _purposeFilter != null ||
        _furnishedFilter != null ||
        _priceMinFilter != null ||
        _priceMaxFilter != null ||
        _areaMinFilter != null ||
        _areaMaxFilter != null ||
        _homeFeedKind != HomeFeedKind.all ||
        _sortBy != 'latest' ||
        _homeShowHiddenOnly;
  }

  String? _shortUserFacingApiError(String? raw, {int maxLen = 260}) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    var line = t.split('\n').first.trim();
    if (line.length > maxLen) {
      line = '${line.substring(0, maxLen)}…';
    }
    return line;
  }

  /// نصوص دقيقة لسبب عدم ظهور بطاقات الرئيسية (إعلانات / طلبات سوق).
  List<Widget> _homeFeedEmptyDiagnosticBlocks({
    required bool showListings,
    required bool showRequests,
    required Color textColor,
  }) {
    final isAr = _isArabic;
    final pipeL = _homePropertyFeedPipelineCounts();
    final pipeR = _homeRequestFeedPipelineCounts();

    String listingsLine() {
      if (pipeL.server == 0) {
        return isAr
            ? 'الإعلانات: الخادم لم يُرجع أي صفوف للرئيسية بعد آخر تحديث ناجح (العدد 0). إن كنت تتوقع بيانات، راجع الجدول وسياسات RLS واستعلام الرئيسية في Supabase؛ وإلا فالمشكلة ليست من فلاتر التطبيق.'
            : 'Listings: the server returned 0 home-feed rows after the last successful refresh. If you expected data, check your table data, RLS policies, and the home-feed query in Supabase; otherwise this is not an in-app filter issue.';
      }
      if (pipeL.filtered == 0) {
        return isAr
            ? 'الإعلانات: وصل ${pipeL.server} سجلًا من الخادم، لكن 0 يظهر في بطاقات الرئيسية. تُعرض هناك الإعلانات بعد النشر/العرض العام فقط؛ فلاتر البحث/المدينة/النوع/الغرض/المفروش تنطبق أيضاً، وما قبل النشر يبقى في «صفحتي».'
            : 'Listings: ${pipeL.server} row(s) arrived, but 0 appear on Home cards. Home shows publicly published listings only; search/city/type/purpose/furnished filters still apply, and pre-publish pipeline stays under My Page.';
      }
      if (_homeShowHiddenOnly) {
        if (_hiddenPropertyIds.isEmpty) {
          return isAr
              ? 'الإعلانات: وضع «المخفية فقط» مفعّل وقائمة الإخفاء المحلية فارغة، لذلك لا توجد بطاقات.'
              : 'Listings: “Hidden only” is on, but your local hide list is empty, so there are no cards.';
        }
        if (pipeL.shown == 0) {
          return isAr
              ? 'الإعلانات: يوجد ${pipeL.filtered} إعلان يمرّ بالفلاتر، لكن لا أحد منه ضمن قائمة «إخفاء من الرئيسية» التي طلبت عرضها فقط.'
              : 'Listings: ${pipeL.filtered} item(s) match filters, but none are in your “hide from home” list while “Hidden only” is on.';
        }
        if (pipeL.shown > 0) {
          return isAr
              ? 'الإعلانات: وضع «المخفية فقط» — ${pipeL.shown} عنصرًا من قائمة الإخفاء يمرّ بالفلاتر.'
              : 'Listings: Hidden-only mode — ${pipeL.shown} hide-list item(s) match filters.';
        }
      }
      if (pipeL.shown == 0) {
        return isAr
            ? 'الإعلانات: ${pipeL.filtered} إعلان يطابق الفلاتر لكنه مُستبعد لأنه في قائمة «إخفاء من الرئيسية» المحلية (${_hiddenPropertyIds.length} معرّفًا).'
            : 'Listings: ${pipeL.filtered} item(s) match filters but are hidden locally from home (${_hiddenPropertyIds.length} id(s) on your hide list).';
      }
      return isAr
          ? 'الإعلانات: حالة غير متوقعة (يرجى التحديث).'
          : 'Listings: unexpected empty state (try refresh).';
    }

    String requestsLine() {
      if (pipeR.server == 0) {
        return isAr
            ? 'طلبات السوق: الخادم لم يُرجع أي طلب ضمن حالات الرئيسية بعد آخر تحديث (العدد 0). راجع الجدول والـ RLS والمهاجرات SQL إن لم يُنشأ الجدول بعد.'
            : 'Market requests: the server returned 0 home-feed request rows. Check table data/RLS/SQL migrations if the feature is new.';
      }
      if (pipeR.filtered == 0) {
        return isAr
            ? 'طلبات السوق: وصل ${pipeR.server} طلبًا من الخادم، لكن 0 يمرّ بفلاتر الرئيسية (بحث، مدينة، نوع، غرض) أو بحالة غير مناسبة للعرض العام.'
            : 'Market requests: ${pipeR.server} row(s) arrived, but 0 pass home filters (search, city, type, purpose) or public home status rules.';
      }
      if (_homeShowHiddenOnly) {
        if (_hiddenMarketRequestIds.isEmpty) {
          return isAr
              ? 'طلبات السوق: وضع «المخفية فقط» مفعّل وقائمة إخفاء الطلبات فارغة.'
              : 'Market requests: “Hidden only” is on, but your request hide list is empty.';
        }
        if (pipeR.shown == 0) {
          return isAr
              ? 'طلبات السوق: يوجد ${pipeR.filtered} طلب يمرّ بالفلاتر، لكن لا أحد منه ضمن قائمة إخفاء الطلبات التي طلبت عرضها فقط.'
              : 'Market requests: ${pipeR.filtered} match filters, but none are in your hidden-requests list while “Hidden only” is on.';
        }
        if (pipeR.shown > 0) {
          return isAr
              ? 'طلبات السوق: وضع «المخفية فقط» — ${pipeR.shown} طلبًا من قائمة الإخفاء يمرّ بالفلاتر.'
              : 'Market requests: Hidden-only — ${pipeR.shown} hide-list request(s) match filters.';
        }
      }
      if (pipeR.shown == 0) {
        return isAr
            ? 'طلبات السوق: ${pipeR.filtered} طلب يطابق الفلاتر لكنه مُستبعد لأنه في قائمة إخفاء الطلبات (${_hiddenMarketRequestIds.length} معرّفًا).'
            : 'Market requests: ${pipeR.filtered} match filters but are hidden locally (${_hiddenMarketRequestIds.length} id(s)).';
      }
      return isAr
          ? 'طلبات السوق: حالة غير متوقعة (يرجى التحديث).'
          : 'Market requests: unexpected empty state (try refresh).';
    }

    final blocks = <Widget>[];
    TextStyle style() => TextStyle(
          color: textColor,
          height: 1.42,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        );

    final cf = _cityFilter.trim();
    if (cf.isNotEmpty && cf != 'all') {
      final cityUi = _cityLabel(cf);
      blocks.add(
        Text(
          isAr
              ? 'تنبيه: فلتر المدينة مفعّل («$cityUi»). إن اخترت «مدينة الاستكشاف الافتراضية» من الإعدادات (منطقة/محافظة/مدينة أو خريطة)، تُطبَّق تلقائياً عند فتح الرئيسية وتُبقي فقط ما يطابق المدينة.'
              : 'Note: city filter is on (“$cityUi”). Settings → default explore city (region/governorate/city or map) applies automatically when Home opens and keeps only matching listings.',
          textAlign: TextAlign.center,
          style: style().copyWith(fontSize: 12.7, fontWeight: FontWeight.w800),
        ),
      );
      blocks.add(const SizedBox(height: 12));
    }
    final refLat = _myLat;
    final refLng = _myLng;
    if (_isNearestMode &&
        (refLat == null ||
            refLng == null ||
            !refLat.isFinite ||
            !refLng.isFinite)) {
      blocks.add(
        Text(
          isAr
              ? 'ترتيب «الأقرب» مفعّل دون نقطة مرجعية محفوظة (موقع من الخريطة في إعدادات الاستكشاف أو صلاحيات الموقع). حتى تتوفر الإحداثيات، الترتيب قد لا يعكس المسافة الفعلية.'
              : '“Nearest” sort is on without a saved anchor (pick on map under explore settings, or grant location). Until coordinates exist, ordering may not reflect real distance.',
          textAlign: TextAlign.center,
          style: style().copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      );
      blocks.add(const SizedBox(height: 12));
    }

    if (showListings) {
      blocks.add(
        Text(
          listingsLine(),
          textAlign: TextAlign.center,
          style: style(),
        ),
      );
    }
    if (showRequests) {
      if (blocks.isNotEmpty) {
        blocks.add(const SizedBox(height: 12));
      }
      blocks.add(
        Text(
          requestsLine(),
          textAlign: TextAlign.center,
          style: style(),
        ),
      );
    }
    return blocks;
  }

  ScrollController? _scrollControllerForOnboardingTab(int tabIndex) {
    if (!_showDashboardOnboarding || _tabIndex != tabIndex) return null;
    return _dashboardOnboardingBackdropScroll;
  }

  void _onOnboardingBackdropPointerScroll(double dy) {
    final c = _dashboardOnboardingBackdropScroll;
    if (!c.hasClients) return;
    final p = c.position;
    final next = (p.pixels + dy).clamp(0.0, p.maxScrollExtent).toDouble();
    c.jumpTo(next);
  }

  // =========================
  // Internet Guard wrapper
  // =========================
  Future<T?> _net<T>(
    Future<T> Function() action, {
    bool showDialog = true,
    Duration timeout = const Duration(seconds: 15),
    String tag = 'NET',
  }) async {
    final session = context.read<AppSession>();
    final sw = Stopwatch()..start();
    final effectiveTimeout = kIsWeb ? const Duration(seconds: 45) : timeout;

    try {
      final fut = session.runNetworkGuarded<T>(
        context: context,
        isAr: _isArabic,
        showDialogOnNoInternet: showDialog,
        action: action,
      );

      final res = await fut.timeout(effectiveTimeout);

      if (kDebugMode) {
        print(
          '[DBG][NET][$tag] ok ${sw.elapsedMilliseconds}ms null=${res == null}',
        );
      }
      return res;
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        print('[DBG][NET][$tag] TIMEOUT ${sw.elapsedMilliseconds}ms $e');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][NET][$tag] ERR ${sw.elapsedMilliseconds}ms $e');
      }
      rethrow;
    }
  }

  // =========================
  // Shared helpers
  // =========================
  double _op(num v) {
    final d = v.toDouble();
    if (d <= 1.0) return d.clamp(0.0, 1.0);
    return (d / 255.0).clamp(0.0, 1.0);
  }

  void _ss(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? cs.error : cs.primary,
          content: Text(
            msg,
            style: TextStyle(
              color: isError ? cs.onError : cs.onPrimary,
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // =========================
  // Nearest distance in KM
  // =========================
  double _distanceFor(Property p) {
    final lat = p.latitude;
    final lng = p.longitude;
    final myLat = _myLat;
    final myLng = _myLng;

    if (lat == null || lng == null || myLat == null || myLng == null) {
      return double.infinity;
    }

    return GeoHelper.distanceKm(
      lat1: myLat,
      lon1: myLng,
      lat2: lat,
      lon2: lng,
    );
  }

  // === DASH_HELPERS_BEGIN ===
  double? _toDouble(dynamic v) => NumberHelper.toDouble(v);

  double _toDouble0(dynamic v, [double fallback = 0.0]) =>
      NumberHelper.toDouble0(v, fallback);

  DateTime? _tryParseDt(dynamic v) => DateHelper.tryParse(v);

  String _fmtDateTime(DateTime dt) => DateHelper.fmtDateTime(dt);

  String _timeAgo(DateTime dt, [bool? isArabic]) {
    final ar = isArabic ?? _isArabic;
    return DateHelper.timeAgo(dt, isAr: ar);
  }
  // === DASH_HELPERS_END ===

  // =========================
  // Chat Context
  // =========================
  String? _chatPropertyId;
  String? _chatReservationId;
  String? _chatTitle;
  String _chatMode = 'property';

  void _openChat({
    required String mode,
    String? propertyId,
    String? reservationId,
    String? title,
  }) {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    setState(() {
      _chatMode = mode;
      _chatPropertyId = propertyId;
      _chatReservationId = reservationId;
      _chatTitle = title;
    });
    unawaited(
      ChatNavigation.push(
        context,
        isAr: _isArabic,
        propertyId: propertyId,
        reservationId: reservationId,
        title: title,
      ),
    );
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(
            l10n.loginRequiredDialogTitle,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(l10n.loginRequiredDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.laterLabel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToLogin();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.userSignIn),
            ),
          ],
        );
      },
    );
  }

  void _navigateToLogin() {
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  // =========================
  // Notifications
  // =========================
  final List<Map<String, dynamic>> _notifications = [];
  bool _loadingNotifications = false;

  void _showNotification(String title, String message, {bool isError = false}) {
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    final onBg = isError ? cs.onError : cs.onPrimary;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? cs.error : cs.primary,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: onBg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: TextStyle(color: onBg),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  void _openNotificationsPage() {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    unawaited(
      _pushBody<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.inAppNotifications),
          builder: (_) => CommunicationHubPage(
            lang: widget.lang,
            isAr: _isArabic,
          ),
        ),
      ).then((_) {
        if (mounted) unawaited(_loadNotifications());
      }),
    );
  }

  Future<void> _openFavoritesFromAppBar() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    await _loadFavoritesList(force: true);
    if (!mounted) return;
    final favItems = filterListDashboard(
      _favoritesList,
      excludePropertiesInCart: true,
    );
    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/dashboard/favorites'),
        builder: (routeCtx) {
          final l10n = AppLocalizations.of(routeCtx)!;
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.navFavorites),
            ),
            body: Builder(
              builder: (inner) {
                final host =
                    inner.findAncestorStateOfType<_UserDashboardState>();
                if (host == null) return const SizedBox.shrink();
                return host._buildFavoritesBody(favItems);
              },
            ),
          );
        },
      ),
    );
  }

  int _ownerSubTabFromStatus(String status) {
    return ListingWorkflowMapper.ownerSubTabIndex(status);
  }

  int _marketerSubTabFromStatus(String status) {
    return ListingWorkflowMapper.marketerSubTabIndex(status);
  }

  String _pickNotifValue(
    Map<String, dynamic> notif,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = (notif[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Map<String, dynamic> _notifDataMap(Map<String, dynamic> notif) {
    final raw = notif['data'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Future<void> _markInAppNotifReadAndRefresh(Map<String, dynamic> notif) async {
    final id = (notif['id'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      try {
        await MarketingFlowService(_sb).markNotificationRead(id);
      } catch (_) {}
    }
    if (mounted) {
      unawaited(_loadNotifications());
    }
  }

  Future<void> _onNotificationTap(Map<String, dynamic> notif) async {
    final data = _notifDataMap(notif);

    String from(List<String> keys) {
      for (final k in keys) {
        final dv = (data[k] ?? '').toString().trim();
        if (dv.isNotEmpty) return dv;
      }
      return _pickNotifValue(notif, keys);
    }

    final role = from([
      WorkflowNotificationKeys.role,
      WorkflowNotificationKeys.targetRole,
    ]).toLowerCase();
    final status = from([
      WorkflowNotificationKeys.status,
      WorkflowNotificationKeys.requestStatus,
      WorkflowNotificationKeys.stage,
    ]).toLowerCase();
    final mainTab = from([
      WorkflowNotificationKeys.mainTab,
      WorkflowNotificationKeys.tab,
      WorkflowNotificationKeys.section,
    ]).toLowerCase();
    final deepRoute = from([
      WorkflowNotificationKeys.deepRoute,
      'deep_route',
    ]).toLowerCase();
    final requestId = from([WorkflowNotificationKeys.requestId, 'request_id']);

    if (deepRoute == 'market_request' && requestId.isNotEmpty) {
      setState(() => _tabIndex = mainTab == WorkflowMainSections.cart ? 3 : 2);
      await _markInAppNotifReadAndRefresh(notif);
      await _openMarketRequestDetailById(requestId);
      return;
    }

    if (mainTab == WorkflowMainSections.home || mainTab == 'main') {
      setState(() => _tabIndex = 0);
      await _markInAppNotifReadAndRefresh(notif);
      return;
    }
    if (mainTab == WorkflowMainSections.favorites ||
        mainTab == WorkflowMainSections.mySubmissions) {
      setState(() => _tabIndex = 2);
      await _markInAppNotifReadAndRefresh(notif);
      return;
    }

    if (mainTab == WorkflowMainSections.chat) {
      await _markInAppNotifReadAndRefresh(notif);
      if (!mounted) return;
      await ChatNavigation.push(context, isAr: _isArabic);
      return;
    }
    if (mainTab == WorkflowMainSections.cart) {
      setState(() => _tabIndex = !_isGuest ? 3 : 0);
      await _markInAppNotifReadAndRefresh(notif);
      return;
    }
    if (mainTab == WorkflowMainSections.reservations) {
      setState(() => _tabIndex = 1);
      await _markInAppNotifReadAndRefresh(notif);
      return;
    }

    setState(() => _tabIndex = 1);
    _ensureSubTabControllers();

    if (_isMarketerRole || role == 'marketer') {
      final idx = _marketerSubTabFromStatus(status);
      if (_marketerTabsCtrl != null) {
        _marketerTabsCtrl!.animateTo(idx);
      }
    } else {
      final idx = _ownerSubTabFromStatus(status);
      if (_ownerTabsCtrl != null) {
        _ownerTabsCtrl!.animateTo(idx);
      }
    }

    await _markInAppNotifReadAndRefresh(notif);

    final propertyId = from([
      WorkflowNotificationKeys.previewPropertyId,
      WorkflowNotificationKeys.propertyId,
      WorkflowNotificationKeys.listingId,
      WorkflowNotificationKeys.entityId,
    ]);
    if (propertyId.isNotEmpty) {
      await _openPropertyFromNotification(propertyId);
      return;
    }

    if (requestId.isNotEmpty) {
      await _openPropertyFromNotificationByRequestId(requestId);
    }
  }

  Future<void> _openPropertyFromNotification(String propertyId) async {
    if (propertyId.trim().isEmpty) return;

    Property? p = _propertyCache[propertyId];
    try {
      p ??= _all.firstWhere((e) => e.id == propertyId);
    } catch (_) {}
    try {
      p ??= _mine.firstWhere((e) => e.id == propertyId);
    } catch (_) {}

    if (p == null) {
      await _loadHome(force: true);
      await _loadMineAndOffers(force: true);
      p = _propertyCache[propertyId];
      try {
        p ??= _all.firstWhere((e) => e.id == propertyId);
      } catch (_) {}
      try {
        p ??= _mine.firstWhere((e) => e.id == propertyId);
      } catch (_) {}
    }

    if (!mounted || p == null) return;
    _openDetails(p);
  }

  Future<void> _openPropertyFromNotificationByRequestId(
      String requestId) async {
    if (requestId.trim().isEmpty) return;
    try {
      final row = await _sb
          .from('properties')
          .select('id')
          .eq('request_id', requestId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return;
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) return;
      await _openPropertyFromNotification(id);
    } catch (_) {}
  }

  // =========================
  // Caching
  // =========================
  static String get _propertiesSelect =>
      SupabaseSchemaSelects.propertiesListing;

  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Map<String, Property> _propertyCache = {};
  DateTime? _lastHomeFetch;
  DateTime? _lastMineFetch;
  DateTime? _lastCartFetch;
  DateTime? _lastFavoritesFetch;
  static const Duration _cacheDuration = Duration(minutes: 1);

  // =========================
  // Loading / error states
  // =========================
  bool _loadingHome = false;
  bool _loadingMine = false;
  bool _loadingOffers = false;
  bool _loadingCart = false;
  bool _loadingFavorites = false;

  String? _errorHome;
  String? _errorMine;
  String? _errorOffers;
  String? _errorCart;
  String? _errorFavorites;

  // =========================
  // Data
  // =========================
  List<Property> _all = <Property>[];
  List<MarketPropertyRequestRow> _marketHomeRequests =
      <MarketPropertyRequestRow>[];
  bool _loadingMarketRequests = false;
  String? _errorMarketRequests;

  /// طلبات سوق قدّمتُ عليها عرضاً نشطاً — تُخفى من رئيسيتي وتُعرض في السلة للمتابعة.
  Set<String> _marketRequestIdsWithMyPendingOffer = <String>{};
  List<Map<String, dynamic>> _myPendingMarketOffersForCart =
      <Map<String, dynamic>>[];

  List<Property> _mine = <Property>[];
  List<Property> _favoritesList = <Property>[];
  Map<String, Property> _myPropertyById = {};

  List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _cart = <Map<String, dynamic>>[];
  Map<String, Property> _cartPropertyById = {};
  List<Map<String, dynamic>> _completedCart = <Map<String, dynamic>>[];
  Map<String, Property> _completedCartPropertyById = {};
  int _cartCount = 0;

  final Map<String, Map<String, dynamic>> _activeReservationByPropertyId = {};

  int _offersCount = 0;
  int _unreadNotificationsCount = 0;
  int _chatUnreadTotal = 0;

  final Set<String> _favoriteIds = <String>{};
  bool _favoritesLoaded = false;

  bool _loggingOut = false;

  // =========================
  // Filter helpers
  // =========================
  void _setSearchQuery(String v) {
    final next = v.trim();
    if (_searchQuery == next) return;
    if (!mounted) return;
    setState(() => _searchQuery = next);
  }

  /// Applies the inline search field to [_searchQuery] after a short delay so the
  /// feed is not recomputed on every keystroke. Shows [_feedFilterBusy] while pending.
  void _scheduleInlineSearchApply() {
    _debounce?.cancel();
    final draft = _inlineSearchCtrl.text.trim();
    if (draft == _searchQuery) {
      if (_feedFilterBusy && mounted) {
        setState(() => _feedFilterBusy = false);
      }
      return;
    }
    if (mounted) setState(() => _feedFilterBusy = true);
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final next = _inlineSearchCtrl.text.trim();
      if (next == _searchQuery) {
        setState(() => _feedFilterBusy = false);
        return;
      }
      _setSearchQuery(_inlineSearchCtrl.text);
      if (mounted) setState(() => _feedFilterBusy = false);
    });
  }

  void _flushInlineSearchNow() {
    _debounce?.cancel();
    if (!mounted) return;
    _setSearchQuery(_inlineSearchCtrl.text);
    setState(() => _feedFilterBusy = false);
  }

  void _setCityFilter(String v) {
    final value = v.trim().isEmpty ? 'all' : v.trim();
    if (_cityFilter == value) return;
    if (!mounted) return;
    setState(() => _cityFilter = value);
  }

  void _setSortBy(String v) {
    if (!mounted) return;

    setState(() {
      _sortBy = v;
      if (v != 'nearest') {
        _cityFilter = 'all';
      }
    });

    if (v == 'nearest' && (_myLat == null || _myLng == null)) {
      _showNotification(
        _isArabic ? 'تم تفعيل الأقرب' : 'Nearest enabled',
        _isArabic
            ? 'سيتم ترتيب النتائج بالأقرب عند توفر موقعك، ويمكنك أيضًا التحديد من قائمة المدن.'
            : 'Results will be sorted by nearest when your location is available. You can also narrow it down with the city list.',
      );
    }
  }

  void _setTypeFilter(PropertyType? value) {
    if (!mounted) return;
    setState(() {
      _typeFilter = value;
    });
  }

  void _setPurposeFilter(String? value) {
    if (!mounted) return;
    setState(() => _purposeFilter = value);
  }

  void _setHomeFeedKind(HomeFeedKind value) {
    if (!mounted) return;
    setState(() => _homeFeedKind = value);
  }

  void _clearNearestMode() {
    if (!mounted) return;
    setState(() {
      _sortBy = 'latest';
      _cityFilter = 'all';
    });
  }

  void _clearAllTopFilters() {
    _debounce?.cancel();
    _inlineSearchCtrl.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _cityFilter = 'all';
      _typeFilter = null;
      _purposeFilter = null;
      _furnishedFilter = null;
      _homeFeedKind = HomeFeedKind.all;
      _sortBy = 'latest';
      _homeShowHiddenOnly = false;
      _myLat = null;
      _myLng = null;
      _feedFilterBusy = false;
    });
    FocusScope.of(context).unfocus();
    unawaited(() async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove(AppConfig.prefPreferredExploreCityKey);
        await p.remove(AppConfig.prefPreferredExploreLatKey);
        await p.remove(AppConfig.prefPreferredExploreLngKey);
      } catch (_) {}
      try {
        await UserListingPreferencesService.clearHomeFeedHideSets();
        if (!mounted) return;
        await _reloadHiddenFeedPreferences();
      } catch (_) {}
    }());
  }

  String _typeLabel(PropertyType? t) {
    if (t == null) {
      return _isArabic ? 'كل الأنواع' : 'All types';
    }

    switch (t) {
      case PropertyType.villa:
        return _isArabic ? 'فيلا' : 'Villa';
      case PropertyType.apartment:
        return _isArabic ? 'شقة' : 'Apartment';
      case PropertyType.land:
        return _isArabic ? 'أرض' : 'Land';
    }
  }

  Future<void> _openSearchFiltersSheet() async {
    final cs = Theme.of(context).colorScheme;

    String tempQuery = _searchQuery;
    String tempCity = _cityFilter;
    PropertyType? tempType = _typeFilter;
    String? tempPurpose = _purposeFilter;
    bool? tempFurnished = _furnishedFilter;
    String tempPriceMin = _priceMinFilter?.toStringAsFixed(0) ?? '';
    String tempPriceMax = _priceMaxFilter?.toStringAsFixed(0) ?? '';
    String tempAreaMin = _areaMinFilter?.toStringAsFixed(0) ?? '';
    String tempAreaMax = _areaMaxFilter?.toStringAsFixed(0) ?? '';
    String tempSort = _sortBy;
    var tempHomeKind = _homeFeedKind;
    var tempHidden = _homeShowHiddenOnly;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget actionChip({
              required bool selected,
              required String label,
              required IconData icon,
              required VoidCallback onTap,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _brandPrimary.withOpacity(0.12)
                        : cs.surfaceContainerHighest.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? _brandPrimary.withOpacity(0.45)
                          : cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: selected ? _brandPrimary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: selected ? _brandPrimary : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: cs.outlineVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _brandPrimary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.tune, color: _brandPrimary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isArabic ? 'بحث متقدم' : 'Advanced Search',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempQuery = '';
                              tempCity = 'all';
                              tempType = null;
                              tempPurpose = null;
                              tempFurnished = null;
                              tempPriceMin = '';
                              tempPriceMax = '';
                              tempAreaMin = '';
                              tempAreaMax = '';
                              tempSort = 'latest';
                              tempHomeKind = HomeFeedKind.all;
                              tempHidden = false;
                            });
                          },
                          child: Text(_isArabic ? 'إعادة ضبط' : 'Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'محتوى الرئيسية' : 'Home feed',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        actionChip(
                          selected: tempHomeKind == HomeFeedKind.all,
                          label: _isArabic ? 'الكل' : 'All',
                          icon: Icons.grid_view_rounded,
                          onTap: () => setModalState(
                            () => tempHomeKind = HomeFeedKind.all,
                          ),
                        ),
                        actionChip(
                          selected: tempHomeKind == HomeFeedKind.listings,
                          label: _isArabic ? 'إعلانات' : 'Listings',
                          icon: Icons.home_work_outlined,
                          onTap: () => setModalState(
                            () => tempHomeKind = HomeFeedKind.listings,
                          ),
                        ),
                        actionChip(
                          selected: tempHomeKind == HomeFeedKind.requests,
                          label: _isArabic ? 'طلبات السوق' : 'Requests',
                          icon: Icons.request_quote_outlined,
                          onTap: () => setModalState(
                            () => tempHomeKind = HomeFeedKind.requests,
                          ),
                        ),
                        if (!_isGuest)
                          actionChip(
                            selected: tempHidden,
                            label: _isArabic ? 'المخفية' : 'Hidden',
                            icon: Icons.visibility_off_outlined,
                            onTap: () => setModalState(
                              () => tempHidden = !tempHidden,
                            ),
                          ),
                      ],
                    ),
                    if (!_isGuest) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _isArabic
                              ? 'عرض العناصر المخفية محلياً'
                              : 'Show locally hidden items',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _isArabic
                              ? 'إعلانات وطلبات أخفيتها من الرئيسية'
                              : 'Listings and requests you hid from Home',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: tempHidden,
                        onChanged: (v) => setModalState(() => tempHidden = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: tempQuery,
                      onChanged: (v) => tempQuery = v,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _isArabic
                            ? 'ابحث برقم الإعلان/الطلب، السعر، المساحة، الاسم، المسوق، المكتب...'
                            : 'Search by ID, price, area, name, marketer, office...',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withOpacity(0.22),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.35),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.35),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: _brandPrimary.withOpacity(0.70),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'السعر' : 'Price',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: tempPriceMin,
                            keyboardType: TextInputType.number,
                            inputFormatters: latinDecimalNumberFormatters(),
                            onChanged: (v) => tempPriceMin = v,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.payments_outlined),
                              hintText: _isArabic ? 'من' : 'From',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: tempPriceMax,
                            keyboardType: TextInputType.number,
                            inputFormatters: latinDecimalNumberFormatters(),
                            onChanged: (v) => tempPriceMax = v,
                            decoration: InputDecoration(
                              prefixIcon:
                                  const Icon(Icons.price_check_outlined),
                              hintText: _isArabic ? 'إلى' : 'To',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'المساحة' : 'Area',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: tempAreaMin,
                            keyboardType: TextInputType.number,
                            inputFormatters: latinDecimalNumberFormatters(),
                            onChanged: (v) => tempAreaMin = v,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.square_foot),
                              hintText: _isArabic ? 'من م²' : 'From m2',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: tempAreaMax,
                            keyboardType: TextInputType.number,
                            inputFormatters: latinDecimalNumberFormatters(),
                            onChanged: (v) => tempAreaMax = v,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.straighten),
                              hintText: _isArabic ? 'إلى م²' : 'To m2',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'نوع العقار' : 'Property type',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        actionChip(
                          selected: tempType == null,
                          label: _isArabic ? 'الكل' : 'All',
                          icon: Icons.apps_outlined,
                          onTap: () => setModalState(() => tempType = null),
                        ),
                        actionChip(
                          selected: tempType == PropertyType.villa,
                          label: _isArabic ? 'فيلا' : 'Villa',
                          icon: Icons.home_work_outlined,
                          onTap: () => setModalState(
                            () => tempType = PropertyType.villa,
                          ),
                        ),
                        actionChip(
                          selected: tempType == PropertyType.apartment,
                          label: _isArabic ? 'شقة' : 'Apartment',
                          icon: Icons.apartment_outlined,
                          onTap: () => setModalState(
                            () => tempType = PropertyType.apartment,
                          ),
                        ),
                        actionChip(
                          selected: tempType == PropertyType.land,
                          label: _isArabic ? 'أرض' : 'Land',
                          icon: Icons.landscape_outlined,
                          onTap: () => setModalState(
                            () => tempType = PropertyType.land,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'غرض الإعلان' : 'Listing purpose',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        actionChip(
                          selected: tempPurpose == null,
                          label: _isArabic ? 'الكل' : 'All',
                          icon: Icons.layers_outlined,
                          onTap: () => setModalState(() => tempPurpose = null),
                        ),
                        actionChip(
                          selected: tempPurpose == 'sale',
                          label: _isArabic ? 'بيع' : 'Sale',
                          icon: Icons.sell_outlined,
                          onTap: () =>
                              setModalState(() => tempPurpose = 'sale'),
                        ),
                        actionChip(
                          selected: tempPurpose == 'rent',
                          label: _isArabic ? 'إيجار' : 'Rent',
                          icon: Icons.calendar_month_outlined,
                          onTap: () =>
                              setModalState(() => tempPurpose = 'rent'),
                        ),
                        actionChip(
                          selected: tempPurpose == 'auction',
                          label: _isArabic ? 'مزاد' : 'Auction',
                          icon: Icons.gavel_outlined,
                          onTap: () =>
                              setModalState(() => tempPurpose = 'auction'),
                        ),
                        actionChip(
                          selected: tempPurpose == 'investment',
                          label: _isArabic ? 'استثمار' : 'Investment',
                          icon: Icons.trending_up_outlined,
                          onTap: () =>
                              setModalState(() => tempPurpose = 'investment'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'التأثيث' : 'Furnishing',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        actionChip(
                          selected: tempFurnished == null,
                          label: _isArabic ? 'الكل' : 'All',
                          icon: Icons.layers_outlined,
                          onTap: () =>
                              setModalState(() => tempFurnished = null),
                        ),
                        actionChip(
                          selected: tempFurnished == true,
                          label: _isArabic ? 'مفروش' : 'Furnished',
                          icon: Icons.chair_outlined,
                          onTap: () =>
                              setModalState(() => tempFurnished = true),
                        ),
                        actionChip(
                          selected: tempFurnished == false,
                          label: _isArabic ? 'غير مفروش' : 'Unfurnished',
                          icon: Icons.event_seat_outlined,
                          onTap: () =>
                              setModalState(() => tempFurnished = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isArabic ? 'الترتيب' : 'Sort',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _SortMenu(
                      isAr: _isArabic,
                      value: tempSort,
                      onChanged: (v) {
                        setModalState(() => tempSort = v);
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close),
                            label: Text(_isArabic ? 'إغلاق' : 'Close'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _brandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              if (!mounted) return;
                              _debounce?.cancel();
                              setState(() {
                                _feedFilterBusy = false;
                                _searchQuery = tempQuery.trim();
                                _cityFilter =
                                    tempCity.trim().isEmpty ? 'all' : tempCity;
                                _typeFilter = tempType;
                                _purposeFilter = tempPurpose;
                                _furnishedFilter = tempFurnished;
                                _priceMinFilter = _parseFilterNumber(
                                  tempPriceMin,
                                );
                                _priceMaxFilter = _parseFilterNumber(
                                  tempPriceMax,
                                );
                                _areaMinFilter = _parseFilterNumber(
                                  tempAreaMin,
                                );
                                _areaMaxFilter = _parseFilterNumber(
                                  tempAreaMax,
                                );
                                _sortBy = tempSort;
                                _homeFeedKind = tempHomeKind;
                                _homeShowHiddenOnly = tempHidden;
                                _inlineSearchCtrl.text = _searchQuery;
                              });

                              if (_sortBy == 'nearest' &&
                                  (_myLat == null || _myLng == null)) {
                                _showNotification(
                                  _isArabic
                                      ? 'تم تفعيل الأقرب'
                                      : 'Nearest enabled',
                                  _isArabic
                                      ? 'سيتم استخدام الترتيب الأقرب عند توفر موقعك.'
                                      : 'Nearest sorting will be used when your location is available.',
                                );
                              }

                              FocusScope.of(context).unfocus();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(_isArabic ? 'تطبيق' : 'Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFilterChips() {
    final cs = Theme.of(context).colorScheme;
    final List<Widget> chips = [];

    Widget item({
      required String text,
      required IconData icon,
      required VoidCallback onRemove,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _brandPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Icon(
                Icons.close,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchQuery.trim().isNotEmpty) {
      chips.add(
        item(
          text: _isArabic
              ? 'بحث: ${_searchQuery.trim()}'
              : 'Search: ${_searchQuery.trim()}',
          icon: Icons.search,
          onRemove: () {
            _inlineSearchCtrl.clear();
            _setSearchQuery('');
          },
        ),
      );
    }

    if (_typeFilter != null) {
      chips.add(
        item(
          text: _typeLabel(_typeFilter),
          icon: Icons.home_work_outlined,
          onRemove: () => _setTypeFilter(null),
        ),
      );
    }

    if (_purposeFilter != null) {
      final label = switch (_purposeFilter!) {
        'sale' => _isArabic ? 'بيع' : 'Sale',
        'rent' => _isArabic ? 'إيجار' : 'Rent',
        'auction' => _isArabic ? 'مزاد' : 'Auction',
        'investment' => _isArabic ? 'استثمار' : 'Investment',
        _ => _purposeFilter!,
      };
      chips.add(
        item(
          text: label,
          icon: Icons.filter_list_alt,
          onRemove: () => _setPurposeFilter(null),
        ),
      );
    }

    if (_furnishedFilter != null) {
      chips.add(
        item(
          text: _furnishedFilter!
              ? (_isArabic ? 'مفروش' : 'Furnished')
              : (_isArabic ? 'غير مفروش' : 'Unfurnished'),
          icon: Icons.chair_outlined,
          onRemove: () {
            if (!mounted) return;
            setState(() => _furnishedFilter = null);
          },
        ),
      );
    }

    if (_sortBy != 'latest') {
      chips.add(
        item(
          text: _isArabic ? 'ترتيب مخصص' : 'Custom sort',
          icon: Icons.sort,
          onRemove: () => _setSortBy('latest'),
        ),
      );
    }

    if (_tabIndex == 0 && !_isGuest && _homeShowHiddenOnly) {
      chips.add(
        item(
          text: _isArabic ? 'عرض المخفية' : 'Hidden only',
          icon: Icons.visibility_off_outlined,
          onRemove: () => setState(() => _homeShowHiddenOnly = false),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Scrollbar(
        controller: _filterChipsHScrollCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 6,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          controller: _filterChipsHScrollCtrl,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i != 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _maybeApplyPreferredExploreCity() async {
    if (_didApplyPreferredExploreCity) return;
    _didApplyPreferredExploreCity = true;
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(AppConfig.prefPreferredExploreCityKey)?.trim();
      final lat = p.getDouble(AppConfig.prefPreferredExploreLatKey);
      final lng = p.getDouble(AppConfig.prefPreferredExploreLngKey);
      if (!mounted) return;
      final hasCity = v != null && v.isNotEmpty && v != 'all';
      final hasAnchor = lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() > 1e-6 &&
          lng.abs() > 1e-6;
      if (!hasCity && !hasAnchor) return;
      setState(() {
        if (hasCity) {
          _cityFilter = v;
        }
        // نقطة الخريطة/المدينة من الإعدادات — تُستعمل لترتيب «الأقرب» فقط مع المدينة المختارة.
        if (hasCity && hasAnchor) {
          _myLat = lat;
          _myLng = lng;
        }
      });
    } catch (_) {}
  }

  // =========================
  // Initial load
  // =========================
  Future<void> _runInitialLoad() async {
    if (!mounted) return;
    if (_didInitialLoad) return;

    _didInitialLoad = true;
    _lastAuthUserId = _sb.auth.currentUser?.id;
    _inlineSearchCtrl.text = _searchQuery;

    _ss(() {
      _errorHome = null;
      _errorMine = null;
      _errorFavorites = null;
      _errorCart = null;
      _errorOffers = null;

      _homeLoadingSince = DateTime.now();
      _mineLoadingSince = DateTime.now();
      _favLoadingSince = DateTime.now();
      _cartLoadingSince = DateTime.now();
      _offersLoadingSince = DateTime.now();

      if (_isGuest) {
        _favoritesLoaded = true;
        _mine = <Property>[];
        _favoritesList = <Property>[];
        _cart = <Map<String, dynamic>>[];
        _offers = <Map<String, dynamic>>[];
        _offersCount = 0;
        _myPropertyById = {};
        _resetOwnerRequestBuckets();
        _resetMarketerBuckets();
      }
    });

    try {
      await Future.wait([
        _loadCities(),
        _maybeApplyPreferredExploreCity(),
        _loadHome(force: true),
        _loadMarketHomeRequests(force: true),
      ]);
      if (mounted) {
        setState(() {});
      }

      if (!_isGuest) {
        await _loadAccountRole();
        _ensureSubTabControllers();

        await Future.wait([
          _loadNotifications(),
          _loadCart(force: true),
          _loadMineAndOffers(force: true),
        ]);

        await _loadFavoritesForUid();
        await Future.wait([
          _loadFavoritesList(force: true),
          if (_isMarketerRole)
            _loadMarketerBuckets(force: true)
          else
            _loadOwnerRequestsBuckets(force: true),
        ]);
        if (mounted) {
          _ensureWorkflowRealtimeChannel();
        }
      }
      if (mounted) {
        _ensureHomeFeedRealtimeChannel();
      }
    } catch (e) {
      debugPrint('Initial load error: $e');
    } finally {
      if (mounted) unawaited(_reloadHiddenFeedPreferences());
    }
  }

  void _scheduleHomeFeedRealtimeRefresh() {
    _homeFeedRealtimeDebounce?.cancel();
    _homeFeedRealtimeDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      unawaited(Future.wait([
        _loadMarketHomeRequests(force: true),
        _loadHome(force: true),
        if (!_isGuest) _loadMyMarketRequestOfferTracking(),
      ]));
    });
  }

  void _ensureHomeFeedRealtimeChannel() {
    try {
      _homeFeedRealtimeChannel?.unsubscribe();
      _homeFeedRealtimeChannel = null;
      final ch = _sb
          .channel('home_feed_listings_${_sb.auth.currentUser?.id ?? "anon"}');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'market_property_requests',
        callback: (_) => _scheduleHomeFeedRealtimeRefresh(),
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'properties',
        callback: (_) => _scheduleHomeFeedRealtimeRefresh(),
      );
      if (!_isGuest) {
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'market_request_offers',
          callback: (_) => _scheduleHomeFeedRealtimeRefresh(),
        );
      }
      ch.subscribe();
      _homeFeedRealtimeChannel = ch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('home feed realtime bind failed: $e');
      }
    }
  }

  void _disposeHomeFeedRealtimeChannel() {
    _homeFeedRealtimeDebounce?.cancel();
    _homeFeedRealtimeDebounce = null;
    try {
      _homeFeedRealtimeChannel?.unsubscribe();
    } catch (_) {}
    _homeFeedRealtimeChannel = null;
  }

  /// تسلسل أول دخول مسجّل: موافقة/تذكير الخصوصية → جولة التبويبات → ثم لون التمييز بعد إنهاء الجولة.
  Future<void> _runLoggedInFirstRunPrompts() async {
    if (!mounted || _isGuest) return;
    try {
      await OneTimePromptCoordinator.migrateLegacyOnboardingKeysIfNeeded();
      await _maybeShowLegalTermsCoach();
      if (!mounted || _isGuest) return;
      await _maybeShowDashboardOnboarding();
    } catch (_) {}
  }

  /// جولة تعريفية لمرة واحدة (ليس للضيف) — ويب/تطبيق، خطوات حسب الصلاحيات؛
  /// التالي / تخطي / إنهاء من داخل البطاقة فقط (لا إغلاق بالضغط خارجها).
  Future<void> _maybeShowDashboardOnboarding() async {
    if (!mounted || _isGuest) return;
    try {
      await OneTimePromptCoordinator.migrateLegacyOnboardingKeysIfNeeded();
      final pending = await OneTimePromptCoordinator.nextDefaultPending();
      if (pending != 'dashboard_onboarding_v3') return;
      if (!mounted) return;
      setState(() {
        _showDashboardOnboarding = true;
        _tabIndex = 0;
      });
    } catch (_) {}
  }

  Future<void> _completeDashboardOnboarding() async {
    await OneTimePromptCoordinator.markSeen('dashboard_onboarding_v3');
    if (!mounted) return;
    setState(() {
      _showDashboardOnboarding = false;
      _tabIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowAccentColorPrompt());
    });
  }

  Future<void> _maybeShowAccentColorPrompt() async {
    if (!mounted || _isGuest) return;
    try {
      final pending = await OneTimePromptCoordinator.nextDefaultPending();
      if (pending == 'accent_color_prompt_v1') {
        if (!mounted) return;
        await showAccentColorFirstRunDialog(context);
        if (mounted) {
          await OneTimePromptCoordinator.markSeen('accent_color_prompt_v1');
        }
      }
    } catch (_) {}
  }

  /// تذكير لمرة واحدة: مراجعة الشروط من الإعدادات.
  /// يُعرض فقط إذا كان الملف متوافقاً مع الخادم (قبول نفس [legal_documents_versions.version]).
  Future<void> _maybeShowLegalTermsCoach() async {
    if (!mounted || _isGuest) return;
    try {
      final pending = await OneTimePromptCoordinator.nextDefaultPending();
      if (pending != 'legal_terms_policy_coach_v1') return;
      final eligible =
          await LegalTermsPromptService.isEligibleForLegalTermsCoach(
        _sb,
      );
      if (!eligible) {
        await OneTimePromptCoordinator.markSeen('legal_terms_policy_coach_v1');
        return;
      }
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(t.legalTermsCoachTitle),
            content: Text(t.legalTermsCoachBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t.legalTermsCoachOk),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      await OneTimePromptCoordinator.markSeen('legal_terms_policy_coach_v1');
    } catch (_) {}
  }

  List<DashboardOnboardingStepData> _buildDashboardOnboardingSteps(
    AppLocalizations l10n,
  ) {
    final isWeb = kIsWeb;
    final steps = <DashboardOnboardingStepData>[];

    steps.add(
      DashboardOnboardingStepData(
        title: isWeb
            ? l10n.onboardingWelcomeTitleWeb
            : l10n.onboardingWelcomeTitleApp,
        body: isWeb
            ? l10n.onboardingWelcomeBodyWeb
            : l10n.onboardingWelcomeBodyApp,
        tabIndex: 0,
      ),
    );

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingHomeTitle,
        body: l10n.onboardingHomeBody,
        tabIndex: 0,
      ),
    );

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingMyAdsTitle,
        body: _isMarketingAccountType
            ? l10n.onboardingMyAdsBodyMarketing
            : l10n.onboardingMyAdsBodyOwner,
        tabIndex: 1,
      ),
    );

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingMySubmissionsTitle,
        body: l10n.onboardingMySubmissionsBody,
        tabIndex: 2,
      ),
    );

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.marketInsightsTitle,
        body: l10n.onboardingMarketInsightsBody,
        tabIndex: null,
      ),
    );

    if (_showBottomNavMyDeskSlot) {
      final deskBody = _isMarketingAccountType
          ? l10n.onboardingMyDeskBodyMarketing
          : AppRoleHelper.isOwnerIndividual(_accountType)
              ? l10n.onboardingMyDeskBodyOwnerIndividual
              : l10n.onboardingMyDeskBodyOrgMember;
      steps.add(
        DashboardOnboardingStepData(
          title: l10n.onboardingMyDeskTitle,
          body: deskBody,
          tabIndex: 0,
        ),
      );
    }

    if (_cartReservationFeaturesEnabled) {
      steps.add(
        DashboardOnboardingStepData(
          title: l10n.onboardingCartTitle,
          body: l10n.onboardingCartBody,
          tabIndex: 3,
        ),
      );
    }

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingSupportTitle,
        body: l10n.onboardingSupportBody,
        tabIndex: 4,
      ),
    );

    return steps;
  }

  // =========================
  // Auth reload
  // =========================
  void _handleAuthReloadIfNeeded() {
    final uid = _sb.auth.currentUser?.id;
    if (_lastAuthUserId == uid) return;
    _lastAuthUserId = uid;

    if (!mounted) return;
    if (!_didInitialLoad) return;
    if (_reloading) return;
    _reloading = true;

    if (uid == null || uid.isEmpty) {
      _disposeWorkflowRealtimeChannel();
    }

    _ss(() {
      _errorHome = null;
      _errorMine = null;
      _errorFavorites = null;
      _errorCart = null;
      _errorOffers = null;

      _homeLoadingSince = DateTime.now();
      _mineLoadingSince = DateTime.now();
      _favLoadingSince = DateTime.now();
      _cartLoadingSince = DateTime.now();
      _offersLoadingSince = DateTime.now();

      if (uid == null || uid.isEmpty) {
        _favoritesLoaded = true;
        _favoriteIds.clear();
        _favoritesList = <Property>[];
        _cart = <Map<String, dynamic>>[];
        _cartPropertyById = {};
        _cartCount = 0;
        _offers = <Map<String, dynamic>>[];
        _offersCount = 0;
        _marketRequestIdsWithMyPendingOffer = <String>{};
        _myPendingMarketOffersForCart = const [];
        _clearMarketingStateOnLogout();
      }
    });

    () async {
      try {
        await _loadCities();
        if (mounted) {
          setState(() {});
        }

        await Future.wait([
          _loadHome(force: true),
          _loadMarketHomeRequests(force: true),
        ]);

        if (uid != null && uid.isNotEmpty) {
          await _loadAccountRole();
          _ensureSubTabControllers();

          await _loadNotifications();
          await _loadFavoritesForUid();
          await Future.wait([
            _loadFavoritesList(force: true),
            _loadCart(force: true),
            _loadMineAndOffers(force: true),
            if (_isMarketerRole)
              _loadMarketerBuckets(force: true)
            else
              _loadOwnerRequestsBuckets(force: true),
          ]);
        }
        if (mounted && uid != null && uid.isNotEmpty) {
          _ensureWorkflowRealtimeChannel();
        }
        if (mounted) {
          _ensureHomeFeedRealtimeChannel();
        }
      } catch (e) {
        debugPrint('Auth reload error: $e');
      } finally {
        _reloading = false;
      }
    }();
  }

  void _onMarketingWorkflowBucketsRevision() {
    if (!mounted || !_isMarketerRole) return;
    unawaited(_loadMarketerBuckets(force: true));
  }

  void _scheduleWorkflowDataRefresh() {
    _workflowRtDebounce?.cancel();
    _workflowRtDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      unawaited(() async {
        if (_isMarketerRole) {
          await _loadMarketerBuckets(force: true);
        } else if (!_isGuest) {
          await _loadOwnerRequestsBuckets(force: true);
        }
        if (!_isGuest) {
          await _loadCart(force: true);
          await _loadMyMarketRequestOfferTracking();
        }
        await Future.wait([
          _loadHome(force: true),
          _loadMarketHomeRequests(force: true),
        ]);
      }());
    });
  }

  void _ensureWorkflowRealtimeChannel() {
    if (_isGuest || _uid.isEmpty) return;
    try {
      _workflowRtChannel?.unsubscribe();
      _workflowRtChannel = null;
      final uid = _uid;
      final ch = _sb.channel('dashboard_workflow_$uid');

      void bindEq(String table, String column) {
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: column,
            value: uid,
          ),
          callback: (_) => _scheduleWorkflowDataRefresh(),
        );
      }

      if (_isMarketerRole) {
        bindEq('listing_request_invites', 'marketer_id');
        bindEq('listing_offers', 'marketer_id');
        bindEq('listing_contracts', 'marketer_id');
        bindEq('listing_permits', 'marketer_id');
      } else {
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'listing_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: uid,
          ),
          callback: (_) => _scheduleWorkflowDataRefresh(),
        );
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'market_property_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'requester_id',
            value: uid,
          ),
          callback: (_) => _scheduleWorkflowDataRefresh(),
        );
      }

      if (!_isGuest) {
        bindEq('reservations', 'user_id');
        bindEq('market_request_offers', 'offerer_id');
      }

      ch.subscribe();
      _workflowRtChannel = ch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('workflow realtime bind failed: $e');
      }
    }
  }

  void _disposeWorkflowRealtimeChannel() {
    _workflowRtDebounce?.cancel();
    _workflowRtDebounce = null;
    try {
      _workflowRtChannel?.unsubscribe();
    } catch (_) {}
    _workflowRtChannel = null;
  }

  // =========================
  // init / dispose
  // =========================
  void _hydrateAccountRoleFromCache() {
    final uid = _sb.auth.currentUser?.id ?? '';
    final snap = AccountRoleCache.snapshot;
    if (snap != null &&
        snap.userId.isNotEmpty &&
        uid.isNotEmpty &&
        snap.userId != uid) {
      unawaited(AccountRoleCache.clear());
      return;
    }
    if (uid.isEmpty || snap == null || snap.userId != uid) return;
    _accountType = snap.accountType.trim();
    if (_accountType.isEmpty) _accountType = 'user';
    _verified = snap.verified;
    _accountRoleLoaded = true;
    _orgNavResolved = snap.orgNavResolved;
    _orgNavIsOwner = snap.orgNavIsOwner;
    _orgMembershipPermissions = snap.orgPermissions;
  }

  void _onDashboardDeepLinkPending() {
    final row = InAppDashboardDeepLink.pending.value;
    if (row == null || !mounted) return;
    InAppDashboardDeepLink.pending.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_onNotificationTap(Map<String, dynamic>.from(row)));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _brandPrimary = Theme.of(context).colorScheme.primary;
  }

  @override
  void initState() {
    super.initState();

    _hydrateAccountRoleFromCache();
    _ensureSubTabControllers();

    unawaited(touchWebSessionActivity());
    if (kIsWeb && context.read<AppSession>().isGuest) {
      unawaited(touchWebGuestActivity());
    }

    InAppNotificationHub.onInboxInvalidate = () {
      if (!mounted) return;
      unawaited(_loadNotifications());
    };

    InAppDashboardDeepLink.pending.addListener(_onDashboardDeepLinkPending);

    MarketingWorkflowHub.bucketsRevision
        .addListener(_onMarketingWorkflowBucketsRevision);

    _inlineSearchCtrl.text = _searchQuery;
    unawaited(_loadDashboardGesturePreferences());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_maybeWarmUpWebLocationPermission());
      await _runInitialLoad();
      if (!mounted) return;
      unawaited(ListingDeepLink.openIfQueued(context, lang: widget.lang));
      await _runLoggedInFirstRunPrompts();
    });

    _authSub = _sb.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      _handleAuthReloadIfNeeded();
    });
  }

  Future<void> _loadDashboardGesturePreferences() async {
    final values = await Future.wait<bool>([
      AppGesturePreferences.swipeBackEnabled(),
      AppGesturePreferences.edgeOnlySwipeBack(),
      AppGesturePreferences.keyboardBackEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _swipeBackEnabled = values[0];
      _edgeOnlySwipeBack = values[1];
      _keyboardBackEnabled = values[2];
    });
  }

  bool _dashboardCanGoBack() =>
      _dashboardBodyNavKey.currentState?.canPop() ?? false;

  bool _popDashboardBodyRoute() {
    final bodyNav = _dashboardBodyNavKey.currentState;
    if (bodyNav == null || !bodyNav.canPop()) return false;
    bodyNav.pop();
    return true;
  }

  void _handleDashboardSwipeStart(DragStartDetails details) {
    _dashboardSwipeStart = details.globalPosition;
  }

  void _handleDashboardSwipeEnd(DragEndDetails details) {
    if (!_swipeBackEnabled ||
        !AppGesturePreferences.supportsTouchBack ||
        !_dashboardCanGoBack()) {
      return;
    }
    final start = _dashboardSwipeStart;
    _dashboardSwipeStart = null;
    if (start == null) return;
    final width = MediaQuery.sizeOf(context).width;
    if (_edgeOnlySwipeBack && start.dx > 32 && start.dx < width - 32) return;
    if (details.primaryVelocity == null ||
        details.primaryVelocity!.abs() < 450) {
      return;
    }
    AppHaptics.selection();
    _popDashboardBodyRoute();
  }

  KeyEventResult _handleDashboardKeyEvent(FocusNode node, KeyEvent event) {
    if (!_keyboardBackEnabled ||
        !AppGesturePreferences.supportsKeyboardBack ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.escape &&
        key != LogicalKeyboardKey.browserBack &&
        key != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    return _popDashboardBodyRoute()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  Future<void> _maybeWarmUpWebLocationPermission() async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      const promptedKey = 'web_location_permission_prompted_v1';
      final alreadyPrompted = prefs.getBool(promptedKey) ?? false;
      if (alreadyPrompted) return;
      await prefs.setBool(promptedKey, true);
      final outcome = await detectMapPickerLocation(isWeb: true);
      final pos = outcome.position;
      if (outcome.status == MapPickerLocateStatus.ok && pos != null) {
        await prefs.setDouble(
            AppConfig.prefPreferredExploreLatKey, pos.latitude);
        await prefs.setDouble(
            AppConfig.prefPreferredExploreLngKey, pos.longitude);
        if (!mounted) return;
        setState(() {
          _myLat = pos.latitude;
          _myLng = pos.longitude;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    MarketingWorkflowHub.bucketsRevision
        .removeListener(_onMarketingWorkflowBucketsRevision);
    _disposeWorkflowRealtimeChannel();
    _disposeHomeFeedRealtimeChannel();
    InAppNotificationHub.onInboxInvalidate = null;
    InAppDashboardDeepLink.pending.removeListener(_onDashboardDeepLinkPending);
    _debounce?.cancel();
    _authSub?.cancel();
    _inlineSearchCtrl.dispose();
    _filterChipsHScrollCtrl.dispose();
    _dashboardOnboardingBackdropScroll.dispose();
    _ownerTabsCtrl?.dispose();
    _marketerTabsCtrl?.dispose();
    super.dispose();
  }

  /// المحتوى الرئيسي للوحة (تحت AppBar) داخل أول مسار في [_dashboardBodyNavKey].
  Widget _buildDashboardRootStack({
    required AppLocalizations l10n,
    required List<Property> homeItems,
    required int mySubmissionsCount,
    required List<MarketPropertyRequestRow> homeRequestsFiltered,
    int? mixedHomeTimelineCount,
    required int homeLoadedPropertyRows,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SafeArea(
          child: Column(
            children: [
              if (_tabIndex == 0 || _tabIndex == 1 || _tabIndex == 2)
                _buildTopFilters(
                  compactForMyPage: _tabIndex == 1,
                  onRefresh: () async {
                    await _reloadAll();
                  },
                  showResultCount: _tabIndex != 1,
                  resultCount: _tabIndex == 0
                      ? (_homeFeedKind == HomeFeedKind.listings
                          ? homeItems.length
                          : _homeFeedKind == HomeFeedKind.requests
                              ? homeRequestsFiltered.length
                              : (mixedHomeTimelineCount ??
                                  homeItems.length +
                                      homeRequestsFiltered.length))
                      : _tabIndex == 2
                          ? mySubmissionsCount
                          : 0,
                ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildHomeBody(
                      homeItems,
                      homeRequestsFiltered,
                      loadedPropertyRows: homeLoadedPropertyRows,
                      loadedRequestRows: _marketHomeRequests.length,
                    ),
                    _buildMyAdsHub(),
                    _buildMySubmissionsBody(),
                    _buildCartBody(),
                    _buildSupportHubBody(),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_feedFilterBusy &&
            (_tabIndex == 0 || _tabIndex == 1 || _tabIndex == 2))
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: 14,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
            child: IgnorePointer(
              child: Material(
                elevation: 8,
                shadowColor: Colors.black38,
                shape: const CircleBorder(),
                color: Theme.of(context).colorScheme.surface,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: _brandPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_showDashboardOnboarding)
          Positioned.fill(
            child: DashboardOnboardingOverlay(
              l10n: l10n,
              steps: _buildDashboardOnboardingSteps(l10n),
              onTabChange: (i) {
                if (mounted) setState(() => _tabIndex = i);
              },
              onComplete: () {
                unawaited(_completeDashboardOnboarding());
              },
              onBackdropPointerScroll: _onOnboardingBackdropPointerScroll,
            ),
          ),
      ],
    );
  }

  /// جسم التبويبات داخل [Navigator] — يُستدعى من [Builder] تحت المسار حتى يُحدَّث بعد [_loadHome].
  /// (بدون ذلك يبقى [onGenerateInitialRoutes] ببناء أول إطار فقط وقوائم فارغة للأبد على الويب/الجوال.)
  Widget _buildNestedDashboardBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final homePropertyPool = _mergedHomePropertyPool();
    final homeItems = _applyHiddenFeedFilterToProperties(
      filterListDashboard(
        homePropertyPool,
        excludePropertiesInCart: false,
        homeDiscoveryListingCardsOnly: true,
      ),
    );
    final homeRequestsFiltered = _applyHiddenFeedFilterToRequests(
      filterMarketRequests(
        _isGuest || _uid.isEmpty
            ? _marketHomeRequests
            : _marketHomeRequests.where((r) => r.requesterId != _uid).toList(),
      ),
    );
    final mixedHomeCount = _tabIndex == 0 &&
            _homeFeedKind == HomeFeedKind.all &&
            _sortBy == 'latest'
        ? buildMixedHomeTimeline(homeItems, homeRequestsFiltered).length
        : null;
    final mySubmissionsCount = buildMixedHomeTimeline(
      filterListDashboard(_mine, excludePropertiesInCart: true),
      _marketHomeRequests
          .where((r) => r.requesterId == _uid && _uid.isNotEmpty)
          .toList(),
    ).length;
    return _buildDashboardRootStack(
      l10n: l10n,
      homeItems: homeItems,
      mySubmissionsCount: mySubmissionsCount,
      homeRequestsFiltered: homeRequestsFiltered,
      mixedHomeTimelineCount: mixedHomeCount,
      homeLoadedPropertyRows: homePropertyPool.length,
    );
  }

  // =========================
  // BUILD
  // =========================
  PopupMenuItem<String> _dashboardActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
    Color? color,
    bool enabled = true,
    int badge = 0,
  }) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: color ?? cs.primary),
              if (badge > 0)
                PositionedDirectional(
                  top: -7,
                  end: -7,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: cs.onError,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: enabled ? null : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardActionsMenu(AppLocalizations l10n, ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: _isArabic ? 'الخيارات' : 'Options',
      icon: Icon(Icons.more_vert_rounded, color: cs.primary),
      onSelected: (value) {
        AppHaptics.light();
        switch (value) {
          case 'market':
            unawaited(_openMarketInsights());
            break;
          case 'favorites':
            if (_isGuest) {
              _showLoginDialog();
            } else {
              unawaited(_openFavoritesFromAppBar());
            }
            break;
          case 'settings':
            if (_isGuest) {
              _showLoginDialog();
            } else {
              unawaited(_openSettings());
            }
            break;
          case 'login':
            _navigateToLogin();
            break;
          case 'logout':
            unawaited(_logout());
            break;
        }
      },
      itemBuilder: (context) => [
        if (!_isGuest)
          _dashboardActionMenuItem(
            value: 'presence',
            icon: Icons.circle,
            label: _isArabic ? 'متصل الآن' : 'Online now',
            color: cs.primary,
            enabled: false,
          ),
        _dashboardActionMenuItem(
          value: 'market',
          icon: Icons.insights_outlined,
          label: l10n.marketInsightsTitle,
        ),
        if (!_isGuest)
          _dashboardActionMenuItem(
            value: 'favorites',
            icon: Icons.favorite_outline,
            label: l10n.navFavorites,
            color: cs.error,
            badge: _favoriteIds.length,
          ),
        _dashboardActionMenuItem(
          value: 'settings',
          icon: Icons.settings_outlined,
          label: l10n.settingsLabel,
        ),
        const PopupMenuDivider(),
        _dashboardActionMenuItem(
          value: _isGuest ? 'login' : 'logout',
          icon: _isGuest ? Icons.login : Icons.logout,
          label: _isGuest ? l10n.userSignIn : l10n.logoutLabel,
          color: _isGuest ? cs.primary : cs.error,
          enabled: !(_loggingOut && !_isGuest),
        ),
      ],
    );
  }

  Widget _dashboardNotificationsButton(AppLocalizations l10n, ColorScheme cs) {
    final attentionCount = _unreadNotificationsCount +
        _ownerOffersAttentionCount +
        _chatUnreadTotal;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: _IconBadgeButton(
        tooltip: l10n.communicationHubTitle,
        icon: attentionCount > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_outlined,
        badge: attentionCount,
        color: attentionCount > 0 ? cs.error : cs.primary,
        onPressed: () {
          AppHaptics.light();
          _openNotificationsPage();
        },
      ),
    );
  }

  Widget _dashboardMapButton(ColorScheme cs) {
    final count =
        _all.where((p) => p.latitude != null && p.longitude != null).length +
            _marketHomeRequests
                .where((r) => r.latitude != null && r.longitude != null)
                .length;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: _IconBadgeButton(
        tooltip: widget.isAr ? 'خريطة الإعلانات والطلبات' : 'Listings map',
        icon: Icons.map_outlined,
        badge: count,
        color: cs.primary,
        onPressed: () {
          unawaited(_openMapDiscovery());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _readArgsInBuildOnce(context);
    final l10n = AppLocalizations.of(context)!;
    final appSession = context.watch<AppSession>();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bottomSlots = _dashboardBottomSlots();
    final navIndex = _bottomNavSelectedIndex(bottomSlots);
    final canPopDashboardBody = _dashboardCanGoBack();
    final useSideNav = AppLayout.useDashboardSideNavigation(context);

    final dashboardScaffold = Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: _isGuest ? 76 : 82,
        automaticallyImplyLeading: false,
        leading: canPopDashboardBody
            ? IconButton(
                tooltip: _isArabic ? 'رجوع' : 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _popDashboardBodyRoute,
              )
            : null,
        title: _dashboardHomeAppBarTitle(l10n),
        actions: [
          _dashboardMapButton(cs),
          _dashboardNotificationsButton(l10n, cs),
          _dashboardActionsMenu(l10n, cs),
        ],
      ),
      body: Navigator(
        key: _dashboardBodyNavKey,
        observers: <NavigatorObserver>[_dashboardBodyNavObserver],
        onGenerateInitialRoutes: (nav, initialRoute) => [
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/dashboard/root'),
            builder: (routeContext) => Builder(
              builder: (innerContext) {
                final host =
                    innerContext.findAncestorStateOfType<_UserDashboardState>();
                if (host == null) return const SizedBox.shrink();
                return host._buildNestedDashboardBody(innerContext);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: useSideNav && _showBottomNavAddSlot && !_isGuest
          ? FloatingActionButton(
              onPressed: () {
                AppHaptics.medium();
                _openCenterPlus();
              },
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              child: const Icon(Icons.add_rounded, size: 32),
            )
          : null,
      bottomNavigationBar: useSideNav
          ? null
          : LayoutBuilder(
              builder: (context, constraints) {
                final iconOnlyBottomNav =
                    bottomSlots.length > 5 || constraints.maxWidth < 520;
                final compactBottomNav =
                    iconOnlyBottomNav || constraints.maxWidth < 680;
                return NavigationBarTheme(
                  data: NavigationBarThemeData(
                    labelTextStyle: WidgetStateProperty.all(
                      TextStyle(
                        fontSize: compactBottomNav ? 8 : 9,
                        height: compactBottomNav ? 0.96 : 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    height:
                        iconOnlyBottomNav ? 64 : (compactBottomNav ? 76 : 72),
                    labelBehavior: iconOnlyBottomNav
                        ? NavigationDestinationLabelBehavior.alwaysHide
                        : NavigationDestinationLabelBehavior.alwaysShow,
                    selectedIndex: navIndex,
                    indicatorColor: _brandPrimary.withValues(alpha: _op(28)),
                    onDestinationSelected: (i) {
                      AppHaptics.selection();
                      _onDashboardBottomNavSelected(bottomSlots, i);
                    },
                    destinations: _dashboardBottomDestinations(
                      l10n,
                      bottomSlots,
                      compact: compactBottomNav,
                    ),
                  ),
                );
              },
            ),
    );

    final mainChrome = useSideNav
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NavigationRailTheme(
                data: NavigationRailThemeData(
                  indicatorColor: _brandPrimary.withValues(alpha: _op(28)),
                ),
                child: NavigationRail(
                  selectedIndex: navIndex,
                  onDestinationSelected: (i) {
                    AppHaptics.selection();
                    _onDashboardBottomNavSelected(bottomSlots, i);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: _dashboardRailDestinations(l10n, bottomSlots),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
              Expanded(child: dashboardScaffold),
            ],
          )
        : dashboardScaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!appSession.hasInternet) return;
        if (_popDashboardBodyRoute()) return;
        if (_isGuest) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
      child: Focus(
        autofocus: AppGesturePreferences.supportsKeyboardBack,
        onKeyEvent: _handleDashboardKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _handleDashboardSwipeStart,
          onHorizontalDragEnd: _handleDashboardSwipeEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              mainChrome,
              if (!appSession.hasInternet)
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AbsorbPointer(
                        child: ColoredBox(
                          color: cs.scrim.withValues(alpha: 0.55),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Card(
                              margin: const EdgeInsets.all(18),
                              elevation: 12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.wifi_off_rounded,
                                        size: 52, color: cs.onSurface),
                                    const SizedBox(height: 10),
                                    Text(
                                      l10n.offlineNoInternetTitle,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.offlineGlobalOverlayHint,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.35,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: cs.primary,
                                          foregroundColor: cs.onPrimary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: appSession.networkCheckBusy
                                            ? null
                                            : () =>
                                                appSession.refreshConnectivity(
                                                  userInitiated: true,
                                                ),
                                        icon: appSession.networkCheckBusy
                                            ? SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: AppLogoLoading(
                                                  compact: true,
                                                  size: 20,
                                                ),
                                              )
                                            : const Icon(Icons.refresh_rounded),
                                        label: Text(l10n.retryLabel),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // Bottom navigation (ديناميكي حسب account_type — عالمي، بدون تكرار مع AppBar)
  // =========================
  List<DashboardBottomSlot> _dashboardBottomSlots() {
    // تبويبات ثابتة في الأسفل، مع إبقاء الأيقونات متجاوبة عند زيادة العدد.
    return const <DashboardBottomSlot>[
      DashboardBottomSlot.home,
      DashboardBottomSlot.myAds,
      DashboardBottomSlot.mySubmissions,
      DashboardBottomSlot.addListing,
      DashboardBottomSlot.myDesk,
      DashboardBottomSlot.cart,
      DashboardBottomSlot.support,
    ];
  }

  String _dashboardNavLabel(String label) => label.replaceAll(' ', '\u00A0');

  int _bottomNavSelectedIndex(List<DashboardBottomSlot> slots) {
    for (var i = 0; i < slots.length; i++) {
      switch (slots[i]) {
        case DashboardBottomSlot.home:
          if (_tabIndex == 0) return i;
          break;
        case DashboardBottomSlot.myAds:
          if (_tabIndex == 1) return i;
          break;
        case DashboardBottomSlot.mySubmissions:
          if (_tabIndex == 2) return i;
          break;
        case DashboardBottomSlot.cart:
          if (_showBottomNavCart && _tabIndex == 3) return i;
          break;
        case DashboardBottomSlot.support:
          if (_tabIndex == 4) return i;
          break;
        case DashboardBottomSlot.myDesk:
          break;
        case DashboardBottomSlot.addListing:
          break;
      }
    }
    return 0;
  }

  void _onDashboardBottomNavSelected(List<DashboardBottomSlot> slots, int i) {
    FocusScope.of(context).unfocus();
    _dashboardBodyNavKey.currentState?.popUntil((r) => r.isFirst);

    if (_isGuest) {
      final slot = slots[i];
      if (slot != DashboardBottomSlot.home &&
          slot != DashboardBottomSlot.support) {
        _showLoginDialog();
        return;
      }
    }

    switch (slots[i]) {
      case DashboardBottomSlot.home:
        setState(() => _tabIndex = 0);
        break;
      case DashboardBottomSlot.myAds:
        setState(() => _tabIndex = 1);
        break;
      case DashboardBottomSlot.mySubmissions:
        setState(() => _tabIndex = 2);
        break;
      case DashboardBottomSlot.addListing:
        if (!_accountRoleLoaded) return;
        if (!_showBottomNavAddSlot) {
          _showNotification(
            _isArabic ? 'تنبيه' : 'Notice',
            _isArabic
                ? 'إضافة إعلان غير متاحة لهذا الحساب أو بصلاحياتك الحالية.'
                : 'Posting an ad is not available for this account or your current permissions.',
            isError: false,
          );
          return;
        }
        AppHaptics.medium();
        _openCenterPlus();
        break;
      case DashboardBottomSlot.myDesk:
        if (!_accountRoleLoaded) return;
        if (!_showBottomNavMyDeskSlot) {
          _showNotification(
            _isArabic ? 'تنبيه' : 'Notice',
            _isArabic
                ? 'إدارتي غير متاحة لهذا الحساب أو بصلاحياتك الحالية.'
                : 'My desk is not available for this account or your current permissions.',
            isError: false,
          );
          return;
        }
        _openMyDeskNav();
        break;
      case DashboardBottomSlot.cart:
        if (!_accountRoleLoaded) return;
        if (_isGuest) return;
        setState(() => _tabIndex = 3);
        break;
      case DashboardBottomSlot.support:
        setState(() => _tabIndex = 4);
        break;
    }
  }

  List<NavigationDestination> _dashboardBottomDestinations(
      AppLocalizations l10n, List<DashboardBottomSlot> slots,
      {bool compact = false}) {
    return slots.map((slot) {
      switch (slot) {
        case DashboardBottomSlot.home:
          return NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: _dashboardNavLabel(l10n.navHome),
          );
        case DashboardBottomSlot.myAds:
          return NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: _dashboardNavLabel(l10n.navMyAds),
          );
        case DashboardBottomSlot.mySubmissions:
          return NavigationDestination(
            icon: const Icon(Icons.assignment_turned_in_outlined),
            selectedIcon: const Icon(Icons.assignment_turned_in),
            label: _dashboardNavLabel(l10n.navMySubmissions),
          );
        case DashboardBottomSlot.addListing:
          final csAdd = Theme.of(context).colorScheme;
          final addOn = _isGuest || _showBottomNavAddSlot;
          final addRoleLoading = !_isGuest && !_accountRoleLoaded;
          final addOpacity = addRoleLoading ? 0.38 : (addOn ? 1.0 : 0.45);
          final addSize = compact ? 40.0 : 46.0;
          final addIconSize = compact ? 27.0 : 30.0;
          Widget addChip({required bool filled}) {
            return Material(
              elevation: filled ? 12 : 8,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.black38,
              shape: const CircleBorder(),
              color: csAdd.primary,
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: addSize,
                height: addSize,
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    size: addIconSize,
                    color: csAdd.onPrimary,
                  ),
                ),
              ),
            );
          }

          return NavigationDestination(
            icon: Opacity(
              opacity: addOpacity,
              child: addChip(filled: false),
            ),
            selectedIcon: Opacity(
              opacity: addOpacity,
              child: addChip(filled: true),
            ),
            label: _dashboardNavLabel(_isArabic ? 'إضافة إعلان' : l10n.navAdd),
          );
        case DashboardBottomSlot.myDesk:
          final deskOn = _isGuest || _showBottomNavMyDeskSlot;
          final roleLoading = !_isGuest && !_accountRoleLoaded;
          final deskOpacity = roleLoading ? 0.38 : (deskOn ? 1.0 : 0.45);
          const deskAlert = false;
          return NavigationDestination(
            icon: Opacity(
              opacity: deskOpacity,
              child: Tooltip(
                message: l10n.navMyDeskPipelineBadgeTooltip,
                child: _DeskNavBottomIcon(
                  icon: Icons.dashboard_outlined,
                  showDot: deskAlert,
                ),
              ),
            ),
            selectedIcon: Opacity(
              opacity: deskOpacity,
              child: Tooltip(
                message: l10n.navMyDeskPipelineBadgeTooltip,
                child: _DeskNavBottomIcon(
                  icon: Icons.dashboard,
                  showDot: deskAlert,
                  filled: true,
                ),
              ),
            ),
            label: _dashboardNavLabel(l10n.navMyDesk),
          );
        case DashboardBottomSlot.cart:
          final roleLoading = !_isGuest && !_accountRoleLoaded;
          final cartOpacity = _isGuest ? 1.0 : (roleLoading ? 0.38 : 1.0);
          final cartMuted = Theme.of(context).colorScheme.onSurfaceVariant;
          final cartCs = Theme.of(context).colorScheme;
          return NavigationDestination(
            icon: Opacity(
              opacity: cartOpacity,
              child: _BadgeIcon(
                icon: Icons.handshake_outlined,
                badge: _isGuest ? 0 : _cartCount,
                color: roleLoading
                    ? cartMuted
                    : (_cartCount > 0 ? cartCs.error : _brandPrimary),
              ),
            ),
            selectedIcon: Opacity(
              opacity: cartOpacity,
              child: Icon(
                Icons.handshake,
                color: roleLoading ? cartMuted : null,
              ),
            ),
            label: _dashboardNavLabel(l10n.navCart),
          );
        case DashboardBottomSlot.support:
          return NavigationDestination(
            icon: const Icon(Icons.support_agent_outlined),
            selectedIcon: const Icon(Icons.support_agent),
            label:
                _dashboardNavLabel(_isArabic ? 'الدعم الفني' : l10n.navSupport),
          );
      }
    }).toList();
  }

  List<NavigationRailDestination> _dashboardRailDestinations(
    AppLocalizations l10n,
    List<DashboardBottomSlot> slots,
  ) {
    final nav = _dashboardBottomDestinations(l10n, slots);
    return nav
        .map(
          (d) => NavigationRailDestination(
            icon: d.icon,
            selectedIcon: d.selectedIcon ?? d.icon,
            label: Text(
              d.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        )
        .toList();
  }

  // =========================
  // App bar (greeting on Home)
  // =========================
  String _dashboardAppBarTitle(AppLocalizations l10n) {
    if (_tabIndex != 0) {
      return _tabTitle();
    }
    if (_isGuest) {
      return l10n.navHome;
    }
    final raw = _displayNameFromProfile(_profileCache[_uid]).trim();
    final name = DashboardGreeting.firstChunk(raw);
    if (name.isEmpty) {
      return l10n.navHome;
    }
    return DashboardGreeting.appBarLine(
      isAr: _isArabic,
      displayName: name,
      isMarketingAccountType: _isMarketingAccountType,
    );
  }

  /// عنوان الرئيسية: سطر تحية + «شريكنا العقاري» ثم الاسم الرباعي بـ [FittedBox] حسب عرض الشاشة.
  Widget _dashboardHomeAppBarTitle(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_isGuest) {
      final title = _tabIndex == 0 ? l10n.navHome : _tabTitle();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isArabic ? 'تصفّح كضيف' : 'Browsing as guest',
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              height: 1.15,
            ),
          ),
        ],
      );
    }

    final salute = DashboardGreeting.salutationOnly(isAr: _isArabic);
    final partner = _isArabic ? 'شريكنا' : 'partner';
    final raw = _displayNameFromProfile(_profileCache[_uid]).trim();
    final width = MediaQuery.sizeOf(context).width;
    final narrowToolbar = width < 520;
    final mediumToolbar = width < 760;
    final displayName =
        DashboardGreeting.displayNameForAppBar(raw, compact: narrowToolbar);
    final mediumName = _displayNameForDashboardTitle(
      raw,
      compact: narrowToolbar,
      medium: mediumToolbar,
    );

    final subStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
      height: 1.2,
    );

    final line1 = '$salute $partner';
    final fallbackTitle = _tabIndex == 0 ? l10n.navHome : _tabTitle();
    final nameLine = mediumName.isNotEmpty
        ? mediumName
        : (displayName.isNotEmpty ? displayName : fallbackTitle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = constraints.maxWidth < 220 ? 14.5 : 16.5;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subStyle,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  _isArabic ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                nameLine,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textAlign: _isArabic ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: fontSize,
                  height: 1.05,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _displayNameForDashboardTitle(
    String fullName, {
    required bool compact,
    required bool medium,
  }) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    if (compact) return '${parts.first} ${parts.last}';
    if (medium && parts.length >= 3) {
      return '${parts.first} ${parts[1]} ${parts.last}';
    }
    return parts.join(' ');
  }

  // =========================
  // Tab title
  // =========================
  String _tabTitle() {
    final l10n = AppLocalizations.of(context)!;
    switch (_tabIndex) {
      case 0:
        return l10n.navHome;
      case 1:
        return l10n.navMyAds;
      case 2:
        return l10n.navMySubmissions;
      case 3:
        return l10n.navCart;
      case 4:
        return l10n.navSupport;
      default:
        return '';
    }
  }

  // =========================
  // Fail load messages
  // =========================
  String _failLoadTitle() {
    return _isArabic ? 'فشل التحميل' : 'Failed to load';
  }

  String _failLoadSubtitle() {
    return _isArabic
        ? 'حدث خطأ أثناء التحميل'
        : 'An error occurred while loading';
  }

  String _marketOfferStatusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (_isArabic) {
      switch (s) {
        case '':
        case 'pending':
        case 'submitted':
          return 'قيد الانتظار';
        case 'accepted':
        case 'approved':
        case 'owner_accepted':
        case 'selected':
          return 'مقبول';
        case 'rejected':
        case 'declined':
        case 'owner_rejected':
          return 'مرفوض';
        case 'withdrawn':
          return 'مسحوب';
        case 'expired':
          return 'منتهي';
        case 'cancelled':
        case 'canceled':
          return 'ملغى';
        default:
          return raw.trim().isEmpty ? '—' : raw.trim();
      }
    }
    switch (s) {
      case '':
        return 'Pending';
      case 'owner_accepted':
        return 'Owner accepted';
      case 'owner_rejected':
        return 'Not selected';
      default:
        return raw.trim().isEmpty ? 'N/A' : raw.trim();
    }
  }

  // =========================
  // Open settings
  // =========================
  Future<void> _openSettings() async {
    if (!mounted) return;

    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/dashboard/settings'),
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  Future<void> _openMarketInsights() async {
    if (!mounted) return;
    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.marketInsights),
        builder: (_) => MarketInsightsPage(lang: widget.lang),
      ),
    );
  }

  // =========================
  // Price row widget
  // =========================
  Widget _priceRow(
    BuildContext context, {
    required String label,
    required double value,
    bool bold = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        AppMoneyLine(
          amount: value,
          currencyCode: 'SAR',
          isAr: _isArabic,
          maxFractionDigits: 0,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            color: bold ? _brandPrimary : cs.onSurface,
          ),
        ),
      ],
    );
  }

  // =========================
  // Open add request
  // =========================
  Future<void> _openAddRequest() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    _showNotification(
      _isArabic ? 'قريباً' : 'Coming Soon',
      _isArabic
          ? 'صفحة إضافة طلب تسويق قريباً'
          : 'Add marketing request page coming soon',
    );
  }

  // =========================
  // Build top filters
  // =========================
  Widget _buildTopFilters({
    required Future<void> Function() onRefresh,
    required int resultCount,
    bool showResultCount = true,
    bool compactForMyPage = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    final compactFilledStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
    );
    final compactOutlinedStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
    );

    final clearNearestBtn = OutlinedButton.icon(
      onPressed: _clearNearestMode,
      style: compactOutlinedStyle,
      icon: const Icon(Icons.close),
      label: Text(
        _isArabic ? 'إلغاء الأقرب' : 'Cancel nearest',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final clearAllBtn = OutlinedButton.icon(
      onPressed: _clearAllTopFilters,
      style: compactOutlinedStyle,
      icon: const Icon(Icons.filter_alt_off_outlined),
      label: Text(
        _isArabic ? 'مسح الفلاتر' : 'Clear filters',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final refreshBtn = FilledButton.icon(
      onPressed: () async => await onRefresh(),
      style: compactFilledStyle,
      icon: const Icon(Icons.refresh),
      label: Text(
        _isArabic ? 'تحديث' : 'Refresh',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final advancedSearchBtn = OutlinedButton.icon(
      onPressed: _openSearchFiltersSheet,
      style: compactOutlinedStyle,
      icon: const Icon(Icons.tune),
      label: Text(
        _isArabic ? 'متقدم' : 'Advanced',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final hiddenBtn = OutlinedButton.icon(
      onPressed: _isGuest
          ? _showLoginDialog
          : () {
              setState(() {
                _homeShowHiddenOnly = !_homeShowHiddenOnly;
                if (_homeShowHiddenOnly) {
                  _homeFeedKind = HomeFeedKind.all;
                }
              });
            },
      style: compactOutlinedStyle,
      icon: Icon(_homeShowHiddenOnly
          ? Icons.visibility_outlined
          : Icons.visibility_off_outlined),
      label: Text(
        _homeShowHiddenOnly
            ? (_isArabic ? 'الرئيسية' : 'Home')
            : (_isArabic ? 'المخفية' : 'Hidden'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final resultChip = showResultCount
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Text(
              _isArabic ? 'النتائج: $resultCount' : 'Results: $resultCount',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                fontSize: 12,
              ),
            ),
          )
        : const SizedBox.shrink();

    Widget buildSearchField() {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: _inlineSearchCtrl,
        builder: (context, val, _) {
          final hasDraft = val.text.trim().isNotEmpty;
          return TextField(
            controller: _inlineSearchCtrl,
            onChanged: (_) => _scheduleInlineSearchApply(),
            onSubmitted: (_) {
              _flushInlineSearchNow();
              FocusScope.of(context).unfocus();
            },
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.search,
            maxLines: 1,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: !hasDraft
                  ? null
                  : IconButton(
                      tooltip: _isArabic ? 'مسح' : 'Clear',
                      onPressed: () {
                        _debounce?.cancel();
                        _inlineSearchCtrl.clear();
                        _setSearchQuery('');
                        if (mounted) setState(() => _feedFilterBusy = false);
                      },
                      icon: const Icon(Icons.close),
                    ),
              hintText: _isArabic
                  ? 'بحث سريع بالعنوان أو الموقع أو الوصف'
                  : 'Quick search by title, location or description',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withOpacity(0.20),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.35),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: _brandPrimary.withOpacity(0.70),
                  width: 1.3,
                ),
              ),
            ),
          );
        },
      );
    }

    Widget buildHomeKindTabs({required bool compact}) {
      final items = <({HomeFeedKind kind, IconData icon, String label})>[
        (
          kind: HomeFeedKind.all,
          icon: Icons.grid_view_rounded,
          label: _isArabic ? 'الكل' : 'All',
        ),
        (
          kind: HomeFeedKind.requests,
          icon: Icons.request_quote_outlined,
          label: _isArabic ? 'الطلبات' : 'Requests',
        ),
        (
          kind: HomeFeedKind.listings,
          icon: Icons.home_work_outlined,
          label: _isArabic ? 'الإعلانات' : 'Listings',
        ),
      ];

      return Semantics(
        label: _isArabic ? 'فلتر بطاقات الرئيسية' : 'Home cards filter',
        button: false,
        child: Container(
          height: compact ? 38 : 42,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.32),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.42)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Expanded(
                  child: Material(
                    color: _homeFeedKind == items[i].kind
                        ? _brandPrimary
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => _setHomeFeedKind(items[i].kind),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 4 : 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              items[i].icon,
                              size: compact ? 15 : 17,
                              color: _homeFeedKind == items[i].kind
                                  ? Colors.white
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: _homeFeedKind == items[i].kind
                                      ? Colors.white
                                      : cs.onSurfaceVariant,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (i != items.length - 1)
                  Container(
                    width: 1,
                    height: compact ? 22 : 26,
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    Widget stretchRow(List<Widget> children) {
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i != children.length - 1) const SizedBox(width: 6),
          ],
        ],
      );
    }

    Widget wrapToolbarActions(List<Widget> children) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }

    return Material(
      color: cs.surface,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: compactForMyPage
            ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
            : const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.25)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final isNarrow = c.maxWidth < 880;

                if (compactForMyPage) {
                  if (isNarrow) {
                    final primaryActions = <Widget>[
                      refreshBtn,
                      advancedSearchBtn,
                      if (_hasActiveTopFilters) clearAllBtn,
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buildSearchField(),
                        const SizedBox(height: 6),
                        _SortMenu(
                          isAr: _isArabic,
                          value: _sortBy,
                          onChanged: _setSortBy,
                          compactToolbar: true,
                        ),
                        const SizedBox(height: 6),
                        stretchRow(primaryActions),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: buildSearchField(),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: _isArabic ? 168 : 158,
                        child: _SortMenu(
                          isAr: _isArabic,
                          value: _sortBy,
                          onChanged: _setSortBy,
                          compactToolbar: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      refreshBtn,
                      const SizedBox(width: 8),
                      advancedSearchBtn,
                      if (_hasActiveTopFilters) ...[
                        const SizedBox(width: 8),
                        clearAllBtn,
                      ],
                    ],
                  );
                }

                final searchField = buildSearchField();
                final feedKindTabs = buildHomeKindTabs(compact: isNarrow);

                if (isNarrow) {
                  final topActions = <Widget>[
                    if (showResultCount) resultChip,
                    refreshBtn,
                  ];
                  final secondActions = <Widget>[
                    advancedSearchBtn,
                    hiddenBtn,
                    if (_isNearestMode) clearNearestBtn,
                    if (_hasActiveTopFilters) clearAllBtn,
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 8),
                      feedKindTabs,
                      const SizedBox(height: 8),
                      stretchRow(topActions),
                      const SizedBox(height: 6),
                      stretchRow(secondActions),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 4, child: searchField),
                    const SizedBox(width: 10),
                    SizedBox(width: _isArabic ? 292 : 274, child: feedKindTabs),
                    const SizedBox(width: 10),
                    resultChip,
                    const SizedBox(width: 10),
                    advancedSearchBtn,
                    const SizedBox(width: 10),
                    hiddenBtn,
                    if (_isNearestMode) ...[
                      const SizedBox(width: 10),
                      clearNearestBtn,
                    ],
                    if (_hasActiveTopFilters) ...[
                      const SizedBox(width: 10),
                      clearAllBtn,
                    ],
                    const SizedBox(width: 10),
                    refreshBtn,
                  ],
                );
              },
            ),
            if (!compactForMyPage) ...[
              _buildActiveFilterChips(),
            ],
          ],
        ),
      ),
    );
  }

  // =========================
  // Offline error check
  // =========================
  bool _isOfflineErrorStr(String? err) {
    if (err == null) return false;
    final e = err.toLowerCase();
    return e.contains('socketexception') ||
        e.contains('failed host lookup') ||
        e.contains('connection reset') ||
        e.contains('connection refused') ||
        e.contains('network is unreachable') ||
        e.contains('timed out') ||
        e.contains('timeout') ||
        e.contains('clientexception') ||
        e.contains('handshake') ||
        e.contains('xmlhttprequest') ||
        e.contains('fetch') ||
        e.contains('offline');
  }

  // =========================
  // Retry with offline hint
  // =========================
  Future<void> _retryWithOfflineHint(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      final msg = e.toString();
      final offline = _isOfflineErrorStr(msg);
      if (!mounted) return;

      _showNotification(
        offline
            ? (_isArabic ? 'لا يوجد اتصال' : 'No connection')
            : (_isArabic ? 'فشل التحديث' : 'Refresh failed'),
        offline
            ? (_isArabic
                ? 'تحقق من الإنترنت ثم أعد المحاولة.'
                : 'Check your internet connection then try again.')
            : (_isArabic ? 'حدث خطأ: $msg' : 'Error: $msg'),
        isError: true,
      );
    }
  }

  // =========================
  // Loading with fallback
  // =========================
  Widget _loadingWithFallback({
    required bool loading,
    required DateTime? since,
    required String title,
    required String subtitle,
    required VoidCallback onRetry,
  }) {
    if (!loading) return const SizedBox.shrink();

    final tooLong = _loadingTooLong(since);
    if (!tooLong) {
      return const PropertyCardSkeletonList(count: 6, topPadding: 16);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.info_outline, size: 54, color: _brandPrimary),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: () {
            AppHaptics.light();
            onRetry();
          },
          icon: const Icon(Icons.refresh),
          label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brandPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // =========================
  // Build home body
  // =========================
  Widget _buildMarketRequestsHomeSection(
    List<MarketPropertyRequestRow> items, {
    bool alwaysShowSectionTitle = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_homeFeedKind == HomeFeedKind.all || alwaysShowSectionTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Row(
                children: [
                  Icon(Icons.request_quote_outlined, color: _brandPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isArabic ? 'طلبات السوق' : 'Market requests',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MarketRequestListingStyleCard(
                request: r,
                isAr: _isArabic,
                bankColor: _brandPrimary,
                currentUserId: _uid.isEmpty ? 'guest' : _uid,
                timeAgo: _timeAgo,
                priorityLabel:
                    _marketRequestPriorityL10nLabel(l10n, r.requestPriority),
                onOpen: () => _openMarketRequestDetail(r),
                homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
                onRestoreMarketRequest:
                    _isGuest ? null : _onRestoreMarketRequest,
                onHomeHideMarketRequest: _isGuest
                    ? (r) async => _showLoginDialog()
                    : _onHomeHideMarketRequest,
                onHomeReportMarketRequest:
                    _isGuest ? null : _onHomeReportMarketRequest,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeBody(
    List<Property> homeItems,
    List<MarketPropertyRequestRow> homeRequestsFiltered, {
    required int loadedPropertyRows,
    required int loadedRequestRows,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(0);

    final showListings = _homeFeedKind == HomeFeedKind.all ||
        _homeFeedKind == HomeFeedKind.listings;
    final showRequests = _homeFeedKind == HomeFeedKind.all ||
        _homeFeedKind == HomeFeedKind.requests;

    final fallback = _loadingWithFallback(
      loading: _loadingHome,
      since: _homeLoadingSince,
      title: _isArabic ? 'جارٍ التحميل…' : 'Loading…',
      subtitle: _isArabic
          ? 'إذا استمر التحميل، اضغط تحديث.'
          : 'If loading continues, tap refresh.',
      onRetry: () => _retryWithOfflineHint(_reloadAll),
    );

    if (_homeFeedKind == HomeFeedKind.requests) {
      if (_loadingMarketRequests && homeRequestsFiltered.isEmpty) {
        return const Center(child: AppLogoLoading());
      }
    } else if (_homeFeedKind == HomeFeedKind.all) {
      // لا نُجمّد الرئيسية بالكامل إن وُجدت طلبات سوق أو إعلانات جاهزة لأحد المصدرين.
      final hasAnyFeedContent =
          homeItems.isNotEmpty || homeRequestsFiltered.isNotEmpty;
      if (!hasAnyFeedContent && (_loadingHome || _loadingMarketRequests)) {
        return fallback;
      }
    } else if (_loadingHome) {
      return fallback;
    }

    final suppressFullPageHomeListingError = _errorHome != null &&
        _homeFeedKind == HomeFeedKind.all &&
        homeRequestsFiltered.isNotEmpty;

    if (_errorHome != null &&
        _homeFeedKind != HomeFeedKind.requests &&
        !suppressFullPageHomeListingError) {
      final offline = _isOfflineErrorStr(_errorHome);

      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline
                  ? (_isArabic
                      ? 'لا يوجد اتصال بالإنترنت'
                      : 'No Internet Connection')
                  : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic
                      ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.'
                      : 'Make sure you are online, then retry.')
                  : _failLoadSubtitle(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          if (kDebugMode) Text(_errorHome!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(_reloadAll),
              icon: const Icon(Icons.refresh),
              label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final listingsEmpty = !showListings || homeItems.isEmpty;
    final requestsEmpty = !showRequests || homeRequestsFiltered.isEmpty;

    if (listingsEmpty && requestsEmpty) {
      final icon = _homeFeedKind == HomeFeedKind.requests
          ? Icons.request_quote_outlined
          : Icons.home_outlined;
      final title = switch (_homeFeedKind) {
        HomeFeedKind.all =>
          _isArabic ? 'لا توجد بطاقات في الرئيسية' : 'No cards on Home',
        HomeFeedKind.listings =>
          _isArabic ? 'لا توجد بطاقات إعلانات' : 'No listing cards',
        HomeFeedKind.requests =>
          _isArabic ? 'لا توجد بطاقات طلبات' : 'No request cards',
      };
      final pipeL = _homePropertyFeedPipelineCounts();
      final pipeR = _homeRequestFeedPipelineCounts();
      final likelyHasServerDataButFiltered =
          loadedPropertyRows > 0 || loadedRequestRows > 0;
      final canBenefitFromReset = _hasActiveTopFilters ||
          _hiddenPropertyIds.isNotEmpty ||
          _hiddenMarketRequestIds.isNotEmpty ||
          (showListings && pipeL.server > 0 && pipeL.shown == 0) ||
          (showRequests && pipeR.server > 0 && pipeR.shown == 0);
      final marketReqErr = _shortUserFacingApiError(_errorMarketRequests);

      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  _isArabic
                      ? 'جرّب تعديل البحث أو مسح الفلاتر ثم التحديث.'
                      : 'Try adjusting search, clearing filters, or pull to refresh.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 14),
                  ..._homeFeedEmptyDiagnosticBlocks(
                    showListings: showListings,
                    showRequests: showRequests,
                    textColor: cs.onSurfaceVariant,
                  ),
                ],
                if (_hasActiveTopFilters) ...[
                  const SizedBox(height: 10),
                  Text(
                    _isArabic
                        ? 'فلاتر علوية نشطة — قد تقلّل النتائج الظاهرة.'
                        : 'Some top filters are on — they may reduce visible results.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                  ),
                ],
                if (showRequests &&
                    marketReqErr != null &&
                    marketReqErr.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Material(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 20,
                            color: cs.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isArabic
                                  ? 'خطأ أثناء تحميل طلبات السوق: $marketReqErr'
                                  : 'Market requests load error: $marketReqErr',
                              style: TextStyle(
                                color: cs.onErrorContainer,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (likelyHasServerDataButFiltered || canBenefitFromReset) ...[
                  const SizedBox(height: 14),
                  Text(
                    _isArabic
                        ? 'إن كان السبب فلاتر التطبيق أو الإخفاء المحلي، استخدم الزر أدناه ثم أعد التحديث.'
                        : 'If filters or local hide rules caused this, use the button below and refresh.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      AppHaptics.light();
                      _clearAllTopFilters();
                      unawaited(_retryWithOfflineHint(_reloadAll));
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      _isArabic
                          ? 'إعادة ضبط الفلاتر وتحديث'
                          : 'Reset filters & refresh',
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => _retryWithOfflineHint(_reloadAll),
                  icon: const Icon(Icons.refresh),
                  label: Text(_isArabic ? 'تحديث' : 'Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final useMergedTimeline = _homeFeedKind == HomeFeedKind.all &&
        _sortBy == 'latest' &&
        showListings &&
        showRequests;

    final mixedEntries = useMergedTimeline
        ? buildMixedHomeTimeline(homeItems, homeRequestsFiltered)
        : const <HomeMixedFeedEntry>[];

    final mixedBlock = (!useMergedTimeline || mixedEntries.isEmpty)
        ? const SizedBox.shrink()
        : RepaintBoundary(
            child: _HomeMixedTimeline(
              entries: mixedEntries,
              currentUserId: _uid.isEmpty ? 'guest' : _uid,
              isAr: _isArabic,
              bankColor: _brandPrimary,
              isFav: (id) => _isFav(id),
              onToggleFav: (id) => _toggleFav(id),
              onOpenDetails: (p) => _openDetails(p),
              activeHoldCount: (pid) => _activeReservationHoldCount(pid),
              isReserved: (pid) => _isReservedByAnyone(pid),
              reservedUntil: (pid) => _reservedUntil(pid),
              reservedByName: (pid) => _reservedByName(pid),
              onAddToCart: (p) => _addToCart(p),
              onEditProperty: _editProperty,
              onDeleteProperty: (p) => _requestDeleteProperty(p),
              timeAgo: _timeAgo,
              canShowCartButton: _cartReservationFeaturesEnabled,
              onPropertyViewsInteraction: (ctx, p, isOwner) {
                final pubId = (p.publishedByMarketerId ?? '').trim();
                final isPm = !_isGuest && _uid.isNotEmpty && pubId == _uid;
                PropertyViewService.showSheet(
                  context: ctx,
                  sb: _sb,
                  propertyId: p.id,
                  viewsCount: p.views,
                  isOwner: isOwner,
                  isPublishingMarketer: isPm,
                  isAr: _isArabic,
                );
              },
              onCopyListingWebLink: _copyListingPublicLink,
              onOpenMarketRequest: _openMarketRequestDetail,
              onEditMarketRequest: _editMarketRequest,
              onSubmitMarketRequestOffer: _isGuest
                  ? (r) => _showLoginDialog()
                  : (r) =>
                      _openMarketRequestDetail(r, autoOpenSubmitOffer: true),
              marketRequestPriorityLabel: (r) =>
                  _marketRequestPriorityL10nLabel(l10n, r.requestPriority),
              suppressPublicOwnerIdentityOnCards: true,
              onShareListingFromCard: _shareListingFromCard,
              onHomeHideFromFeed: _isGuest
                  ? (p) async => _showLoginDialog()
                  : _onHomeHideProperty,
              onHomeReportListing: _isGuest
                  ? (p) async => _showLoginDialog()
                  : _onHomeReportProperty,
              onHomeHideMarketRequest: _isGuest
                  ? (r) async => _showLoginDialog()
                  : _onHomeHideMarketRequest,
              onHomeReportMarketRequest: _isGuest
                  ? (r) async => _showLoginDialog()
                  : _onHomeReportMarketRequest,
              homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
              onRestorePropertyToHome:
                  _isGuest ? null : _onRestorePropertyToHome,
              onWithdrawPropertyReport:
                  _isGuest ? null : _onWithdrawPropertyReport,
              onRestoreMarketRequest: _isGuest ? null : _onRestoreMarketRequest,
            ),
          );

    final grid = useMergedTimeline
        ? const SizedBox.shrink()
        : ((!showListings || homeItems.isEmpty)
            ? const SizedBox.shrink()
            : RepaintBoundary(
                child: _PropertyGrid(
                  items: homeItems,
                  currentUserId: _uid.isEmpty ? 'guest' : _uid,
                  isAr: _isArabic,
                  bankColor: _brandPrimary,
                  isFav: (id) => _isFav(id),
                  onToggleFav: (id) => _toggleFav(id),
                  onOpenDetails: (p) => _openDetails(p),
                  activeHoldCount: (pid) => _activeReservationHoldCount(pid),
                  isReserved: (pid) => _isReservedByAnyone(pid),
                  reservedUntil: (pid) => _reservedUntil(pid),
                  reservedByName: (pid) => _reservedByName(pid),
                  onAddToCart: (p) => _addToCart(p),
                  // الرئيسية للاستكشاف: كالنسخة القديمة — لا تعديل/حذف من الشبكة (يُدار من «إعلاناتي»).
                  showEditDelete: false,
                  onEditProperty: _editProperty,
                  onDeleteProperty: (p) => _requestDeleteProperty(p),
                  timeAgo: _timeAgo,
                  canShowCartButton: _cartReservationFeaturesEnabled,
                  showListingQuickActions: false,
                  onCopyListingWebLink: _copyListingPublicLink,
                  suppressPublicOwnerIdentityOnCards: true,
                  onShareListingFromCard: _shareListingFromCard,
                  onHomeHideFromFeed: _isGuest
                      ? (p) async => _showLoginDialog()
                      : _onHomeHideProperty,
                  onHomeReportListing: _isGuest
                      ? (p) async => _showLoginDialog()
                      : _onHomeReportProperty,
                  homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
                  onRestorePropertyToHome:
                      _isGuest ? null : _onRestorePropertyToHome,
                  onWithdrawPropertyReport:
                      _isGuest ? null : _onWithdrawPropertyReport,
                  onPropertyViewsInteraction: (ctx, p, isOwner) {
                    final pubId = (p.publishedByMarketerId ?? '').trim();
                    final isPm = !_isGuest && _uid.isNotEmpty && pubId == _uid;
                    PropertyViewService.showSheet(
                      context: ctx,
                      sb: _sb,
                      propertyId: p.id,
                      viewsCount: p.views,
                      isOwner: isOwner,
                      isPublishingMarketer: isPm,
                      isAr: _isArabic,
                    );
                  },
                ),
              ));

    final showRequestsBelowListings = _homeFeedKind == HomeFeedKind.listings &&
        homeRequestsFiltered.isNotEmpty;
    final requestBlock = useMergedTimeline
        ? const SizedBox.shrink()
        : (((!showRequests && !showRequestsBelowListings) ||
                homeRequestsFiltered.isEmpty)
            ? const SizedBox.shrink()
            : _buildMarketRequestsHomeSection(
                homeRequestsFiltered,
                alwaysShowSectionTitle: showRequestsBelowListings,
              ));

    final listingsHiddenByFilters = showListings &&
        homeItems.isEmpty &&
        loadedPropertyRows > 0 &&
        _errorHome == null;
    final requestsHiddenByFilters = showRequests &&
        homeRequestsFiltered.isEmpty &&
        loadedRequestRows > 0 &&
        (_errorMarketRequests == null || _errorMarketRequests!.trim().isEmpty);

    final filterHintBanner = (listingsHiddenByFilters ||
            requestsHiddenByFilters)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.filter_alt_outlined,
                          color: cs.onSecondaryContainer,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isArabic
                                ? 'البيانات موجودة لكن الفلاتر أو الإخفاء المحلي قد يخفيان بعض النتائج.'
                                : 'Data is loaded, but filters or your local hide-from-home list may be hiding items.',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSecondaryContainer,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_hasActiveTopFilters ||
                        _hiddenPropertyIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (_hiddenPropertyIds.isNotEmpty)
                            Chip(
                              label: Text(
                                _isArabic
                                    ? 'إعلانات مخفية محلياً: ${_hiddenPropertyIds.length}'
                                    : 'Locally hidden listings: ${_hiddenPropertyIds.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (_hiddenMarketRequestIds.isNotEmpty)
                            Chip(
                              label: Text(
                                _isArabic
                                    ? 'طلبات مخفية: ${_hiddenMarketRequestIds.length}'
                                    : 'Hidden requests: ${_hiddenMarketRequestIds.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        AppHaptics.light();
                        _clearAllTopFilters();
                      },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        _isArabic ? 'إعادة ضبط الفلاتر' : 'Reset filters',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        filterHintBanner,
        if (suppressFullPageHomeListingError && !_isGuest) ...[
          Material(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: cs.onErrorContainer,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isArabic
                          ? 'تعذّر تحديث إعلانات العقارات؛ طلبات السوق تظهر أدناه. اضغط تحديث لإعادة المحاولة.'
                          : 'Property listings could not be refreshed; market requests are shown below. Tap refresh to retry.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onErrorContainer,
                        height: 1.35,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_retryWithOfflineHint(() async {
                      await _loadHome(force: true);
                    })),
                    child: Text(_isArabic ? 'تحديث' : 'Refresh'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        mixedBlock,
        grid,
        requestBlock,
      ],
    );

    return SingleChildScrollView(
      controller: onboardingScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: mainColumn,
    );
  }

  // =========================
  // Build my ads body (محسّنة)
  // =========================
  Widget _buildMyAdsHub() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(1);

    final hasImmediateMyPageData =
        _mine.isNotEmpty || _hasMarketingData || _hasOwnerRequestsData;
    if (_loadingMine && !hasImmediateMyPageData) {
      return const PropertyCardSkeletonList(count: 6, topPadding: 16);
    }

    if (_errorMine != null) {
      final offline = _isOfflineErrorStr(_errorMine);

      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              offline ? l10n.noInternetConnectionTitle : l10n.failedToLoadAds,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? l10n.ensureInternetThenRetry
                  : (_isArabic
                      ? 'تحقق من الاتصال ثم أعد المحاولة.'
                      : 'Check connection then retry.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          if (kDebugMode) Text(_errorMine!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(
                () => _loadMineAndOffers(force: true),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // التبويبات الكاملة (معلن/مسوّق) في user_dashboard.my_ads_hub.dart
    return _buildMyAdsMarketingHub(sortedMineForHub());
  }

  // =========================
  // Build «طلباتي»: إعلاناتي + طلبات السوق التي قدّمتها (بطاقات كالرئيسية)
  // =========================
  Widget _buildMySubmissionsBody() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(2);

    if (_isGuest) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'سجّل الدخول لعرض طلباتك'
                      : 'Log in to view your submissions',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _navigateToLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: Text(
                    l10n.loginNowLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final mineFiltered = _mine
        .where((p) =>
            p.ownerId == _uid &&
            ListingPermissionsHelper.shouldShowInPublicHome(p) &&
            ListingPermissionsHelper.shouldShowOnHomeDiscoveryCard(p))
        .toList()
      ..sort((a, b) => b.displayDate.compareTo(a.displayDate));
    final myReq = _marketHomeRequests
        .where((r) => r.requesterId == _uid && _uid.isNotEmpty)
        .toList();

    final loading = _loadingMine || (_uid.isNotEmpty && _loadingMarketRequests);

    if (loading) {
      return const PropertyCardSkeletonList(count: 6, topPadding: 16);
    }

    if (_errorMine != null && mineFiltered.isEmpty && myReq.isEmpty) {
      final offline = _isOfflineErrorStr(_errorMine);
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline ? l10n.noInternetConnectionTitle : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline ? l10n.ensureInternetThenRetry : _failLoadSubtitle(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(
                () async {
                  await _loadMineAndOffers(force: true);
                  await _loadMarketHomeRequests(force: true);
                },
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final entries = buildMixedHomeTimeline(mineFiltered, myReq);
    if (entries.isEmpty) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'لا توجد طلبات أو إعلانات مرسلة بعد'
                      : 'No submitted requests or listings yet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'أضف إعلانًا أو طلبًا عقاريًا، ثم ستظهر حالته وتفاصيله هنا.'
                      : 'Create a listing or a property request, then its status and details will appear here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _tabIndex = 0),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(l10n.navHome),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final marketErr = (_errorMarketRequests ?? '').trim();

    return ListView(
      controller: onboardingScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        if (marketErr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              color: cs.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 20, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isArabic
                            ? 'تعذّر تحديث بعض طلبات السوق: $marketErr'
                            : 'Some market requests could not refresh: $marketErr',
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        _HomeMixedTimeline(
          entries: entries,
          currentUserId: _uid.isEmpty ? 'guest' : _uid,
          isAr: _isArabic,
          bankColor: _brandPrimary,
          isFav: (id) => _isFav(id),
          onToggleFav: (id) => _toggleFav(id),
          onOpenDetails: (p) => _openDetails(p),
          activeHoldCount: (pid) => _activeReservationHoldCount(pid),
          isReserved: (pid) => _isReservedByAnyone(pid),
          reservedUntil: (pid) => _reservedUntil(pid),
          reservedByName: (pid) => _reservedByName(pid),
          onAddToCart: (p) => _addToCart(p),
          onEditProperty: _editProperty,
          onDeleteProperty: (p) => _requestDeleteProperty(p),
          timeAgo: _timeAgo,
          canShowCartButton: _cartReservationFeaturesEnabled,
          onPropertyViewsInteraction: (ctx, p, isOwner) {
            final pubId = (p.publishedByMarketerId ?? '').trim();
            final isPm = !_isGuest && _uid.isNotEmpty && pubId == _uid;
            PropertyViewService.showSheet(
              context: ctx,
              sb: _sb,
              propertyId: p.id,
              viewsCount: p.views,
              isOwner: isOwner,
              isPublishingMarketer: isPm,
              isAr: _isArabic,
            );
          },
          onCopyListingWebLink: _copyListingPublicLink,
          onOpenMarketRequest: _openMarketRequestDetail,
          onEditMarketRequest: _editMarketRequest,
          onSubmitMarketRequestOffer: _isGuest
              ? (r) => _showLoginDialog()
              : (r) => _openMarketRequestDetail(r, autoOpenSubmitOffer: true),
          marketRequestPriorityLabel: (r) =>
              _marketRequestPriorityL10nLabel(l10n, r.requestPriority),
          suppressPublicOwnerIdentityOnCards: true,
          onShareListingFromCard: _shareListingFromCard,
          onHomeHideFromFeed:
              _isGuest ? (p) async => _showLoginDialog() : _onHomeHideProperty,
          onHomeReportListing: _isGuest
              ? (p) async => _showLoginDialog()
              : _onHomeReportProperty,
          onHomeHideMarketRequest: _isGuest
              ? (r) async => _showLoginDialog()
              : _onHomeHideMarketRequest,
          onHomeReportMarketRequest:
              _isGuest ? null : _onHomeReportMarketRequest,
          homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
          onRestorePropertyToHome: _isGuest ? null : _onRestorePropertyToHome,
          onWithdrawPropertyReport: _isGuest ? null : _onWithdrawPropertyReport,
          onRestoreMarketRequest: _isGuest ? null : _onRestoreMarketRequest,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // =========================
  // Build favorites body
  // =========================
  Widget _buildFavoritesBody(List<Property> favItems) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(2);

    if (_loadingFavorites) {
      return const PropertyCardSkeletonList(count: 6, topPadding: 16);
    }

    if (_errorFavorites != null) {
      final offline = _isOfflineErrorStr(_errorFavorites);

      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline ? l10n.noInternetConnectionTitle : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline ? l10n.ensureInternetThenRetry : _failLoadSubtitle(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          if (kDebugMode) Text(_errorFavorites!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(
                () => _loadFavoritesList(force: true),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_isGuest) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'سجّل الدخول لعرض المفضلة'
                      : 'Login to view favorites',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: _navigateToLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      l10n.loginNowLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (favItems.isEmpty) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'لا توجد عناصر في المفضلة' : 'No favorites yet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _tabIndex = 0),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(
                    _isArabic ? 'استعرض الإعلانات' : 'Browse Listings',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _PropertyGrid(
      items: favItems,
      currentUserId: _uid.isEmpty ? 'guest' : _uid,
      isAr: _isArabic,
      bankColor: _brandPrimary,
      isFav: (id) => _isFav(id),
      onToggleFav: (id) => _toggleFav(id),
      onOpenDetails: (p) => _openDetails(p),
      activeHoldCount: (pid) => _activeReservationHoldCount(pid),
      isReserved: (pid) => _isReservedByAnyone(pid),
      reservedUntil: (pid) => _reservedUntil(pid),
      reservedByName: (pid) => _reservedByName(pid),
      onAddToCart: (p) => _addToCart(p),
      showEditDelete: true,
      onEditProperty: _editProperty,
      onDeleteProperty: (p) => _requestDeleteProperty(p),
      timeAgo: _timeAgo,
      canShowCartButton: _cartReservationFeaturesEnabled,
      showListingQuickActions: false,
      onCopyListingWebLink: _copyListingPublicLink,
      suppressPublicOwnerIdentityOnCards: true,
      onShareListingFromCard: _shareListingFromCard,
      onHomeHideFromFeed:
          _isGuest ? (p) async => _showLoginDialog() : _onHomeHideProperty,
      onHomeReportListing:
          _isGuest ? (p) async => _showLoginDialog() : _onHomeReportProperty,
      homeFeedShowsHiddenOnly: false,
      onRestorePropertyToHome: null,
      onWithdrawPropertyReport: null,
      onPropertyViewsInteraction: (ctx, p, isOwner) {
        final pubId = (p.publishedByMarketerId ?? '').trim();
        final isPm = !_isGuest && _uid.isNotEmpty && pubId == _uid;
        PropertyViewService.showSheet(
          context: ctx,
          sb: _sb,
          propertyId: p.id,
          viewsCount: p.views,
          isOwner: isOwner,
          isPublishingMarketer: isPm,
          isAr: _isArabic,
        );
      },
    );
  }

  // =========================
  // Build support hub (الدعم الفني + قنوات الإدارة — قريباً)
  // =========================
  Widget _buildSupportHubBody() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(4);

    if (_isGuest) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.lock_outline,
            size: 84,
            color: _brandPrimary.withOpacity(_op(180)),
          ),
          const SizedBox(height: 18),
          Text(
            _isArabic
                ? 'سجّل الدخول لعرض الدعم الفني'
                : 'Log in to access support',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: _navigateToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: Text(
                l10n.loginNowLabel,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: onboardingScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        ListTile(
          leading: Icon(Icons.forum_outlined, color: cs.primary),
          title: Text(
            l10n.openChatInboxButton,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            l10n.communicationHubChatsHint,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () {
            AppHaptics.light();
            unawaited(ChatNavigation.push(context, isAr: _isArabic));
          },
        ),
        const Divider(height: 1),
        DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: l10n.supportHubTechnicalTab),
                  Tab(text: l10n.supportHubAdminTab),
                  Tab(text: l10n.supportHubTicketsTab),
                ],
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.58,
                child: TabBarView(
                  children: [
                    SupportPage(
                      userId: _uid,
                      isAr: _isArabic,
                      bankColor: _brandPrimary,
                      wrapInScaffold: false,
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l10n.supportHubAdminSoon,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l10n.supportHubTicketsSoon,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================
  // Build cart body
  // =========================
  Widget _buildCartBody() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(3);

    if (_loadingCart) {
      return const CartRowSkeletonList(count: 5, topPadding: 16);
    }

    if (_errorCart != null) {
      final offline = _isOfflineErrorStr(_errorCart);

      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              offline ? l10n.noInternetConnectionTitle : l10n.failedToLoadCart,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? l10n.ensureInternetThenRetry
                  : (_isArabic
                      ? 'تحقق من الاتصال ثم أعد المحاولة.'
                      : 'Check connection then retry.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          if (kDebugMode) Text(_errorCart!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(
                () => _loadCart(force: true),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_uid.isEmpty) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'سجّل الدخول لعرض صفقاتك'
                      : 'Log in to view your deals',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: _navigateToLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      l10n.loginNowLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_cart.isEmpty &&
        _myPendingMarketOffersForCart.isEmpty &&
        _completedCart.isEmpty) {
      return ListView(
        controller: onboardingScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.handshake_outlined,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'لا توجد صفقات في قائمتك بعد'
                      : 'No deals in your list yet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (_isMarketingAccountType) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _isArabic
                          ? 'تقديم عرض على الإعلانات من الرئيسية مخصّص للمستخدمين غير المسوّقين. تابع أعمالك من «صفحتي» أو لوحة فريقك حسب صلاحياتك.'
                          : 'Submitting offers on listings from Home is for non-marketer accounts. Continue from My page or your team workspace based on permissions.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _tabIndex = 0),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(_isArabic ? 'اذهب للرئيسية' : 'Go to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: onboardingScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(12),
      itemCount: _cart.length +
          1 +
          (_myPendingMarketOffersForCart.isEmpty ? 0 : 1) +
          _myPendingMarketOffersForCart.length +
          (_completedCart.isEmpty ? 0 : 1 + _completedCart.length),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final introEnd = _myPendingMarketOffersForCart.isEmpty ? 1 : 2;
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              _isArabic
                  ? 'صفقاتي: عروضك/حجوزاتك على الإعلانات وطلبات السوق. تُعرض الأحدث أولاً، ولا يظهر زر تقديم عرض مرة أخرى بعد وجود عرض نشط.'
                  : 'My deals: your offers/holds on listings and market requests, newest first. Submit offer is hidden after an active offer exists.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          );
        }
        if (_myPendingMarketOffersForCart.isNotEmpty && i == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              AppLocalizations.of(context)!.cartMarketOffersSectionTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          );
        }
        final offerIdx = i - introEnd;
        if (offerIdx >= 0 && offerIdx < _myPendingMarketOffersForCart.length) {
          final o = _myPendingMarketOffersForCart[offerIdx];
          final rid = (o['market_request_id'] ?? '').toString();
          final st = (o['status'] ?? '').toString();
          final stLabel = _marketOfferStatusLabel(st);
          final price = o['price_offer'];
          final priceValue = _toDouble0(price);
          final msg = (o['message'] ?? '').toString().trim();
          final titleHint = (o['_request_title'] ?? '').toString().trim();
          MarketPropertyRequestRow? foundRow;
          for (final e in _marketHomeRequests) {
            if (e.id == rid) {
              foundRow = e;
              break;
            }
          }
          return _ReservationCard(
            bankColor: _brandPrimary,
            icon: Icons.local_offer_outlined,
            title: titleHint.isNotEmpty
                ? titleHint
                : (foundRow?.title ?? (_isArabic ? 'طلب عقاري' : 'Request')),
            subtitle: Text(
              _isArabic
                  ? 'عرضك على طلب عقاري'
                  : 'Your offer on a market request',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            chips: [
              _MiniChip(
                icon: Icons.verified_outlined,
                text: '${_isArabic ? 'الحالة' : 'Status'}: $stLabel',
                color: _brandPrimary,
              ),
              if (rid.trim().isNotEmpty)
                _MiniChip(
                  icon: Icons.copy_outlined,
                  text: _isArabic
                      ? 'طلب: ${DisplayIds.tenDigit(rid)}'
                      : 'Request: ${DisplayIds.tenDigit(rid)}',
                  color: _brandPrimary,
                  onTap: () => _copyPlainToClipboard(
                    rid.trim(),
                    _isArabic ? 'تم نسخ رقم الطلب' : 'Request ID copied',
                  ),
                ),
            ],
            priceTable: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _priceRow(
                  context,
                  label: _isArabic ? 'قيمة عرضك' : 'Your offer amount',
                  value: priceValue,
                  bold: true,
                ),
                if (msg.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _isArabic ? 'رسالتك' : 'Your message',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    msg,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
            primaryAction: _ReservationAction(
              kind: _ReservationActionKind.outlined,
              icon: Icons.open_in_new,
              label: _isArabic ? 'تتبع الطلب' : 'Track request',
              onPressed: rid.isEmpty
                  ? null
                  : () => unawaited(_openMarketRequestDetailById(rid)),
            ),
            secondaryAction: _ReservationAction(
              kind: _ReservationActionKind.outlined,
              icon: Icons.chat_bubble_outline,
              label: _isArabic ? 'دردشة' : 'Chat',
              onPressed: rid.isEmpty
                  ? null
                  : () => unawaited(_openMarketRequestDetailById(rid)),
            ),
            thirdAction: null,
            tryParseDt: _tryParseDt,
            timeAgo: _timeAgo,
            fmtDateTime: _fmtDateTime,
          );
        }
        final cartIdx = i - introEnd - _myPendingMarketOffersForCart.length;
        if (cartIdx >= _cart.length) {
          final completedIdx = cartIdx - _cart.length - 1;
          if (_completedCart.isNotEmpty && cartIdx == _cart.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                _isArabic ? 'صفقات منتهية' : 'Completed deals',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            );
          }
          if (completedIdx >= 0 && completedIdx < _completedCart.length) {
            return _buildCompletedPurchaseCard(_completedCart[completedIdx]);
          }
          return const SizedBox.shrink();
        }
        final r = _cart[cartIdx];
        final reservationId = (r['id'] ?? '').toString();
        final propertyId = (r['property_id'] ?? '').toString();
        final p = _cartPropertyById[propertyId];

        final basePrice = _toDouble0(r['base_price']);
        final platformFee = _toDouble0(r['platform_fee_amount']);
        final extraFee = _toDouble0(r['extra_fee_amount']);
        final total = _toDouble0(r['total_amount']);

        final createdAt = _tryParseDt(r['created_at']);
        final expiresAt = _tryParseDt(r['expires_at']);
        final createdText = createdAt == null
            ? (_isArabic ? 'غير معروف' : 'Unknown')
            : _timeAgo(createdAt, _isArabic);
        final expiresText = expiresAt == null
            ? (_isArabic ? 'غير معروف' : 'Unknown')
            : _fmtDateTime(expiresAt);

        return _ReservationCard(
          bankColor: _brandPrimary,
          icon: Icons.handshake_outlined,
          title: p?.title ?? (_isArabic ? 'عقار' : 'Property'),
          chips: [
            if (expiresAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _ReservationExpiryCountdown(
                  expiresAt: expiresAt,
                  isAr: _isArabic,
                ),
              ),
            _MiniChip(
              icon: Icons.schedule,
              text: _isArabic ? 'منذ: $createdText' : 'Since: $createdText',
              color: _brandPrimary,
            ),
            _MiniChip(
              icon: Icons.timer_outlined,
              text: _isArabic ? 'ينتهي: $expiresText' : 'Expires: $expiresText',
              color: _brandPrimary,
            ),
            if (reservationId.trim().isNotEmpty)
              _MiniChip(
                icon: Icons.copy_outlined,
                text: _isArabic
                    ? 'حجز: ${DisplayIds.plainNumericOrClean(reservationId)}'
                    : 'Hold: ${DisplayIds.plainNumericOrClean(reservationId)}',
                color: _brandPrimary,
                onTap: () => _copyPlainToClipboard(
                  reservationId.trim(),
                  _isArabic ? 'تم نسخ رقم الحجز' : 'Reservation ID copied',
                ),
              ),
          ],
          priceTable: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _priceRow(
                context,
                label: _isArabic ? 'السعر الأساسي' : 'Base price',
                value: basePrice,
              ),
              const SizedBox(height: 6),
              _priceRow(
                context,
                label: _isArabic ? 'عمولة المنصة (5%)' : 'Platform fee (5%)',
                value: platformFee,
              ),
              const SizedBox(height: 6),
              _priceRow(
                context,
                label: _isArabic ? 'رسوم إضافية (2.5%)' : 'Extra fee (2.5%)',
                value: extraFee,
              ),
              const Divider(height: 16),
              _priceRow(
                context,
                label: _isArabic ? 'الإجمالي' : 'Total',
                value: total,
                bold: true,
              ),
            ],
          ),
          primaryAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.open_in_new,
            label: _isArabic ? 'فتح الإعلان' : 'Open listing',
            onPressed: p == null ? null : () => _openDetails(p),
          ),
          secondaryAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.chat_bubble_outline,
            label: _isArabic ? 'دردشة' : 'Chat',
            onPressed: () {
              final t =
                  p?.title ?? (_isArabic ? 'دردشة الحجز' : 'Reservation chat');
              _openChat(
                mode: 'reservation',
                propertyId: propertyId,
                reservationId: reservationId,
                title: t,
              );
            },
          ),
          thirdAction: _ReservationAction(
            kind: _ReservationActionKind.filledDanger,
            icon: Icons.close,
            label: _isArabic ? 'إلغاء' : 'Cancel',
            onPressed: () => _cancelReservationFromCart(r),
          ),
          fourthAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.verified_outlined,
            label: _isArabic ? 'إتمام الشراء' : 'Complete purchase',
            onPressed:
                p == null ? null : () => _completeSaleFromCart(propertyId),
          ),
          tryParseDt: _tryParseDt,
          timeAgo: _timeAgo,
          fmtDateTime: _fmtDateTime,
        );
      },
    );
  }

  Widget _buildCompletedPurchaseCard(Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    final reservationId = (r['id'] ?? '').toString();
    final propertyId = (r['property_id'] ?? '').toString();
    final p =
        _completedCartPropertyById[propertyId] ?? _cartPropertyById[propertyId];
    final basePrice = _toDouble0(r['base_price']);
    final total = _toDouble0(r['total_amount']);
    final completedAt =
        _tryParseDt(r['updated_at']) ?? _tryParseDt(r['created_at']);
    final completedText = completedAt == null
        ? (_isArabic ? 'غير معروف' : 'Unknown')
        : _timeAgo(completedAt, _isArabic);

    return _ReservationCard(
      bankColor: _brandPrimary,
      icon: Icons.verified_outlined,
      title: p?.title ?? (_isArabic ? 'إعلان مكتمل' : 'Completed listing'),
      subtitle: Text(
        _isArabic
            ? 'صفقة منتهية منذ: $completedText'
            : 'Completed deal since: $completedText',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
      chips: [
        _MiniChip(
          icon: Icons.check_circle_outline,
          text: _isArabic ? 'مكتملة' : 'Completed',
          color: Colors.green.shade700,
        ),
        if (reservationId.trim().isNotEmpty)
          _MiniChip(
            icon: Icons.copy_outlined,
            text: _isArabic
                ? 'صفقة: ${DisplayIds.plainNumericOrClean(reservationId)}'
                : 'Deal: ${DisplayIds.plainNumericOrClean(reservationId)}',
            color: _brandPrimary,
            onTap: () => _copyPlainToClipboard(
              reservationId.trim(),
              _isArabic ? 'تم نسخ رقم الصفقة' : 'Deal ID copied',
            ),
          ),
      ],
      priceTable: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _priceRow(
            context,
            label: _isArabic ? 'سعر الإعلان' : 'Listing price',
            value: basePrice,
          ),
          const SizedBox(height: 6),
          _priceRow(
            context,
            label: _isArabic ? 'إجمالي الصفقة' : 'Deal total',
            value: total,
            bold: true,
          ),
        ],
      ),
      primaryAction: _ReservationAction(
        kind: _ReservationActionKind.outlined,
        icon: Icons.open_in_new,
        label: _isArabic ? 'التفاصيل' : 'Details',
        onPressed: p == null ? null : () => _openDetails(p),
      ),
      secondaryAction: _ReservationAction(
        kind: _ReservationActionKind.outlined,
        icon: Icons.campaign_outlined,
        label: _isArabic ? 'إعادة تسويقه' : 'Relist',
        onPressed: p == null
            ? null
            : () => unawaited(_relistCompletedPropertyFromCart(p)),
      ),
      thirdAction: _ReservationAction(
        kind: _ReservationActionKind.outlined,
        icon: Icons.chat_bubble_outline,
        label: _isArabic ? 'دردشة' : 'Chat',
        onPressed: () {
          final t = p?.title ?? (_isArabic ? 'دردشة الصفقة' : 'Deal chat');
          _openChat(
            mode: 'reservation',
            propertyId: propertyId,
            reservationId: reservationId,
            title: t,
          );
        },
      ),
      tryParseDt: _tryParseDt,
      timeAgo: _timeAgo,
      fmtDateTime: _fmtDateTime,
    );
  }

  // =========================
  // Build offers body
  // =========================
  Widget _buildOffersBody() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loadingOffers) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: const [
          SizedBox(height: 120),
          Center(child: AppLogoLoading()),
          SizedBox(height: 120),
        ],
      );
    }

    if (_errorOffers != null) {
      final offline = _isOfflineErrorStr(_errorOffers);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              offline
                  ? l10n.noInternetConnectionTitle
                  : l10n.failedToLoadReservations,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? l10n.ensureInternetThenRetry
                  : (_isArabic
                      ? 'تحقق من الاتصال ثم أعد المحاولة.'
                      : 'Check connection then retry.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          if (kDebugMode) Text(_errorOffers!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _retryWithOfflineHint(
                () => _loadMineAndOffers(force: true),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_uid.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'سجّل الدخول لعرض الحجوزات'
                      : 'Login to view reservations',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: _navigateToLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      l10n.loginNowLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_offers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 84,
                  color: _brandPrimary.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic
                      ? 'لا توجد حجوزات على إعلاناتك'
                      : 'No reservations on your listings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => _retryWithOfflineHint(
                    () => _loadMineAndOffers(force: true),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.refreshLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(12),
      itemCount: _offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _offers[i];
        final reservationId = (r['id'] ?? '').toString();
        final propertyId = (r['property_id'] ?? '').toString();
        final p = _myPropertyById[propertyId];

        final basePrice = _toDouble0(r['base_price']);
        final platformFee = _toDouble0(r['platform_fee_amount']);
        final extraFee = _toDouble0(r['extra_fee_amount']);
        final total = _toDouble0(r['total_amount']);

        final createdAt = _tryParseDt(r['created_at']);
        final expiresAt = _tryParseDt(r['expires_at']);
        final createdText = createdAt == null
            ? (_isArabic ? 'غير معروف' : 'Unknown')
            : _timeAgo(createdAt, _isArabic);
        final expiresText = expiresAt == null
            ? (_isArabic ? 'غير معروف' : 'Unknown')
            : _fmtDateTime(expiresAt);

        final status = (r['status'] ?? '').toString().trim();
        final buyerName = (r['reserved_by_name'] ?? '').toString().trim();
        final buyerLabel = buyerName.isNotEmpty
            ? buyerName
            : ((r['user_id'] ?? 'N/A').toString());
        final buyerPhone = (r['reserved_by_phone'] ?? '').toString().trim();
        final buyerCity = (r['reserved_by_city'] ?? '').toString().trim();
        final buyerAccount =
            (r['reserved_by_account_type'] ?? '').toString().trim();
        final buyerLicense =
            (r['reserved_by_license_no'] ?? '').toString().trim();

        return _ReservationCard(
          bankColor: _brandPrimary,
          icon: Icons.receipt_long_outlined,
          title: p?.title ?? (_isArabic ? 'إعلان' : 'Listing'),
          subtitle: Text(
            _isArabic ? 'منذ: $createdText' : 'Time: $createdText',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          chips: [
            _MiniChip(
              icon: Icons.tag,
              text: _isArabic
                  ? 'الحالة: ${status.isEmpty ? 'غير محدد' : status}'
                  : 'Status: ${status.isEmpty ? 'N/A' : status}',
              color: _brandPrimary,
            ),
            _MiniChip(
              icon: Icons.person_outline,
              text: _isArabic
                  ? 'الحاجز: $buyerLabel'
                  : 'Reserved by: $buyerLabel',
              color: _brandPrimary,
            ),
            if (buyerCity.isNotEmpty)
              _MiniChip(
                icon: Icons.location_city_outlined,
                text: _isArabic ? 'المدينة: $buyerCity' : 'City: $buyerCity',
                color: _brandPrimary,
              ),
            if (buyerPhone.isNotEmpty)
              _MiniChip(
                icon: Icons.phone_outlined,
                text: buyerPhone,
                color: _brandPrimary,
                onTap: () => _copyPlainToClipboard(
                  buyerPhone,
                  _isArabic ? 'تم نسخ رقم الجوال' : 'Phone copied',
                ),
              ),
            if (buyerAccount.isNotEmpty)
              _MiniChip(
                icon: Icons.badge_outlined,
                text: _isArabic
                    ? 'نوع الحساب: $buyerAccount'
                    : 'Account: $buyerAccount',
                color: _brandPrimary,
              ),
            if (buyerLicense.isNotEmpty)
              _MiniChip(
                icon: Icons.verified_user_outlined,
                text: _isArabic
                    ? 'الرخصة: $buyerLicense'
                    : 'License: $buyerLicense',
                color: _brandPrimary,
              ),
            _MiniChip(
              icon: Icons.timer_outlined,
              text: _isArabic ? 'ينتهي: $expiresText' : 'Expires: $expiresText',
              color: _brandPrimary,
            ),
            if (reservationId.trim().isNotEmpty)
              _MiniChip(
                icon: Icons.copy_outlined,
                text: _isArabic
                    ? 'حجز: ${DisplayIds.plainNumericOrClean(reservationId)}'
                    : 'Hold: ${DisplayIds.plainNumericOrClean(reservationId)}',
                color: _brandPrimary,
                onTap: () => _copyPlainToClipboard(
                  reservationId.trim(),
                  _isArabic ? 'تم نسخ رقم الحجز' : 'Reservation ID copied',
                ),
              ),
          ],
          priceTable: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _priceRow(
                context,
                label: _isArabic ? 'السعر الأساسي' : 'Base price',
                value: basePrice,
              ),
              const SizedBox(height: 6),
              _priceRow(
                context,
                label: _isArabic ? 'عمولة المنصة (5%)' : 'Platform fee (5%)',
                value: platformFee,
              ),
              const SizedBox(height: 6),
              _priceRow(
                context,
                label: _isArabic ? 'رسوم إضافية (2.5%)' : 'Extra fee (2.5%)',
                value: extraFee,
              ),
              const Divider(height: 16),
              _priceRow(
                context,
                label: _isArabic ? 'الإجمالي' : 'Total',
                value: total,
                bold: true,
              ),
            ],
          ),
          primaryAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.open_in_new,
            label: _isArabic ? 'فتح الإعلان' : 'Open listing',
            onPressed: p == null ? null : () => _openDetails(p),
          ),
          secondaryAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.chat_bubble_outline,
            label: _isArabic ? 'دردشة' : 'Chat',
            onPressed: () {
              final t =
                  p?.title ?? (_isArabic ? 'دردشة الحجز' : 'Reservation chat');
              _openChat(
                mode: 'reservation',
                propertyId: propertyId,
                reservationId: reservationId,
                title: t,
              );
            },
          ),
          thirdAction: null,
          tryParseDt: _tryParseDt,
          timeAgo: _timeAgo,
          fmtDateTime: _fmtDateTime,
        );
      },
    );
  }
}

/// إعادة بناء اللوحة عند تغيّر كدسة [Navigator] الداخلي لإخفاء [AppBar] الخارجي عند وجود صفحة فوق الجذر.
class _DashboardBodyNavObserver extends NavigatorObserver {
  _DashboardBodyNavObserver({required this.onChange});
  final VoidCallback onChange;

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange());
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _schedule();
}
