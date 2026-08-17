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

  /// تحديد اللغة العربية — من المُنبّه الحي حتى تُطبَّق من الإعدادات فوراً.
  bool get isAr => langNotifier.value != 'en';

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard>
    with TickerProviderStateMixin, MarketingStateMixin {
  // =========================
  // ✅ Loading watchdog (UI only)
  // =========================
  DateTime? _homeLoadingSince;
  DateTime? _marketRequestsLoadingSince;
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
  static const int homeFeedFetchLimit = 48;
  static const int homeFeedFetchLimitWeb = 24;
  static const int marketHomeRequestsFetchLimit = 40;
  static const int marketHomeRequestsFetchLimitWeb = 20;
  static const int minePropertiesFetchLimit = 200;
  static const int minePropertiesFetchLimitWeb = 80;
  static const int mapDiscoveryFetchLimit = 500;

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
      if (!mounted) return;
      // بعد push/pop: حدّث عنوان الشريط من أعلى مسار الجسم.
      _syncNestedShellTitleFromNavigator();
    },
  );

  /// عناوين المسارات المضمّنة تحت التحية (إدارتي / إعدادات / …).
  final List<String?> _nestedTitleStack = <String?>[];

  Offset? _dashboardSwipeStart;
  bool _swipeBackEnabled = true;
  bool _edgeOnlySwipeBack = false;
  bool _keyboardBackEnabled = true;

  // =========================
  // Auth + reload guards
  // =========================
  StreamSubscription<AuthState>? _authSub;
  Timer? _orgJoinBadgeTimer;
  int _orgPendingJoinCount = 0;
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

  /// تمييز مؤقت لشريط التنقل أثناء شورتز/إدارتي (لا يُعاد للرئيسية بصرياً).
  int? _bottomNavTransientIndex;

  /// ويب: تبويبات زِيرت + قائمة أبناء ثابتة لـ [IndexedStack].
  /// عند تبديل التبويب فقط نُعيد نفس مثيلات الـ Widget فلا تُعاد بناء الرئيسية (تجمّد).
  /// عند تغيّر بيانات الفيد نُحدّث الأبناء فتظهر البطاقات (كاش قديم كان يُبقي الرئيسية فارغة).
  final Set<int> _webVisitedTabs = <int>{0};
  final Set<int> _webMaterializedTabs = <int>{};
  List<Widget>? _webTabChildren;
  int _webTabChildrenFeedSig = -1;
  int _webTabChildrenHubSig = -1;
  int _webBuiltActiveTab = -1;
  String? _lastWebHomePaintSig;

  /// يُستخدم سابقاً لتشخيص «كتالوج ملكك فقط» — أُزيل مسار الإظهار الاحتياطي.
  // ignore: unused_field
  int _webSelfOwnedPoolLogLen = -1;

  /// تبويب «التعاقد» للمسوّق: 0 = تمت الموافقة، 1 = بانتظار التعاقد.
  int _marketerContractHubSegment = 0;

  /// تمييز بطاقة طلب في «صفحتي» بعد فتح إشعار (يُفرغ تلقائياً).
  String? _hubHighlightRequestId;

  /// مفاتيح بطاقات «صفحتي» لـ [Scrollable.ensureVisible] بعد إشعار FCM.
  final Map<String, GlobalKey> _hubRequestCardKeys = {};

  GlobalKey _hubCardKeyForRequest(String requestId) {
    final id = requestId.trim();
    if (id.isEmpty) return GlobalKey();
    return _hubRequestCardKeys.putIfAbsent(id, GlobalKey.new);
  }

  void _scrollHubCardIntoView(String requestId, {int attempt = 0}) {
    final id = requestId.trim();
    if (id.isEmpty || !mounted) return;
    final box = _hubRequestCardKeys[id]?.currentContext;
    if (box != null) {
      Scrollable.ensureVisible(
        box,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        alignment: 0.12,
      );
      return;
    }
    if (attempt > 14) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(
        Duration(milliseconds: 60 + attempt * 35),
        () => _scrollHubCardIntoView(id, attempt: attempt + 1),
      );
    });
  }

  void _setMarketerContractHubSegment(int v) {
    if (_marketerContractHubSegment == v) return;
    setState(() => _marketerContractHubSegment = v);
  }

  bool _showDashboardOnboarding = false;
  /// إعادة الجولة من الإعدادات فقط — بعدها يُعرض اختيار الألوان مرة.
  bool _offerAccentAfterTourReplay = false;
  String _searchQuery = '';
  String _cityFilter = 'all';
  String _regionFilter = '';
  String _governorateFilter = '';
  String _districtFilter = '';
  bool _didApplyPreferredExploreCity = false;
  PropertyType? _typeFilter;

  /// بيع / إيجار (مجمّع) / مزاد / استثمار — يطابق [PropertyListingDisplay.matchesPurposeFilter].
  String? _purposeFilter;

  /// طلبات مدفوعة / ذات أولوية فقط (إطار ذهبي + أعلى القائمة).
  bool _paidPriorityOnlyFilter = false;

  /// `null` = الكل، `true` = مفروش فقط، `false` = غير مفروش (يشمل غير المحدد).
  bool? _furnishedFilter;
  double? _priceMinFilter;
  double? _priceMaxFilter;
  double? _areaMinFilter;
  double? _areaMaxFilter;
  HomeFeedKind _homeFeedKind = HomeFeedKind.all;
  String _sortBy = 'latest';
  Timer? _debounce;
  Timer? _advancedSearchDraftTimer;
  Timer? _appAudiencePollTimer;
  Timer? _presenceHeartbeatTimer;

  /// تقدير «متصل الآن» من الخادم (get_app_audience_stats.online_now).
  int? _appAudienceOnlineApprox;

  /// True while debounced search text is catching up to the applied query.
  bool _feedFilterBusy = false;

  /// عنوان مختصر لصفحة الجسم الداخلي (إعدادات، اشتراكات، …) عند فتحها فوق جذر اللوحة.
  String? _nestedShellTitle;

  /// إخفاء الشريط السفلي أثناء التمرير للأسفل (يُعاد عند التوقف أو التمرير للأعلى).
  bool _bottomNavSlideVisible = true;

  /// للضيف: عرض رقم الإصدار في شريط الرئيسية.
  String _packageVersionLine = '';

  /// إعلانات/طلبات أخفاها المستخدم محلياً (تظهر عند تفعيل شريط «المخفية»).
  bool _homeShowHiddenOnly = false;
  Set<String> _hiddenPropertyIds = {};
  Set<String> _hiddenMarketRequestIds = {};
  Set<String> _hiddenCompletedDealPropertyIds = {};

  /// يمنع إعادة فلترة الرئيسية في كل `build` — يُحدَّث عند تغيّر المدخلات فقط.
  int _homeFeedDataEpoch = 0;
  int _nestedDashboardFeedCacheBuiltKey = -1;
  int _nestedDashboardHomePropertyPoolSize = 0;
  List<Property> _nestedDashboardHomeItems = const [];
  List<MarketPropertyRequestRow> _nestedDashboardHomeRequests = const [];
  int? _nestedDashboardMixedHomeCount;
  int _nestedDashboardMySubmissionsCount = 0;
  List<HomeMixedFeedEntry> _nestedDashboardMixedEntries = const [];
  ({int server, int filtered, int shown}) _nestedDashboardPipelineL =
      (server: 0, filtered: 0, shown: 0);
  ({int server, int filtered, int shown}) _nestedDashboardPipelineR =
      (server: 0, filtered: 0, shown: 0);
  bool _nestedDashboardFeedCacheRebuildPending = false;

  /// يمنع تداخل استدعاءات مباشرة لـ [_runNestedDashboardFeedCacheRebuildAsync].
  bool _nestedDashboardFeedCacheRebuildRunning = false;
  Timer? _feedCacheRebuildDebounce;

  bool _homeFeedPaintPending = false;
  final List<VoidCallback> _homeFeedPendingMutations = [];

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isArabic => widget.isAr;
  String get _lang => widget.lang;
  String get _uid => _sb.auth.currentUser?.id ?? '';
  @override
  bool get _isGuest {
    // مصدر الحقيقة: جلسة Supabase. prefs الضيف المتأخرة كانت تُصنّف المستخدم ضيفاً
    // رغم وجود uid → مسح الفيد + auth.reload skipped + إعادة إقلاع مزدوجة.
    final authUid = _sb.auth.currentUser?.id ?? '';
    if (authUid.isNotEmpty) return false;
    try {
      return context.read<AppSession>().isGuest;
    } catch (_) {
      return true;
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
        _regionFilter.trim().isNotEmpty ||
        _governorateFilter.trim().isNotEmpty ||
        _districtFilter.trim().isNotEmpty ||
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
    final pipeL = _nestedDashboardPipelineL;
    final pipeR = _nestedDashboardPipelineR;

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

  void _markDashboardFeedDirty() {
    _nestedDashboardFeedCacheBuiltKey = -1;
    // ويب: لا تهدم IndexedStack ولا تصفّر feedSig (تصفيره كان يفرض home.paint دائماً).
    if (kIsWeb) {
      _scheduleNestedDashboardFeedCacheRebuild();
      return;
    }
    _webTabChildren = null;
    _webTabChildrenFeedSig = -1;
    _webMaterializedTabs.clear();
  }

  void _flushHomeFeedMutations() {
    if (!mounted) return;
    _homeFeedPaintPending = false;
    final pending = List<VoidCallback>.from(_homeFeedPendingMutations);
    _homeFeedPendingMutations.clear();
    if (pending.isEmpty) return;
    _nestedDashboardFeedCacheBuiltKey = -1;
    if (!kIsWeb) {
      _webTabChildren = null;
      _webTabChildrenFeedSig = -1;
      _webMaterializedTabs.clear();
    }
    setState(() {
      for (final mutate in pending) {
        mutate();
      }
    });
    // جدول إعادة بناء واحدة بعد الدفعة — لا تستدعِها قبل setState مع عواصف متداخلة.
    if (kIsWeb) {
      _scheduleNestedDashboardFeedCacheRebuild();
    }
  }

  /// على الويب: طبّق طابور الرئيسية فوراً (بعد الجلب) حتى لا يبقى `_all` فارغاً
  /// بينما التشخيص والفيد يعملان على بيانات قديمة → بانر «الفلاتر تخفي النتائج».
  void _flushHomeFeedMutationsSync() {
    if (!kIsWeb || _homeFeedPendingMutations.isEmpty) return;
    _flushHomeFeedMutations();
  }

  /// على الويب: دمج تحديثات الرئيسية المتتالية في إطار واحد.
  void _ssHomeFeed(VoidCallback fn) {
    if (!mounted) return;
    if (kIsWeb) {
      _homeFeedPendingMutations.add(fn);
      if (!_homeFeedPaintPending) {
        _homeFeedPaintPending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _flushHomeFeedMutations();
        });
      }
      return;
    }
    _markDashboardFeedDirty();
    _ss(fn);
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
    String? marketRequestId,
    ConversationKind? kind,
    String? counterpartyId,
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
      _bottomNavSlideVisible = true;
    });
    // داخل جسم اللوحة — يبقى الشريط السفلي (مثل الاشتراكات/المدفوعات).
    unawaited(
      _pushBody<void>(
        ChatNavigation.materialRoute(
          isAr: _isArabic,
          embedInParentDashboardShell: true,
          propertyId: propertyId,
          reservationId: reservationId,
          title: title,
          marketRequestId: marketRequestId,
          kind: kind,
          counterpartyId: counterpartyId,
        ),
      ),
    );
  }

  void _showLoginDialog() {
    if (_isGuest) {
      unawaited(_showGuestAuthRequiredFromSheet());
      return;
    }
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

  Future<void> _showGuestAuthRequiredFromSheet() async {
    final res = await showGuestAuthRequiredSheet(
      context: context,
      isAr: _isArabic,
    );
    if (!mounted || res == null) return;
    if (res == GuestAuthRequiredResult.login) {
      _navigateToLogin();
    } else {
      await Navigator.of(context, rootNavigator: true).pushNamed('/register');
    }
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

  void _showNotification(
    String title,
    String message, {
    bool isError = false,
    bool playSound = false,
  }) {
    if (playSound) {
      playInAppNotificationChime();
    }
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
            hideLeadingBecauseShellHasBack: true,
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

    if (deepRoute == InAppDeepRoutes.subscriptionsHub ||
        deepRoute == 'subscriptions_hub') {
      await _markInAppNotifReadAndRefresh(notif);
      if (!mounted) return;
      final at = from(['account_type']).trim();
      final acct = at.isEmpty ? _accountType : at;
      final oid = await _orgUnitIdForSubscriptionsMenu();
      if (!mounted) return;
      final embed = MediaQuery.sizeOf(context).width >= 580;
      await _pushBody<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/dashboard/subscriptions'),
          builder: (_) => SubscriptionsRootScreen(
            lang: widget.lang,
            accountType: acct,
            organizationId: oid,
            initialIndex: 2,
            embedAppBar: embed,
          ),
        ),
      );
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

    final explicitMyAdsTab = int.tryParse(
      (data[WorkflowNotificationKeys.myAdsSubTab] ?? '').toString().trim(),
    );

    final ownsRequest = requestId.isNotEmpty &&
        _ownerListingRequests.any((r) {
          final id = (r['id'] ?? r['request_id'] ?? '').toString().trim();
          return id.isNotEmpty && id == requestId;
        });
    final wantsPublisher =
        role == 'owner' || role == 'publisher' || ownsRequest;

    if (_usesMarketerMyPageHub &&
        wantsPublisher &&
        (_hasOwnerRequestsData || ownsRequest || role == 'owner')) {
      setState(() => _setMarketerPublisherHubMode(1));
      unawaited(_loadOwnerRequestsBuckets(force: true, silent: true));
      _ensureSubTabControllers();
      final idx = explicitMyAdsTab ?? _ownerSubTabFromStatus(status);
      if (_ownerTabsCtrl != null && idx >= 0 && idx < _ownerTabsCtrl!.length) {
        _ownerTabsCtrl!.animateTo(idx);
      }
    } else if (_isMarketerRole || role == 'marketer') {
      if (_usesMarketerMyPageHub) {
        setState(() => _setMarketerPublisherHubMode(0));
      }
      final idx = explicitMyAdsTab ?? _marketerSubTabFromStatus(status);
      if (_marketerTabsCtrl != null &&
          idx >= 0 &&
          idx < _marketerTabsCtrl!.length) {
        _marketerTabsCtrl!.animateTo(idx);
      }
    } else {
      final idx = explicitMyAdsTab ?? _ownerSubTabFromStatus(status);
      if (_ownerTabsCtrl != null && idx >= 0 && idx < _ownerTabsCtrl!.length) {
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
    // FCM / لوحة: عند وجود معرّف طلب وعقار، مرّر للتبويب ثم مرّر للبطاقة حتى لو لم يُرسل my_ads_sub_tab.
    final focusHubRequestCard = requestId.isNotEmpty && propertyId.isNotEmpty;
    if (focusHubRequestCard) {
      setState(() => _hubHighlightRequestId = requestId);
      MarketingWorkflowHub.requestHubHighlight(requestId);
      _scrollHubCardIntoView(requestId);
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() {
          if (_hubHighlightRequestId == requestId) {
            _hubHighlightRequestId = null;
          }
        });
        if (MarketingWorkflowHub.hubHighlightRequestId.value == requestId) {
          MarketingWorkflowHub.hubHighlightRequestId.value = null;
        }
      });
      return;
    }
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

    Property? p =
        _propertyCache[propertyId] ?? _propertyFromLocalCaches(propertyId);

    if (p == null) {
      await _loadHome(force: true);
      await _loadMineAndOffers(force: true);
      p = _propertyCache[propertyId] ?? _propertyFromLocalCaches(propertyId);
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
  List<Map<String, dynamic>> _myArchivedMarketOffersForCart =
      <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get _visibleArchivedMarketOffersForCart {
    return _myArchivedMarketOffersForCart.where((o) {
      final id = (o['id'] ?? '').toString().trim();
      if (id.isEmpty) return false;
      return !_hiddenCartMarketOfferIds.contains(id);
    }).toList(growable: false);
  }

  bool _marketOfferLostToOtherPartner(Map<String, dynamic> o) {
    final oid = (o['id'] ?? '').toString().trim();
    final selected = (o['_selected_offer_id'] ?? '').toString().trim();
    final reqSt = (o['_request_status'] ?? '').toString().toLowerCase().trim();
    final st = (o['status'] ?? '').toString().toLowerCase().trim();
    if (selected.isNotEmpty && oid.isNotEmpty && selected != oid) {
      return reqSt == 'completed' ||
          reqSt == 'closed' ||
          st == 'lost' ||
          st == 'rejected' ||
          st == 'declined' ||
          st == 'superseded';
    }
    return st == 'lost' || st == 'rejected' || st == 'declined';
  }

  Set<String> _marketRequestIdsHiddenAfterTwoWithdrawals = <String>{};
  Set<String> _hiddenCartMarketOfferIds = <String>{};
  List<MarketPropertyRequestRow> _myMarketSubmissions =
      <MarketPropertyRequestRow>[];
  bool _loadingMyMarketSubmissions = false;
  bool _expiringPromptShown = false;
  String? _ownerHubInlineOfferBusyId;

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
    _markDashboardFeedDirty();
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
    _markDashboardFeedDirty();
    setState(() => _cityFilter = value);
  }

  void _setSortBy(String v) {
    if (!mounted) return;

    _markDashboardFeedDirty();
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
    _markDashboardFeedDirty();
    setState(() {
      _typeFilter = value;
    });
  }

  void _setPurposeFilter(String? value) {
    if (!mounted) return;
    _markDashboardFeedDirty();
    setState(() => _purposeFilter = value);
  }

  void _setHomeFeedKind(HomeFeedKind value) {
    if (!mounted) return;
    // ضغطة ثانية على نفس التبويب تُنهي الفلترة وتعود للكل.
    final next = _homeFeedKind == value ? HomeFeedKind.all : value;
    if (next == _homeFeedKind) return;
    // ويب: يجب إبطال كاش الرئيسية — وإلا تبقى البطاقات القديمة (ضيف ومستخدم).
    _markDashboardFeedDirty();
    setState(() => _homeFeedKind = next);
  }

  void _clearNearestMode() {
    if (!mounted) return;
    _markDashboardFeedDirty();
    setState(() {
      _sortBy = 'latest';
      _cityFilter = 'all';
    });
  }

  void _clearAllTopFilters() {
    _debounce?.cancel();
    _advancedSearchDraftTimer?.cancel();
    _inlineSearchCtrl.clear();
    if (!mounted) return;
    _markDashboardFeedDirty();
    setState(() {
      _searchQuery = '';
      _cityFilter = 'all';
      _typeFilter = null;
      _purposeFilter = null;
      _furnishedFilter = null;
      _paidPriorityOnlyFilter = false;
      _priceMinFilter = null;
      _priceMaxFilter = null;
      _areaMinFilter = null;
      _areaMaxFilter = null;
      _homeFeedKind = HomeFeedKind.all;
      _sortBy = 'latest';
      _homeShowHiddenOnly = false;
      _myLat = null;
      _myLng = null;
      _feedFilterBusy = false;
    });
    unawaited(_clearAdvSearchDraftPrefs());
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

  Future<void> _refreshAppAudienceOnlineApprox() async {
    try {
      final key = await PresenceHeartbeatService.clientKey(_sb);
      final raw = await _sb.rpc(
        'get_app_audience_stats',
        params: {'p_exclude_client_key': key},
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      final n = (raw is Map) ? (raw['online_now'] as num?)?.toInt() : null;
      setState(() => _appAudienceOnlineApprox = n);
    } catch (_) {
      // توافق: إن لم تُنشر الوسيطة بعد.
      try {
        final raw = await _sb
            .rpc('get_app_audience_stats')
            .timeout(const Duration(seconds: 6));
        if (!mounted) return;
        final n = (raw is Map) ? (raw['online_now'] as num?)?.toInt() : null;
        setState(() => _appAudienceOnlineApprox = n);
      } catch (_) {}
    }
  }

  /// عناوين شركاء متصلين حسب المنصة/العرض.
  String _audiencePartnersTitle({required bool isAr}) {
    final wideDesktopWeb = kIsWeb &&
        MediaQuery.sizeOf(context).width >= 600 &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (wideDesktopWeb) {
      return isAr ? 'الشركاء المتصلين' : 'Connected partners';
    }
    if (kIsWeb) {
      return isAr ? 'الشركاء المتصلين بالويب' : 'Partners connected on web';
    }
    return isAr ? 'الشركاء المتصلين بالتطبيق' : 'Partners connected in the app';
  }

  String _audienceOnlineNowLabel({required bool isAr}) {
    return isAr ? 'المتصلون الآن' : 'Online now';
  }

  String _audienceGuestsLabel({required bool isAr}) {
    return isAr ? 'الشركاء المتصلين كضيف' : 'Guests connected now';
  }

  Future<void> _exitAdvancedSearchModeFull() async {
    _debounce?.cancel();
    _advancedSearchDraftTimer?.cancel();
    _inlineSearchCtrl.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _cityFilter = 'all';
      _typeFilter = null;
      _purposeFilter = null;
      _furnishedFilter = null;
      _paidPriorityOnlyFilter = false;
      _priceMinFilter = null;
      _priceMaxFilter = null;
      _areaMinFilter = null;
      _areaMaxFilter = null;
      _homeFeedKind = HomeFeedKind.all;
      _sortBy = 'latest';
      _homeShowHiddenOnly = false;
      _feedFilterBusy = false;
    });
    await _clearAdvSearchDraftPrefs();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _openSearchFiltersSheet() async {
    final cs = Theme.of(context).colorScheme;

    // ويب: لا تفكّ مدن JSON عند فتح الورقة — كان يجمّد الواجهة.
    await Future<void>.delayed(Duration.zero); // let tap complete
    if (!mounted) return;

    final sheet = _DashboardAdvDraftHolder.fromState(this);
    await sheet.mergePersistedIfAny();
    if (!mounted) return;

    if (kIsWeb) {
      unawaited(
          Future<void>.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;
        await _loadCities(includeExtra: false);
      }));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AqarBrandColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final sheetScrollCtrl = ScrollController();

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
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AqarBrandColors.primary.withOpacity(0.12)
                        : cs.surfaceContainerHighest.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? AqarBrandColors.primary.withOpacity(0.45)
                          : AqarBrandColors.border.withOpacity(0.85),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: selected
                            ? AqarBrandColors.primary
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: selected ? AqarBrandColors.dark : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final sheetMaxH = MediaQuery.sizeOf(context).height * 0.94;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: sheetMaxH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: AqarDesktopScrollbar(
                        controller: sheetScrollCtrl,
                        scrollbarOnRight: true,
                        alwaysShowThumb: true,
                        child: SingleChildScrollView(
                          controller: sheetScrollCtrl,
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
                                    color:
                                        AqarBrandColors.border.withOpacity(0.9),
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
                                      color: AqarBrandColors.accent,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AqarBrandColors.gold
                                            .withOpacity(0.35),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.tune_rounded,
                                      color: AqarBrandColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _isArabic
                                          ? 'نظام التصفية والفلاتر الذكي'
                                          : 'Smart filters',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Cairo',
                                            color: AqarBrandColors.dark,
                                          ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _exitAdvancedSearchModeFull();
                                    },
                                    child: Text(
                                      _isArabic ? 'إعادة ضبط' : 'Reset',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'محتوى الرئيسية' : 'Home feed',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'Cairo',
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  actionChip(
                                    selected:
                                        sheet.homeKind == HomeFeedKind.all,
                                    label: _isArabic ? 'الكل' : 'All',
                                    icon: Icons.grid_view_rounded,
                                    onTap: () {
                                      setModalState(
                                        () => sheet.homeKind = HomeFeedKind.all,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected:
                                        sheet.homeKind == HomeFeedKind.listings,
                                    label: _isArabic ? 'إعلانات' : 'Listings',
                                    icon: Icons.home_work_outlined,
                                    onTap: () {
                                      setModalState(
                                        () => sheet.homeKind =
                                            HomeFeedKind.listings,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected:
                                        sheet.homeKind == HomeFeedKind.requests,
                                    label:
                                        _isArabic ? 'طلبات السوق' : 'Requests',
                                    icon: Icons.request_quote_outlined,
                                    onTap: () {
                                      setModalState(
                                        () => sheet.homeKind =
                                            HomeFeedKind.requests,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: _paidPriorityOnlyFilter,
                                    label: _isArabic
                                        ? 'مدفوع / أولوية'
                                        : 'Paid / Priority',
                                    icon: Icons.workspace_premium_rounded,
                                    onTap: () {
                                      setModalState(() {
                                        _paidPriorityOnlyFilter =
                                            !_paidPriorityOnlyFilter;
                                      });
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  if (!_isGuest)
                                    actionChip(
                                      selected: sheet.hidden,
                                      label: _isArabic ? 'المخفية' : 'Hidden',
                                      icon: Icons.visibility_off_outlined,
                                      onTap: () {
                                        setModalState(
                                          () => sheet.hidden = !sheet.hidden,
                                        );
                                        _scheduleAdvSearchDraftSave(sheet);
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                initialValue: sheet.query,
                                onChanged: (v) {
                                  sheet.query = v;
                                  _scheduleAdvSearchDraftSave(sheet);
                                },
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText: _isArabic
                                      ? 'ابحث برقم الإعلان/الطلب، السعر، المساحة، الاسم، المسوق، المكتب...'
                                      : 'Search by ID, price, area, name, marketer, office...',
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest
                                      .withOpacity(0.22),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color:
                                          cs.outlineVariant.withOpacity(0.35),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color:
                                          cs.outlineVariant.withOpacity(0.35),
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
                              AqarMoneyRangeField(
                                isAr: _isArabic,
                                label: _isArabic
                                    ? 'المبلغ المحدد / السعر'
                                    : 'Specified amount / Price',
                                minInitial: sheet.priceMin,
                                maxInitial: sheet.priceMax,
                                minHint: _isArabic ? 'من' : 'From',
                                maxHint: _isArabic ? 'إلى' : 'To',
                                onMinChanged: (v) {
                                  sheet.priceMin = v;
                                  _scheduleAdvSearchDraftSave(sheet);
                                },
                                onMaxChanged: (v) {
                                  sheet.priceMax = v;
                                  _scheduleAdvSearchDraftSave(sheet);
                                },
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'المساحة' : 'Area',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: sheet.areaMin,
                                      keyboardType: TextInputType.number,
                                      inputFormatters:
                                          latinDecimalNumberFormatters(),
                                      onChanged: (v) {
                                        sheet.areaMin = v;
                                        _scheduleAdvSearchDraftSave(sheet);
                                      },
                                      decoration: InputDecoration(
                                        prefixIcon:
                                            const Icon(Icons.square_foot),
                                        hintText:
                                            _isArabic ? 'من م²' : 'From m2',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: sheet.areaMax,
                                      keyboardType: TextInputType.number,
                                      inputFormatters:
                                          latinDecimalNumberFormatters(),
                                      onChanged: (v) {
                                        sheet.areaMax = v;
                                        _scheduleAdvSearchDraftSave(sheet);
                                      },
                                      decoration: InputDecoration(
                                        prefixIcon:
                                            const Icon(Icons.straighten),
                                        hintText:
                                            _isArabic ? 'إلى م²' : 'To m2',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'نوع العقار' : 'Property type',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  actionChip(
                                    selected: sheet.type == null,
                                    label: _isArabic ? 'الكل' : 'All',
                                    icon: Icons.apps_outlined,
                                    onTap: () {
                                      setModalState(() => sheet.type = null);
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.type == PropertyType.villa,
                                    label: _isArabic ? 'فيلا' : 'Villa',
                                    icon: Icons.home_work_outlined,
                                    onTap: () {
                                      setModalState(
                                        () => sheet.type = PropertyType.villa,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected:
                                        sheet.type == PropertyType.apartment,
                                    label: _isArabic ? 'شقة' : 'Apartment',
                                    icon: Icons.apartment_outlined,
                                    onTap: () {
                                      setModalState(
                                        () =>
                                            sheet.type = PropertyType.apartment,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.type == PropertyType.land,
                                    label: _isArabic ? 'أرض' : 'Land',
                                    icon: Icons.landscape_outlined,
                                    onTap: () {
                                      setModalState(
                                        () => sheet.type = PropertyType.land,
                                      );
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'غرض الإعلان' : 'Listing purpose',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  actionChip(
                                    selected: sheet.purpose == null,
                                    label: _isArabic ? 'الكل' : 'All',
                                    icon: Icons.layers_outlined,
                                    onTap: () {
                                      setModalState(() => sheet.purpose = null);
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.purpose == 'sale',
                                    label: _isArabic ? 'بيع' : 'Sale',
                                    icon: Icons.sell_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.purpose = 'sale');
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.purpose == 'rent',
                                    label: _isArabic ? 'إيجار' : 'Rent',
                                    icon: Icons.calendar_month_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.purpose = 'rent');
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.purpose == 'auction',
                                    label: _isArabic ? 'مزاد' : 'Auction',
                                    icon: Icons.gavel_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.purpose = 'auction');
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.purpose == 'investment',
                                    label: _isArabic ? 'استثمار' : 'Investment',
                                    icon: Icons.trending_up_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.purpose = 'investment');
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'التأثيث' : 'Furnishing',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  actionChip(
                                    selected: sheet.furnished == null,
                                    label: _isArabic ? 'الكل' : 'All',
                                    icon: Icons.layers_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.furnished = null);
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.furnished == true,
                                    label: _isArabic ? 'مفروش' : 'Furnished',
                                    icon: Icons.chair_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.furnished = true);
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                  actionChip(
                                    selected: sheet.furnished == false,
                                    label:
                                        _isArabic ? 'غير مفروش' : 'Unfurnished',
                                    icon: Icons.event_seat_outlined,
                                    onTap: () {
                                      setModalState(
                                          () => sheet.furnished = false);
                                      _scheduleAdvSearchDraftSave(sheet);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isArabic ? 'الترتيب' : 'Sort',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _SortMenu(
                                isAr: _isArabic,
                                value: sheet.sort,
                                onChanged: (v) {
                                  setModalState(() => sheet.sort = v);
                                  _scheduleAdvSearchDraftSave(sheet);
                                },
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    FocusScope.of(context).unfocus();
                                    Navigator.pop(context);
                                    await _exitAdvancedSearchModeFull();
                                  },
                                  icon:
                                      const Icon(Icons.filter_alt_off_outlined),
                                  label: Text(
                                    _isArabic
                                        ? 'إنهاء البحث المتقدم'
                                        : 'End advanced search',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: EdgeInsets.zero,
                      child: Row(
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () async {
                                if (!mounted) return;
                                _debounce?.cancel();
                                setState(() {
                                  _feedFilterBusy = false;
                                  _searchQuery = sheet.query.trim();
                                  _cityFilter = sheet.city.trim().isEmpty
                                      ? 'all'
                                      : sheet.city;
                                  _typeFilter = sheet.type;
                                  _purposeFilter = sheet.purpose;
                                  _furnishedFilter = sheet.furnished;
                                  _priceMinFilter = _parseFilterNumber(
                                    sheet.priceMin,
                                  );
                                  _priceMaxFilter = _parseFilterNumber(
                                    sheet.priceMax,
                                  );
                                  _areaMinFilter = _parseFilterNumber(
                                    sheet.areaMin,
                                  );
                                  _areaMaxFilter = _parseFilterNumber(
                                    sheet.areaMax,
                                  );
                                  _sortBy = sheet.sort;
                                  _homeFeedKind = sheet.homeKind;
                                  _homeShowHiddenOnly = sheet.hidden;
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

                                final nav = Navigator.of(context);
                                nav.pop();
                                await _clearAdvSearchDraftPrefs();
                                FocusManager.instance.primaryFocus?.unfocus();
                              },
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(_isArabic ? 'تطبيق' : 'Apply'),
                            ),
                          ),
                        ],
                      ),
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

    if (_paidPriorityOnlyFilter) {
      chips.add(
        item(
          text: _isArabic ? 'مدفوع / أولوية' : 'Paid / Priority',
          icon: Icons.workspace_premium_rounded,
          onRemove: () => setState(() => _paidPriorityOnlyFilter = false),
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
      child: SingleChildScrollView(
        controller: _filterChipsHScrollCtrl,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
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
      if (kIsWeb) {
        await _webYieldUi();
      }
      _markDashboardFeedDirty();
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

  Future<void> _webYieldUi() async {
    // جوال + ويب: فسح خيط الواجهة بين مراحل التحميل بعد الدخول.
    await Future<void>.delayed(
      Duration(milliseconds: kIsWeb ? 32 : 16),
    );
  }

  /// ويب: `#/userDashboard?tab=4` يفتح تبويباً غير الرئيسية (لتجاوز تجمّد الرئيسية).
  void _applyWebDashboardTabFromUrl() {
    if (!kIsWeb) return;
    try {
      final frag = Uri.base.fragment.trim();
      if (frag.isEmpty) return;
      final path = frag.startsWith('/') ? frag : '/$frag';
      final uri = Uri.parse('https://local$path');
      final raw = uri.queryParameters['tab'] ?? uri.queryParameters['t'];
      final idx = int.tryParse((raw ?? '').trim());
      if (idx == null || idx < 0 || idx > 4) return;
      if (idx == 3 && _isGuest) {
        WebBootstrapDiag.warn('dashboard.tab', 'tab=3 cart ignored for guest');
        return;
      }
      if (_tabIndex == idx) return;
      _tabIndex = idx;
      WebBootstrapDiag.log('dashboard.tab', 'opened from url tab=$idx');
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
        // ضيف: ابدأ بدون فلاتر/مدينة محفوظة من جلسة سابقة على نفس الجهاز.
        _searchQuery = '';
        _cityFilter = 'all';
        _typeFilter = null;
        _purposeFilter = null;
        _furnishedFilter = null;
        _paidPriorityOnlyFilter = false;
        _priceMinFilter = null;
        _priceMaxFilter = null;
        _areaMinFilter = null;
        _areaMaxFilter = null;
        _regionFilter = '';
        _governorateFilter = '';
        _districtFilter = '';
        _homeFeedKind = HomeFeedKind.all;
        _sortBy = 'latest';
        _homeShowHiddenOnly = false;
        _hiddenPropertyIds = {};
        _hiddenMarketRequestIds = {};
        _myLat = null;
        _myLng = null;
        _inlineSearchCtrl.clear();
      }
    });

    try {
      PropertiesHomeFeedService.resetCircuit();
      SupabasePublicReadGuard.clearAuthFailureCooldown();
      // المرحلة 1: الرئيسية + طلبات السوق (+ إعلاناتي بالتوازي على الويب) ثم ارسم فوراً.
      final phase1 = <Future<void>>[
        _loadHome(force: true, userInitiated: true),
        _loadMarketHomeRequests(force: true),
      ];
      // ويب: سخّن mine + طلباتي مع الرئيسية حتى طلباتي/إعلاناتي فوري عند أول نقرة.
      if (!_isGuest && kIsWeb) {
        phase1.add(_loadMineAndOffers(force: true));
        phase1.add(_loadMyMarketSubmissions(force: false));
      }
      await Future.wait(phase1);
      _flushHomeFeedMutationsSync();
      if (mounted) {
        _ensureSubTabControllers();
        setState(() {});
      }
      WebBootstrapDiag.log(
        'initial_load',
        'home painted listings=${_all.length} requests=${_marketHomeRequests.length} mine=${_mine.length}',
      );

      // الدخول دائماً على الرئيسية — لا تُحوّل تلقائياً إلى صفحتي.
      if (!_isGuest) {
        // صفّر أي طلب قديم لفتح صفحتي حتى لا يخطف التبويب عند إعادة التحميل.
        unawaited(AccountCompletionService.consumeOpenMyPageOnce());
      }

      // المرحلة 2: دور + إشعارات؛ الدلاء الثقيلة في الخلفية دون حجب اللمس.
      if (!_isGuest) {
        Future<void> loadRest() async {
          if (!mounted) return;
          await Future.wait([
            _loadAccountRole(),
            _loadNotifications(),
            _refreshAppAudienceOnlineApprox(),
            if (!kIsWeb) _loadMineAndOffers(force: true),
            _loadFavoritesForUid(),
            if (!kIsWeb) _loadCart(force: true),
          ]);
          if (!mounted) return;
          // سخّن إدارتي مبكراً حتى يفتح فوراً عند النقر.
          unawaited(_prefetchMyDeskWarm());
          _ensureSubTabControllers();
          if (!kIsWeb) {
            await Future.wait([
              _loadFavoritesList(force: true),
              if (_usesMarketerMyPageHub) ...[
                _loadMarketerBuckets(force: true),
                _loadOwnerRequestsBuckets(force: true),
              ] else
                _loadOwnerRequestsBuckets(force: true),
            ]);
          } else {
            unawaited(_loadFavoritesList(force: false));
            // ويب: صفحتي تحتاج دلاء المسوّق/المالك — تحميل كسول بمهلة (لا يحجب اللمس).
            unawaited(_ensureMyAdsHubDataLoaded());
          }
          if (mounted) {
            _ensureWorkflowRealtimeChannel();
            _ensureHomeFeedRealtimeChannel();
            setState(() {});
          }
        }

        if (kIsWeb) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(loadRest());
          });
        } else {
          await loadRest();
        }
      } else if (mounted) {
        _ensureHomeFeedRealtimeChannel();
      }

      // المدن على الويب مؤجّلة — كانت decode أثناء الدخول يجمّد الإطار.
      if (!kIsWeb) {
        unawaited(() async {
          try {
            await _loadCities(includeExtra: false);
            await _maybeApplyPreferredExploreCity();
            if (mounted) setState(() {});
          } catch (_) {}
        }());
      } else {
        Future<void>.delayed(const Duration(seconds: 5), () async {
          if (!mounted) return;
          try {
            await _loadCities(includeExtra: false);
            await _maybeApplyPreferredExploreCity();
            // لا setState إن لم تتغيّر الفلاتر — يمنع عاصفة home.paint.
            if (mounted && _cityFilter != 'all') setState(() {});
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('Initial load error: $e');
    } finally {
      if (mounted) {
        unawaited(_reloadHiddenFeedPreferences());
      }
    }
  }

  bool _webDeferredTabsScheduled = false;

  void _scheduleWebDeferredTabs() {
    if (_isGuest || _webDeferredTabsScheduled) return;
    _webDeferredTabsScheduled = true;
    // ويب: بعد إصلاح الازدواج — تأخير قصير فقط لترك إطار الرئيسية يستقر (كان 6ث يُشعر بالتعليق).
    final delay = kIsWeb
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 600);
    WebBootstrapDiag.log(
      'deferred_tabs',
      'scheduled in ${delay.inMilliseconds}ms',
    );
    Future<void>.delayed(delay, () {
      if (!mounted || _isGuest) return;
      unawaited(_runInitialLoadLoggedInDeferred());
    });
  }

  /// باقي التبويبات بعد الرئيسية — خفيف جداً على الويب (لا buckets/mine عند الإقلاع).
  Future<void> _runInitialLoadLoggedInDeferred() async {
    if (!mounted || _isGuest) return;
    WebBootstrapDiag.start('deferred_tabs');
    try {
      await _webYieldUi();
      WebBootstrapDiag.start('deferred.account_role');
      await _loadAccountRole().timeout(
        const Duration(seconds: 12),
        onTimeout: () =>
            WebBootstrapDiag.warn('deferred.account_role', 'timeout'),
      );
      WebBootstrapDiag.end('deferred.account_role');
      await _webYieldUi();
      WebBootstrapDiag.start('deferred.notifications');
      await _loadNotifications().timeout(
        const Duration(seconds: 12),
        onTimeout: () =>
            WebBootstrapDiag.warn('deferred.notifications', 'timeout'),
      );
      WebBootstrapDiag.end('deferred.notifications');

      // ويب — كل الأدوار (مالك/مسوّق/مكتب/مؤسسة/شركة/وكالة):
      // إقلاع خفيف فوري، ثم تسخين صفحتي/السلة في الخلفية دون حجب اللمس.
      if (kIsWeb) {
        if (mounted) {
          _ensureSubTabControllers();
          _ensureHomeFeedRealtimeChannel(deferMs: 2500);
        }
        WebBootstrapDiag.end(
          'deferred_tabs',
          'web light complete role=${_accountType.trim().isEmpty ? "pending" : _accountType}',
        );
        // بعد استقرار الرئيسية: سخّن «إعلاناتي» لكل الصلاحيات في الخلفية.
        Future<void>.delayed(const Duration(milliseconds: 1600), () {
          if (!mounted || _isGuest) return;
          unawaited(_ensureMyAdsHubDataLoaded());
        });
        Future<void>.delayed(const Duration(milliseconds: 2800), () {
          if (!mounted || _isGuest) return;
          unawaited(
            _loadCart(force: false).timeout(
              const Duration(seconds: 12),
              onTimeout: () {},
            ),
          );
        });
        return;
      }

      await _webYieldUi();
      WebBootstrapDiag.start('deferred.cart');
      await _loadCart(force: true).timeout(
        const Duration(seconds: 12),
        onTimeout: () => WebBootstrapDiag.warn('deferred.cart', 'timeout'),
      );
      WebBootstrapDiag.end('deferred.cart');
      await _webYieldUi();
      WebBootstrapDiag.start('deferred.mine');
      await _loadMineAndOffers(force: true).timeout(
        const Duration(seconds: 15),
        onTimeout: () => WebBootstrapDiag.warn('deferred.mine', 'timeout'),
      );
      WebBootstrapDiag.end('deferred.mine');
      await _loadFavoritesForUid().timeout(
        const Duration(seconds: 10),
        onTimeout: () => WebBootstrapDiag.warn('deferred.favorites', 'timeout'),
      );
      if (!mounted) return;
      _ensureSubTabControllers();
      await _webYieldUi();
      await _loadFavoritesList(force: true);
      // نفس معيار الواجهة: نوع الحساب لا verified فقط.
      if (_usesMarketerMyPageHub) {
        await Future.wait([
          _loadMarketerBuckets(force: true),
          _loadOwnerRequestsBuckets(force: true),
        ]);
      } else {
        await _loadOwnerRequestsBuckets(force: true);
      }
      if (mounted) {
        _ensureWorkflowRealtimeChannel();
        _ensureHomeFeedRealtimeChannel(deferMs: 800);
      }
      WebBootstrapDiag.end('deferred_tabs', 'complete');
    } catch (e) {
      WebBootstrapDiag.warn('deferred_tabs', '$e');
      debugPrint('Deferred initial load error: $e');
    }
  }

  bool _myAdsHubDataLoadStarted = false;

  /// فتح «صفحتي» فوراً بالكاش/الهيكل — الشبكة كلها في الخلفية (لا await 5ث).
  Future<void> _ensureMyAdsHubDataLoaded({bool force = false}) async {
    if (_isGuest || !mounted) return;
    if (!force && _myAdsHubDataLoadStarted) return;
    _myAdsHubDataLoadStarted = true;
    WebBootstrapDiag.start('my_ads.lazy');
    try {
      _ensureSubTabControllers();
      // لا setState فوري هنا — يمنع وميض/إعادة بناء قبل وصول الدلاء.
      WebBootstrapDiag.log(
        'my_ads.lazy',
        'instant paint n=${_mine.length} hub=${_usesMarketerMyPageHub ? "marketer" : "owner"}',
      );
      WebBootstrapDiag.end('my_ads.lazy', 'ui ready (bg load)');
      unawaited(_loadMyAdsHubDataInBackground(force: force));
    } catch (e) {
      WebBootstrapDiag.warn('my_ads.lazy', '$e');
      _myAdsHubDataLoadStarted = false;
    }
  }

  Future<void> _loadMyAdsHubDataInBackground({required bool force}) async {
    try {
      final roleFut = _accountRoleLoaded
          ? Future<void>.value()
          : _loadAccountRole().timeout(
              const Duration(seconds: 4),
              onTimeout: () {},
            );
      final mineFut = (!force && _mine.isNotEmpty && !_loadingMine)
          ? Future<void>.value()
          : _loadMineAndOffers(force: force || _mine.isEmpty).timeout(
              const Duration(seconds: 8),
              onTimeout: () =>
                  WebBootstrapDiag.warn('my_ads.lazy', 'mine timeout'),
            );
      await Future.wait([roleFut, mineFut]);
      if (!mounted) return;
      _ensureSubTabControllers();
      WebBootstrapDiag.log(
        'my_ads.lazy',
        'mine ready n=${_mine.length} hub=${_usesMarketerMyPageHub ? "marketer" : "owner"}',
      );

      final usedMarketer = _usesMarketerMyPageHub;
      final hasHubCache = usedMarketer
          ? (_hasMarketingData || _hasOwnerRequestsData)
          : _hasOwnerRequestsData;
      // إن وُجد كاش للدلاء ولا طلب force: أعِد الرسم مرة واحدة بعد mine فقط عند الحاجة.
      if (force || !hasHubCache) {
        // انتظر الدلاء ثم setState مرة واحدة — يقلل الوميض المزدوج.
      } else if (mounted) {
        setState(() {});
      }

      final bucketsFut = usedMarketer
          ? Future.wait([
              _loadMarketerBuckets(force: force),
              _loadOwnerRequestsBuckets(force: force),
            ])
          : _loadOwnerRequestsBuckets(force: force);
      try {
        await bucketsFut;
        if (!mounted) return;
        _ensureSubTabControllers();
        if (_usesMarketerMyPageHub != usedMarketer) {
          if (_usesMarketerMyPageHub) {
            await _loadMarketerBuckets(force: false);
          } else {
            await _loadOwnerRequestsBuckets(force: false);
          }
        }
        if (!kIsWeb) {
          _ensureWorkflowRealtimeChannel();
        }
        if (mounted) setState(() {});
        WebBootstrapDiag.log(
          'my_ads.lazy',
          'hub=${_usesMarketerMyPageHub ? "marketer" : "owner"} buckets=done',
        );
      } catch (e) {
        WebBootstrapDiag.warn('my_ads.lazy', 'buckets $e');
        if (mounted) setState(() {});
      }
    } catch (e) {
      WebBootstrapDiag.warn('my_ads.lazy.bg', '$e');
      // أبقِ العلم true إن وُجد كاش حتى لا تُعاد الحلقة عند كل دخول لصفحتي.
      if (!_hasMarketingData && !_hasOwnerRequestsData && _mine.isEmpty) {
        _myAdsHubDataLoadStarted = false;
      }
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

  void _ensureHomeFeedRealtimeChannel({int deferMs = 0}) {
    if (kIsWeb) return;
    void subscribe() {
      if (!mounted) return;
      try {
        _homeFeedRealtimeChannel?.unsubscribe();
        _homeFeedRealtimeChannel = null;
        final ch = _sb.channel(
            'home_feed_listings_${_sb.auth.currentUser?.id ?? "anon"}');
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

    if (deferMs > 0 && kIsWeb) {
      Future<void>.delayed(Duration(milliseconds: deferMs), subscribe);
      return;
    }
    subscribe();
  }

  void _disposeHomeFeedRealtimeChannel() {
    _homeFeedRealtimeDebounce?.cancel();
    _homeFeedRealtimeDebounce = null;
    try {
      _homeFeedRealtimeChannel?.unsubscribe();
    } catch (_) {}
    _homeFeedRealtimeChannel = null;
  }

  /// تسلسل أول دخول مسجّل: جولة التبويبات → لون التمييز.
  /// الشروط الإلزامية تُعالَج في [PostAuthShell] قبل اللوحة — لا حوار مكرر هنا.
  Future<void> _runLoggedInFirstRunPrompts() async {
    if (!mounted || _isGuest) return;
    try {
      await OneTimePromptCoordinator.migrateLegacyOnboardingKeysIfNeeded();
      await DeviceFirstRunPrefs.syncLegacyOneTimeIntoDeviceFlags();
      if (!mounted || _isGuest) return;
      if (await DeviceFirstRunPrefs.consumeReplayPending()) {
        await DeviceFirstRunPrefs.clearTourAndAccentForReplay();
        if (mounted) {
          setState(() {
            _offerAccentAfterTourReplay = true;
            _showDashboardOnboarding = true;
            _tabIndex = 0;
          });
        }
        return;
      }
      if (_sb.auth.currentUser != null) {
        final eligibleCoach =
            await LegalTermsPromptService.isEligibleForLegalTermsCoach(_sb);
        if (eligibleCoach) {
          await _maybeShowLegalTermsCoach();
        } else {
          final uid = _uid.trim().isEmpty ? null : _uid.trim();
          final coachId = OneTimePromptCoordinator.idForUser(
            'legal_terms_policy_coach_v2',
            uid,
          );
          await OneTimePromptCoordinator.markSeen(coachId);
        }
      }
      if (!mounted || _isGuest) return;
      await _maybeShowDashboardOnboarding();
    } catch (_) {}
  }

  /// جولة تعريفية لمرة واحدة لكل حساب — الضغط خارج الفقاعة = التالي؛ الإغلاق من الأزرار فقط.
  Future<void> _maybeShowDashboardOnboarding() async {
    if (!mounted || _isGuest) return;
    try {
      await OneTimePromptCoordinator.migrateLegacyOnboardingKeysIfNeeded();
      await DeviceFirstRunPrefs.syncLegacyOneTimeIntoDeviceFlags();
      if (await DeviceFirstRunPrefs.isDashboardTourDone()) {
        await _maybeShowAccentColorPrompt();
        return;
      }
      if (!mounted) return;
      setState(() {
        _showDashboardOnboarding = true;
        _tabIndex = 0;
      });
    } catch (_) {}
  }

  String _partnerOnboardingLine() {
    if (_isGuest) {
      return partnerRealtorLine(isArabic: _isArabic, rawFullName: '');
    }
    final raw = _resolvedGreetingDisplayName();
    return partnerRealtorLine(isArabic: _isArabic, rawFullName: raw);
  }

  Future<void> _completeDashboardOnboarding(
      {bool resetTabToHome = true}) async {
    final uid = _uid.trim().isEmpty ? null : _uid.trim();
    await DeviceFirstRunPrefs.setDashboardTourDone(userId: uid);
    if (!mounted) return;
    final offerAccentAfterReplay = _offerAccentAfterTourReplay;
    _offerAccentAfterTourReplay = false;
    setState(() {
      _showDashboardOnboarding = false;
      if (resetTabToHome) _tabIndex = 0;
    });
    if (offerAccentAfterReplay) {
      // إعادة الجولة من الإعدادات: اعرض الألوان بعدها إن لزم.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowAccentColorPrompt());
      });
    } else {
      // أول دخول: تخطّي/إغلاق/إكمال الجولة ⇒ لا جولة ولا ألوان مرة أخرى.
      await DeviceFirstRunPrefs.setAccentPromptDone(userId: uid);
    }
  }

  Future<void> _maybeShowAccentColorPrompt() async {
    if (!mounted || _isGuest) return;
    try {
      final uid = _uid.trim().isEmpty ? null : _uid.trim();
      if (await DeviceFirstRunPrefs.isAccentPromptDone(userId: uid)) return;
      // لا تُعرض قبل إنهاء الجولة (إن كانت معلّقة لهذا الحساب).
      if (!await DeviceFirstRunPrefs.isDashboardTourDone(userId: uid)) return;
      if (!mounted) return;
      await showAccentColorFirstRunDialog(context);
      if (mounted) {
        await DeviceFirstRunPrefs.setAccentPromptDone(userId: uid);
      }
    } catch (_) {}
  }

  /// إقرار الشروط لمرة واحدة لكل حساب: مربع صح إلزامي + رابط منبثق.
  /// لا يُغلق إلا بعد التأشير وزر المتابعة؛ لا يُورَّث بين الحسابات.
  Future<void> _maybeShowLegalTermsCoach() async {
    if (!mounted || _isGuest) return;
    try {
      final uid = _uid.trim().isEmpty ? null : _uid.trim();
      final coachId = OneTimePromptCoordinator.idForUser(
        'legal_terms_policy_coach_v2',
        uid,
      );
      if (await OneTimePromptCoordinator.hasSeen(coachId)) return;

      final eligible =
          await LegalTermsPromptService.isEligibleForLegalTermsCoach(
        _sb,
      );
      if (!eligible) return;
      if (!mounted) return;

      final ok = await showLegalTermsAckDialog(
        context,
        isAr: _isArabic,
      );
      if (!mounted) return;
      if (ok) {
        await OneTimePromptCoordinator.markSeen(coachId);
      }
    } catch (_) {}
  }

  List<DashboardOnboardingStepData> _buildDashboardOnboardingSteps(
    AppLocalizations l10n,
  ) {
    final isWeb = kIsWeb;
    final steps = <DashboardOnboardingStepData>[];

    // ترحيب في الوسط
    steps.add(
      DashboardOnboardingStepData(
        title: isWeb
            ? l10n.onboardingWelcomeTitleWeb
            : l10n.onboardingWelcomeTitleApp,
        body: isWeb
            ? l10n.onboardingWelcomeBodyWeb
            : l10n.onboardingWelcomeBodyApp,
        tabIndex: 0,
        arrow: DashboardCoachArrow.none,
      ),
    );

    // الرئيسية — أسفل يسار/أول تبويب
    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingHomeTitle,
        body: l10n.onboardingHomeBody,
        tabIndex: 0,
        arrow: DashboardCoachArrow.down,
        navFraction: 0.08,
      ),
    );

    // صفحتي
    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingMyAdsTitle,
        body: _isMarketingAccountType
            ? l10n.onboardingMyAdsBodyMarketing
            : l10n.onboardingMyAdsBodyOwner,
        tabIndex: 1,
        arrow: DashboardCoachArrow.down,
        navFraction: 0.28,
      ),
    );

    // طلباتي/إعلاناتي
    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingMySubmissionsTitle,
        body: l10n.onboardingMySubmissionsBody,
        tabIndex: 2,
        arrow: DashboardCoachArrow.down,
        navFraction: 0.48,
      ),
    );

    // رؤى السوق — أيقونة علوية
    steps.add(
      DashboardOnboardingStepData(
        title: l10n.marketInsightsTitle,
        body: l10n.onboardingMarketInsightsBody,
        tabIndex: null,
        arrow: DashboardCoachArrow.up,
        navFraction: 0.72,
      ),
    );

    // الدردشة — أيقونة علوية
    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingChatTitle,
        body: l10n.onboardingChatBody,
        tabIndex: null,
        arrow: DashboardCoachArrow.up,
        navFraction: 0.88,
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
          arrow: DashboardCoachArrow.up,
          navFraction: 0.55,
        ),
      );
    }

    if (_cartReservationFeaturesEnabled) {
      steps.add(
        DashboardOnboardingStepData(
          title: l10n.onboardingCartTitle,
          body: l10n.onboardingCartBody,
          tabIndex: 3,
          arrow: DashboardCoachArrow.down,
          navFraction: 0.68,
        ),
      );
    }

    steps.add(
      DashboardOnboardingStepData(
        title: l10n.onboardingSupportTitle,
        body: l10n.onboardingSupportBody,
        tabIndex: 4,
        arrow: DashboardCoachArrow.down,
        navFraction: 0.88,
      ),
    );

    return steps;
  }

  void _onLiveAppearanceChanged() {
    if (!mounted) return;
    // إعادة بناء فورية للغة/الثيم + تحديث اسم التحية حسب لغة الواجهة.
    unawaited(_hydrateGreetingNameCache());
    setState(() {});
  }

  // =========================
  // Auth reload
  // =========================
  void _handleAuthReloadIfNeeded({AuthChangeEvent? event}) {
    if (SessionManager.duringPublicSessionReset) {
      WebBootstrapDiag.warn('auth.reload', 'skipped — public session reset');
      return;
    }
    // ضيف: signedOut بعد مسح JWT لا يجب أن يعيد تحميل اللوحة بالكامل (كان يجمّد).
    if (_isGuest) {
      WebBootstrapDiag.warn('auth.reload', 'skipped — guest mode');
      return;
    }
    if (event == AuthChangeEvent.tokenRefreshed ||
        event == AuthChangeEvent.userUpdated) {
      return;
    }

    // فضّل الجلسة إن وُجدت — currentUser قد يكون null لحظة عابرة دون signedOut.
    final uid = _sb.auth.currentUser?.id ?? _sb.auth.currentSession?.user.id;
    if ((uid == null || uid.isEmpty) && event != AuthChangeEvent.signedOut) {
      WebBootstrapDiag.warn(
        'auth.reload',
        'ignored transient uid null (not signedOut)',
      );
      return;
    }
    if (_lastAuthUserId == uid) return;
    WebBootstrapDiag.warn(
      'auth.reload',
      'uid change ${_lastAuthUserId ?? "null"} → ${uid ?? "null"}',
    );
    final previousUid = _lastAuthUserId;
    _lastAuthUserId = uid;

    if (!mounted) return;
    if (!_didInitialLoad) return;
    if (_reloading) return;
    _reloading = true;

    // تبديل حساب A→B أو خروج صريح: امسح فوراً حتى لا يومض بيانات الحساب السابق.
    final switchedAccounts = previousUid != null &&
        previousUid.isNotEmpty &&
        uid != null &&
        uid.isNotEmpty &&
        previousUid != uid;
    final signedOut =
        event == AuthChangeEvent.signedOut || uid == null || uid.isEmpty;
    if (switchedAccounts || signedOut) {
      InAppNotificationHub.clearQueueAndToast();
      MarketingBucketsCache.instance.clearAll();
      MarketingWorkflowHub.hubHighlightRequestId.value = null;
      _hubHighlightRequestId = null;
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

      if (signedOut || switchedAccounts) {
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
        _notifications.clear();
        _clearMarketingStateOnLogout();
        _myAdsHubDataLoadStarted = false;
      }
    });

    // خروج بلا uid: لا تُعد تحميل لوحة مستخدم — اترك الحارس يوجّه للدخول.
    if (signedOut && (uid == null || uid.isEmpty)) {
      _reloading = false;
      return;
    }

    () async {
      try {
        if (kIsWeb) {
          await _reloadAll();
          if (mounted && uid != null && uid.isNotEmpty) {
            _ensureWorkflowRealtimeChannel();
          }
          if (mounted) {
            _ensureHomeFeedRealtimeChannel();
          }
        } else {
          await _loadCities(includeExtra: false);
          if (mounted) {
            setState(() {});
          }

          await Future.wait([
            _loadHome(force: true),
            _loadMarketHomeRequests(force: true),
          ]);

          if (uid != null && uid.isNotEmpty) {
            await Future.wait([
              _loadAccountRole(),
              _loadNotifications(),
              _loadFavoritesForUid(),
              _loadCart(force: true),
              _loadMineAndOffers(force: true),
            ]);
            _ensureSubTabControllers();

            await Future.wait([
              _loadFavoritesList(force: true),
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
        }
      } catch (e) {
        debugPrint('Auth reload error: $e');
      } finally {
        _reloading = false;
      }
    }();
  }

  void _onMarketingWorkflowBucketsRevision() {
    if (!mounted || _isGuest) return;
    // كان يحدّث المسوّق فقط — المالك يبقى ببطاقات قديمة في التبويبات بعد الموافقة/الإعادة.
    if (_isMarketerRole) {
      MarketingBucketsCache.instance.invalidateMarketer(_uid);
      unawaited(_loadMarketerBuckets(force: true));
    } else {
      MarketingBucketsCache.instance.invalidateOwner(_uid);
      unawaited(_loadOwnerRequestsBuckets(force: true));
      unawaited(_loadMineAndOffers(force: true));
    }
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
        if (!kIsWeb) {
          await Future.wait([
            _loadHome(force: true),
            _loadMarketHomeRequests(force: true),
          ]);
        }
      }());
    });
  }

  void _ensureWorkflowRealtimeChannel() {
    if (kIsWeb) return;
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

  Future<void> _hydrateGreetingNameCache() async {
    if (_isGuest || _uid.isEmpty) return;
    final mem = DashboardGreetingCache.memoryFor(_uid);
    if (mem != null && mem.isNotEmpty) {
      _greetingNameCache = mem;
    }
    final cached = await DashboardGreetingCache.read(_uid);
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty && cached != _greetingNameCache) {
      setState(() => _greetingNameCache = cached);
    }
    // جلب الملف الشخصي فوراً (لا تنتظر دفعة الإشعارات).
    unawaited(_warmOwnProfileForGreeting());
  }

  /// تسخين إدارتي في الخلفية بعد جاهزية الدور — يقلّل انتظار أول فتح.
  Future<void> _prefetchMyDeskWarm() async {
    if (_isGuest || _uid.isEmpty) return;
    try {
      final at = _accountType.trim().toLowerCase();
      final marketing = AppRoleHelper.isMarketingRole(
            AppRoleHelper.fromAccountType(at),
          ) ||
          AppRoleHelper.isOrgEntity(at) ||
          _orgNavIsOwner ||
          AppRoleHelper.orgPermissionsOpenDeskShell(_orgMembershipPermissions);
      if (!marketing && !AppRoleHelper.isOwnerIndividual(at)) return;
      final svc = OrgTeamService(_sb);
      if (AppRoleHelper.isOrgEntity(at) ||
          AppRoleHelper.isMarketingRole(
            AppRoleHelper.fromAccountType(at),
          ) ||
          _orgNavIsOwner) {
        await svc.ensureMyOrgUnit().timeout(const Duration(seconds: 8));
        await svc.myOrgContext().timeout(const Duration(seconds: 8));
      }
    } catch (_) {}
  }

  Future<void> _warmOwnProfileForGreeting() async {
    if (_isGuest || _uid.isEmpty) return;
    try {
      await _fetchProfilesByUserIds([_uid]);
      if (!mounted) return;
      final name = _displayNameFromProfile(_profileCache[_uid]).trim();
      if (name.isEmpty) return;
      unawaited(DashboardGreetingCache.save(_uid, name));
      if (name != _greetingNameCache) {
        setState(() => _greetingNameCache = name);
      }
    } catch (_) {}
  }

  String _resolvedGreetingDisplayName() {
    final fromProfile = _displayNameFromProfile(_profileCache[_uid]).trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    return _greetingNameCache.trim();
  }

  /// سابقاً كان يضبط الصلاحيات «محمّلة» بنوع افتراضي user فيُخفي إدارتي/إعلاناتي.
  /// التبويبات تبقى متفائلة حتى [_loadAccountRole] الحقيقي.
  void _primeWebAccountRoleForInteraction() {}

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

    _lastAuthUserId = _sb.auth.currentUser?.id;
    _hydrateAccountRoleFromCache();
    unawaited(_hydrateGreetingNameCache());
    _inlineSearchCtrl.text = _searchQuery;

    langNotifier.addListener(_onLiveAppearanceChanged);
    themeModeNotifier.addListener(_onLiveAppearanceChanged);

    _ensureSubTabControllers();
    unawaited(_refreshOrgJoinRequestBadge());
    _ensureOrgJoinBadgePolling();

    unawaited(touchWebSessionActivity());
    if (context.read<AppSession>().isGuest) {
      unawaited(touchWebGuestActivity());
    }

    InAppNotificationHub.onInboxInvalidate = () {
      if (!mounted) return;
      unawaited(_loadNotifications());
    };

    InAppDashboardDeepLink.pending.addListener(_onDashboardDeepLinkPending);

    MarketingWorkflowHub.bucketsRevision
        .addListener(_onMarketingWorkflowBucketsRevision);

    unawaited(_loadDashboardGesturePreferences());

    if (kIsWeb) {
      AppWebSoftRefresh.register(() async {
        if (!mounted) return;
        // لا تحجب الواجهة عند العودة من الخلفية / F5 — حدّث في الخلفية فوراً.
        unawaited(_reloadAll());
        unawaited(PresenceHeartbeatService.ping(_sb));
        unawaited(_refreshAppAudienceOnlineApprox());
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kIsWeb) _applyWebDashboardTabFromUrl();
      unawaited(_maybeWarmUpWebLocationPermission());
      await _runInitialLoad();
      if (!mounted) return;
      unawaited(ListingDeepLink.openIfQueued(context, lang: widget.lang));
      await _runLoggedInFirstRunPrompts();
      if (!mounted) return;
      unawaited(_refreshAppAudienceOnlineApprox());
      _appAudiencePollTimer?.cancel();
      _appAudiencePollTimer = Timer.periodic(const Duration(seconds: 50), (_) {
        if (!mounted) return;
        unawaited(_refreshAppAudienceOnlineApprox());
      });

      _presenceHeartbeatTimer?.cancel();
      _presenceHeartbeatTimer =
          Timer.periodic(const Duration(seconds: 55), (_) {
        if (!mounted) return;
        unawaited(PresenceHeartbeatService.ping(_sb));
      });
      unawaited(PresenceHeartbeatService.ping(_sb));
    });

    unawaited(_loadPackageVersionLine());

    _authSub = _sb.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.tokenRefreshed) return;
      _handleAuthReloadIfNeeded(event: data.event);
    });
  }

  Future<void> _runWebBootstrapAfterFirstFrame() async {
    if (!mounted) return;
    WebBootstrapDiag.log('dashboard.bootstrap', 'first frame');
    if (kIsWeb) {
      WebInteractionRecovery.dismissStuckOverlaysOnce();
    }
    if (kIsWeb && !WebDashboardBootstrapGuard.tryStart()) {
      // ثانوية دائماً: لا تحميل مزدوج (كان يفرّغ الرئيسية ويجمّد التبويبات).
      WebBootstrapDiag.warn(
        'dashboard.bootstrap',
        'duplicate instance — abort load',
      );
      return;
    }
    _primeWebAccountRoleForInteraction();
    _applyWebDashboardTabFromUrl();
    await _webYieldUi();

    _ensureSubTabControllers();
    unawaited(_refreshOrgJoinRequestBadge());
    _ensureOrgJoinBadgePolling();

    unawaited(touchWebSessionActivity());
    if (_isGuest) {
      unawaited(touchWebGuestActivity());
    }

    InAppNotificationHub.onInboxInvalidate = () {
      if (!mounted) return;
      unawaited(_loadNotifications());
    };

    InAppDashboardDeepLink.pending.addListener(_onDashboardDeepLinkPending);

    MarketingWorkflowHub.bucketsRevision
        .addListener(_onMarketingWorkflowBucketsRevision);

    unawaited(_loadDashboardGesturePreferences());
    unawaited(_loadPackageVersionLine());

    if (kIsWeb) {
      AppWebSoftRefresh.register(() async {
        if (!mounted) return;
        // لا تحجب الواجهة عند العودة من الخلفية / F5 — حدّث في الخلفية فوراً.
        unawaited(_reloadAll());
        unawaited(PresenceHeartbeatService.ping(_sb));
        unawaited(_refreshAppAudienceOnlineApprox());
      });
    }

    await _runInitialLoad();
    if (!mounted) return;
    await _webYieldUi();
    WebBootstrapDiag.log('dashboard.bootstrap', 'initial load finished');
    // لا إعادة feed.cache هنا — [_runInitialLoad] جدولها مرة واحدة.

    unawaited(ListingDeepLink.openIfQueued(context, lang: widget.lang));
    // بعد اكتمال الرئيسية — لا ننافس طلبات التحميل بـ get_active_legal_version.
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      unawaited(_runLoggedInFirstRunPrompts());
    });

    _appAudiencePollTimer?.cancel();
    _appAudiencePollTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      if (!mounted) return;
      unawaited(_refreshAppAudienceOnlineApprox());
    });
    unawaited(_refreshAppAudienceOnlineApprox());

    _authSub = _sb.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.tokenRefreshed) return;
      _handleAuthReloadIfNeeded(event: data.event);
    });
  }

  Widget _webTabSlot(int index, Widget child) {
    return KeyedSubtree(
      key: ValueKey<String>('web-tab-$index'),
      child: child,
    );
  }

  List<Widget> _buildWebTabChildren({
    required List<Property> homeItems,
    required List<MarketPropertyRequestRow> homeRequestsFiltered,
    required int homeLoadedPropertyRows,
  }) {
    Widget slot(int i, Widget Function() build) {
      if (!_webVisitedTabs.contains(i)) {
        return _webTabSlot(i, const SizedBox.shrink());
      }
      return _webTabSlot(i, build());
    }

    return <Widget>[
      slot(
        0,
        () => _buildHomeBody(
          homeItems,
          homeRequestsFiltered,
          loadedPropertyRows: homeLoadedPropertyRows,
          loadedRequestRows: _marketHomeRequests.length,
        ),
      ),
      slot(1, _buildMyAdsHub),
      slot(2, _buildMySubmissionsBody),
      slot(3, _buildCartBody),
      slot(4, _buildSupportHubBody),
    ];
  }

  Widget _buildDashboardTabBody({
    required List<Property> homeItems,
    required List<MarketPropertyRequestRow> homeRequestsFiltered,
    required int homeLoadedPropertyRows,
  }) {
    // ويب: IndexedStack — ابنِ التبويب النشط دائماً، وحدّث الرئيسية عند تغيّر الفيد،
    // ولا تعِد بناء إعلاناتي/طلباتي عند كل home.paint (كان يسبب Null check + تجمّد).
    if (kIsWeb) {
      _webVisitedTabs.add(_tabIndex);
      final feedSig = Object.hash(
        _nestedDashboardFeedCacheBuiltKey,
        homeItems.length,
        homeRequestsFiltered.length,
        homeLoadedPropertyRows,
        _marketHomeRequests.length,
        _nestedDashboardMixedEntries.length,
        _errorHome,
        _homeFeedKind,
        _homeShowHiddenOnly,
        _paidPriorityOnlyFilter,
        homeItems.isEmpty ? 0 : identityHashCode(homeItems.first),
        homeRequestsFiltered.isEmpty
            ? 0
            : identityHashCode(homeRequestsFiltered.first),
      );
      final feedChanged = _webTabChildrenFeedSig != feedSig;
      // بيانات إعلاناتي/طلباتي — منفصلة عن عاصفة home.paint.
      final hubSig = Object.hash(
        Object.hash(
          _mine.length,
          _offers.length,
          _loadingMine,
          _loadingMarketing,
          _loadingOwnerRequests,
          _accountType,
          _myAdsHubDataLoadStarted,
          _errorMine,
          _hasMarketingData,
          _hasOwnerRequestsData,
          _mkInvites.length,
          _mkOffers.length,
          _mkContracts.length,
          _mkPermits.length,
          _mkPublished.length,
          _ownerListingRequests.length,
          // لا تُدخل identityHashCode لكنترولر التبويب — إعادة إنشائه كانت تهدم الـ hub وتسبب Null check.
          _usesMarketerMyPageHub,
          _hasOwnerRequestsData,
          _marketerPublisherHubMode,
          _mkInvites.isNotEmpty ||
              _mkOffers.isNotEmpty ||
              _mkContracts.isNotEmpty ||
              _mkPermits.isNotEmpty ||
              _mkPublished.isNotEmpty,
        ),
        Object.hash(
          _searchQuery,
          _cityFilter,
          _typeFilter,
          _purposeFilter,
          _furnishedFilter,
          _priceMinFilter,
          _priceMaxFilter,
          _areaMinFilter,
          _areaMaxFilter,
          _sortBy,
          _paidPriorityOnlyFilter,
        ),
      );
      final hubChanged = _webTabChildrenHubSig != hubSig;
      final active = _tabIndex.clamp(0, 4);
      final tabSwitched = _webBuiltActiveTab != active;
      Widget buildSlot(int i) {
        switch (i) {
          case 1:
            return _webTabSlot(i, _buildMyAdsHub());
          case 2:
            return _webTabSlot(i, _buildMySubmissionsBody());
          case 3:
            return _webTabSlot(i, _buildCartBody());
          case 4:
            return _webTabSlot(i, _buildSupportHubBody());
          case 0:
          default:
            return _webTabSlot(
              i,
              _buildHomeBody(
                homeItems,
                homeRequestsFiltered,
                loadedPropertyRows: homeLoadedPropertyRows,
                loadedRequestRows: _marketHomeRequests.length,
              ),
            );
        }
      }

      final prev = _webTabChildren;
      final next = List<Widget>.generate(5, (i) {
        if (!_webVisitedTabs.contains(i)) {
          return _webTabSlot(i, const SizedBox.shrink());
        }
        final isActive = i == active;
        if (i == 0) {
          // حتى على الرئيسية: لا تعِد البناء إلا عند تغيّر الفيد أو أول زيارة.
          // (setState من الإشعارات/المتصل كان يطلق home.paint عشرات المرات.)
          if (feedChanged ||
              prev == null ||
              !_webMaterializedTabs.contains(0) ||
              (isActive && tabSwitched)) {
            _webMaterializedTabs.add(0);
            return buildSlot(0);
          }
          return prev[0];
        }
        // إعلاناتي/طلباتي/…: لا تُهدم مع home.paint — فقط عند التبديل أو تغيّر بياناتها.
        final needsHubRebuild = isActive &&
            (tabSwitched ||
                hubChanged ||
                prev == null ||
                !_webMaterializedTabs.contains(i));
        if (needsHubRebuild) {
          _webMaterializedTabs.add(i);
          return buildSlot(i);
        }
        if (prev != null &&
            i < prev.length &&
            _webMaterializedTabs.contains(i)) {
          return prev[i];
        }
        if (isActive) {
          _webMaterializedTabs.add(i);
          return buildSlot(i);
        }
        return _webTabSlot(i, const SizedBox.shrink());
      });
      _webTabChildrenFeedSig = feedSig;
      _webTabChildrenHubSig = hubSig;
      _webBuiltActiveTab = active;
      _webTabChildren = next;
      // IndexedStack يُبقي عدة ListView في الشجرة — بدون هذا يتعارض PrimaryScrollController
      // ويظهر Uncaught Error عند فتح إعلاناتي/بعد تحديث الفيد.
      return PrimaryScrollController.none(
        child: IndexedStack(
          index: active,
          sizing: StackFit.expand,
          children: _webTabChildren!,
        ),
      );
    }

    return _DeferredTabBody(
      tabIndex: _tabIndex,
      deferFirstFrame: _tabIndex != 0,
      extraDeferFrames: 0,
      builder: (context) {
        switch (_tabIndex) {
          case 1:
            return _buildMyAdsHub();
          case 2:
            return _buildMySubmissionsBody();
          case 3:
            return _buildCartBody();
          case 4:
            return _buildSupportHubBody();
          case 0:
          default:
            return _buildHomeBody(
              homeItems,
              homeRequestsFiltered,
              loadedPropertyRows: homeLoadedPropertyRows,
              loadedRequestRows: _marketHomeRequests.length,
            );
        }
      },
    );
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

  Future<void> _loadPackageVersionLine() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _packageVersionLine = '${p.version} (${p.buildNumber})';
      });
    } catch (_) {}
  }

  void _showGuestAboutAppDialog() {
    AppAboutCredits.show(
      context,
      isAr: _isArabic,
      versionLine: _packageVersionLine,
    );
  }

  bool _dashboardCanGoBack() =>
      _dashboardBodyNavKey.currentState?.canPop() ?? false;

  String? _nestedTitleForRouteSettings(RouteSettings settings) {
    final n = (settings.name ?? '').trim();
    if (n.isEmpty) return null;
    if (n == '/dashboard/settings') {
      return _isArabic ? 'الإعدادات' : 'Settings';
    }
    if (n == '/dashboard/subscriptions') {
      return AppLocalizations.of(context)?.subscriptionsTitle ??
          (_isArabic ? 'الاشتراكات' : 'Subscriptions');
    }
    if (n == AppRoutes.marketInsights) {
      return AppLocalizations.of(context)?.marketInsightsTitle ??
          (_isArabic ? 'رؤى السوق' : 'Market insights');
    }
    if (n == '/desk/organization' || n == '/desk/owner') {
      return _isArabic ? 'إدارتي' : 'My desk';
    }
    if (n == '/dashboard/favorites') {
      return AppLocalizations.of(context)?.navFavorites ??
          (_isArabic ? 'المفضلة' : 'Favorites');
    }
    if (n == AppRoutes.inAppNotifications || n.contains('communication')) {
      return _isArabic ? 'الإشعارات' : 'Notifications';
    }
    return null;
  }

  void _syncNestedShellTitleFromNavigator() {
    if (!mounted) return;
    final canPop = _dashboardBodyNavKey.currentState?.canPop() ?? false;
    if (!canPop) {
      if (_nestedTitleStack.isNotEmpty) _nestedTitleStack.clear();
      if (_nestedShellTitle != null) {
        setState(() => _nestedShellTitle = null);
      } else {
        setState(() {});
      }
      return;
    }
    setState(() {
      _nestedShellTitle =
          _nestedTitleStack.isEmpty ? null : _nestedTitleStack.last;
    });
  }

  bool _onDashboardScrollForBottomNav(ScrollNotification n) {
    if (!mounted) return false;
    if (kIsWeb) return false;
    if (AppLayout.useDashboardSideNavigation(context)) return false;
    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta;
      if (d == null) return false;
      if (d > 5) {
        if (_bottomNavSlideVisible) {
          setState(() => _bottomNavSlideVisible = false);
        }
      } else if (d < -5) {
        if (!_bottomNavSlideVisible) {
          setState(() => _bottomNavSlideVisible = true);
        }
      }
    } else if (n is ScrollEndNotification) {
      if (!_bottomNavSlideVisible) {
        setState(() => _bottomNavSlideVisible = true);
      }
    }
    return false;
  }

  bool _popDashboardBodyRoute() {
    // أولاً جسم اللوحة (اشتراكات/دردشة/نماذج +) — لا تقفز إلى rootNavigator.
    final bodyNav = _dashboardBodyNavKey.currentState;
    if (bodyNav != null && bodyNav.canPop()) {
      bodyNav.pop();
      if (mounted && !_bottomNavSlideVisible) {
        setState(() => _bottomNavSlideVisible = true);
      }
      return true;
    }
    if (kIsWeb) {
      final root = Navigator.of(context, rootNavigator: true);
      if (!root.canPop()) return false;
      final name = ModalRoute.of(context)?.settings.name ?? '';
      if (name == '/userDashboard' || name == '/userdashboard' || name == '/') {
        return false;
      }
      root.pop();
      return true;
    }
    return false;
  }

  /// شورتز بملء الشاشة — خارج فلاتر الكل/طلبات/إعلانات.
  Future<void> _openHomeShortsFeed({required int slotsIndex}) async {
    final listings = _nestedDashboardHomeItems.isNotEmpty
        ? List<Property>.from(_nestedDashboardHomeItems)
        : List<Property>.from(_all);
    final requests = _nestedDashboardHomeRequests.isNotEmpty
        ? List<MarketPropertyRequestRow>.from(_nestedDashboardHomeRequests)
        : List<MarketPropertyRequestRow>.from(_marketHomeRequests);
    final items = <HomeShortsItem>[
      for (final p in listings) HomeShortsItem.property(p),
      for (final r in requests) HomeShortsItem.request(r),
    ];
    if (!mounted) return;
    setState(() => _bottomNavTransientIndex = slotsIndex);
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => HomeShortsFeedPage(
          items: items,
          isAr: _isArabic,
          onOpenProperty: (p) {
            Navigator.of(context, rootNavigator: true).pop();
            unawaited(_openDetails(p));
          },
          onOpenRequest: (r) {
            Navigator.of(context, rootNavigator: true).pop();
            unawaited(_openMarketRequestDetail(r));
          },
          onCompleteDeal: (item) {
            final p = item.property;
            if (p != null) {
              Navigator.of(context, rootNavigator: true).pop();
              unawaited(_addToCart(p));
            }
          },
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted) setState(() => _bottomNavTransientIndex = null);
  }

  /// رجوع عند جذر اللوحة: تأكيد ثم خروج آمن (لا تُترك جلسة مفتوحة على شاشة الدخول).
  Future<void> _handleDashboardRootBrowserBack() async {
    if (!mounted) return;
    final online = context.read<AppSession>().hasInternet;
    if (!online) return;
    final isAr = widget.lang.toLowerCase().startsWith('ar');
    if (_isGuest) {
      final ok = await AppBackRefreshDialogs.confirmLeaveGuest(context, isAr);
      if (!ok || !mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/entryChoice',
        (r) => false,
      );
      return;
    }
    final ok = await AppBackRefreshDialogs.confirmSignOut(context, isAr);
    if (!ok || !mounted) return;
    await SafeSignOutService.signOutAndNavigateToLogin(
      context,
      logoutReason: 'browser_back_exit',
    );
  }

  Future<void> _onDashboardPopInvoked(bool didPop) async {
    if (didPop) return;
    if (!mounted) return;
    if (!context.read<AppSession>().hasInternet) return;
    if (_popDashboardBodyRoute()) return;
    await _handleDashboardRootBrowserBack();
  }

  Future<void> _refreshOrgJoinRequestBadge() async {
    if (!mounted) return;
    if (_isGuest || !_orgNavIsOwner) {
      if (_orgPendingJoinCount != 0 && mounted) {
        setState(() => _orgPendingJoinCount = 0);
      }
      return;
    }
    try {
      final n = (await OrgTeamService(_sb).listPendingJoinRequests()).length;
      if (!mounted) return;
      if (n != _orgPendingJoinCount) {
        setState(() => _orgPendingJoinCount = n);
      }
    } catch (_) {}
  }

  void _ensureOrgJoinBadgePolling() {
    _orgJoinBadgeTimer?.cancel();
    _orgJoinBadgeTimer = null;
    if (_isGuest || !_orgNavIsOwner) return;
    _orgJoinBadgeTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      unawaited(_refreshOrgJoinRequestBadge());
    });
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
    langNotifier.removeListener(_onLiveAppearanceChanged);
    themeModeNotifier.removeListener(_onLiveAppearanceChanged);
    MarketingWorkflowHub.bucketsRevision
        .removeListener(_onMarketingWorkflowBucketsRevision);
    _disposeWorkflowRealtimeChannel();
    _disposeHomeFeedRealtimeChannel();
    InAppNotificationHub.onInboxInvalidate = null;
    InAppDashboardDeepLink.pending.removeListener(_onDashboardDeepLinkPending);
    _debounce?.cancel();
    _feedCacheRebuildDebounce?.cancel();
    _advancedSearchDraftTimer?.cancel();
    _appAudiencePollTimer?.cancel();
    _presenceHeartbeatTimer?.cancel();
    _authSub?.cancel();
    _orgJoinBadgeTimer?.cancel();
    _inlineSearchCtrl.dispose();
    _filterChipsHScrollCtrl.dispose();
    _dashboardOnboardingBackdropScroll.dispose();
    _ownerTabsCtrl?.dispose();
    _marketerTabsCtrl?.dispose();
    // ويب: بعد الخروج/تبديل الضيف يُسمح لـ UserDashboard التالي بالـ bootstrap.
    if (kIsWeb) {
      AppWebSoftRefresh.unregister();
      WebDashboardBootstrapGuard.reset();
    }
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
                  // الرئيسية فقط: الكل / الطلبات / الإعلانات.
                  // صفحتي وطلباتي/إعلاناتي: بحث + تحديث + متقدم (بدون تبويبات الرئيسية).
                  compactForMyPage: _tabIndex == 1 || _tabIndex == 2,
                  onRefresh: () async {
                    await _reloadAll();
                  },
                  showResultCount: _tabIndex == 0,
                  resultCount: _tabIndex == 0
                      ? (_homeFeedKind == HomeFeedKind.listings
                          ? homeItems.length
                          : _homeFeedKind == HomeFeedKind.requests
                              ? homeRequestsFiltered.length
                              : homeItems.length + homeRequestsFiltered.length)
                      : _tabIndex == 2
                          ? mySubmissionsCount
                          : 0,
                ),
              Expanded(
                // ويب: IndexedStack ذكي (لا يهدم إعلاناتي مع كل home.paint).
                // KeyedSubtree(tabIndex) السابق كان يعيد بناء الجسم بالكامل → عاصفة + Uncaught Error.
                child: kIsWeb
                    ? _buildDashboardTabBody(
                        homeItems: homeItems,
                        homeRequestsFiltered: homeRequestsFiltered,
                        homeLoadedPropertyRows: homeLoadedPropertyRows,
                      )
                    : IndexedStack(
                        index: _tabIndex,
                        sizing: StackFit.expand,
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
              partnerLine: _partnerOnboardingLine(),
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
        excludePropertiesInCart: !_isGuest && _uid.isNotEmpty,
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
    // حدّث كاش العرض المتزامن حتى تستخدمه بطاقات الرئيسية المختلطة.
    _nestedDashboardHomeItems = homeItems;
    _nestedDashboardHomeRequests = homeRequestsFiltered;
    _nestedDashboardHomePropertyPoolSize = homePropertyPool.length;
    final mixedTimeline = _sortBy == 'latest'
        ? buildMixedHomeTimeline(homeItems, homeRequestsFiltered)
        : const <HomeMixedFeedEntry>[];
    _nestedDashboardMixedEntries = mixedTimeline;
    final mixedHomeCount = _tabIndex == 0 &&
            _homeFeedKind == HomeFeedKind.all &&
            _sortBy == 'latest'
        ? mixedTimeline.length
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
          case 'about_app':
            _showGuestAboutAppDialog();
            break;
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
          case 'reports_dashboard':
            if (_isGuest) {
              _showLoginDialog();
            } else {
              final can = OrgPermissionManager.can(
                    _orgMembershipPermissions,
                    OrgPermissionKeys.viewReports,
                  ) ||
                  OrgPermissionManager.can(
                    _orgMembershipPermissions,
                    OrgPermissionKeys.viewAnalytics,
                  );
              if (!can) {
                AppHaptics.heavy();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isArabic
                          ? 'لا تملك صلاحية التقارير.'
                          : 'No permission to view reports.',
                    ),
                  ),
                );
                break;
              }
              unawaited(_pushBody<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ReportsDashboardScreen(),
                ),
              ));
            }
            break;
          case 'subscriptions_hub':
            if (_isGuest) {
              _showLoginDialog();
            } else {
              _openSubscriptionsHub(initialIndex: 0);
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
        _dashboardActionMenuItem(
          value: 'about_app',
          icon: Icons.info_outline_rounded,
          label: _isArabic ? 'عن التطبيق' : 'About the app',
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
        if (!_isGuest) ...[
          _dashboardActionMenuItem(
            value: 'subscriptions_hub',
            icon: Icons.subscriptions_outlined,
            label: l10n.subscriptionsMenuHub,
            badge: _subscriptionMenuBadge,
          ),
          _dashboardActionMenuItem(
            value: 'reports_dashboard',
            icon: Icons.assessment_outlined,
            label: _isArabic ? 'التقارير المتقدمة' : 'Reports',
          ),
        ],
        const PopupMenuDivider(),
        if (!_isGuest && _packageVersionLine.isNotEmpty)
          _dashboardActionMenuItem(
            value: '__version_line__',
            icon: Icons.tag_rounded,
            label: _isArabic
                ? 'الإصدار: $_packageVersionLine'
                : 'Version: $_packageVersionLine',
            enabled: false,
          ),
        if (!_isGuest && _packageVersionLine.isNotEmpty)
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

  Future<void> _openLiveAudienceStatsDialog() async {
    final ar = _isArabic;
    int? online;
    int? guests;
    Object? rpcError;
    unawaited(PresenceHeartbeatService.ping(_sb));
    try {
      final key = await PresenceHeartbeatService.clientKey(_sb);
      final raw = await _sb.rpc(
        'get_app_audience_stats',
        params: {'p_exclude_client_key': key},
      ).timeout(const Duration(seconds: 6));
      if (raw is Map) {
        online = (raw['online_now'] as num?)?.toInt();
        guests = (raw['online_guests'] as num?)?.toInt();
      }
    } catch (e) {
      try {
        final raw = await _sb
            .rpc('get_app_audience_stats')
            .timeout(const Duration(seconds: 6));
        if (raw is Map) {
          online = (raw['online_now'] as num?)?.toInt();
          guests = (raw['online_guests'] as num?)?.toInt();
        }
      } catch (e2) {
        rpcError = e2;
      }
    }
    if (!mounted) return;
    if (online != null) {
      setState(() => _appAudienceOnlineApprox = online);
    }

    final cs = Theme.of(context).colorScheme;
    final title = _audiencePartnersTitle(isAr: ar);
    final grad = LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [
        Color.lerp(cs.primaryContainer, cs.surface, 0.35)!,
        Color.lerp(cs.tertiaryContainer, cs.surface, 0.2)!,
      ],
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              Icons.groups_2_rounded,
                              color: cs.primary,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (rpcError != null)
                      Text(
                        ar
                            ? 'تعذّر استرجاع الأعداد من الخادم. أعد المحاولة بعد لحظات.'
                            : 'Could not load live counts. Please try again shortly.',
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      )
                    else ...[
                      _audienceStatTile(
                        ctx,
                        cs,
                        icon: Icons.online_prediction_rounded,
                        label: _audienceOnlineNowLabel(isAr: ar),
                        value: online?.toString() ?? '—',
                        highlight: true,
                      ),
                      const SizedBox(height: 12),
                      _audienceStatTile(
                        ctx,
                        cs,
                        icon: Icons.person_outline_rounded,
                        label: _audienceGuestsLabel(isAr: ar),
                        value: guests?.toString() ?? '—',
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          ar ? 'حسناً' : 'OK',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _audienceStatTile(
    BuildContext ctx,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    final bg = highlight
        ? cs.primary.withValues(alpha: 0.12)
        : cs.surface.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (highlight ? cs.primary : cs.outline)
              .withValues(alpha: highlight ? 0.35 : 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
              ),
            ),
            Text(
              value,
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardLiveAudienceButton(ColorScheme cs) {
    final n = _appAudienceOnlineApprox;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: Tooltip(
        message: _audiencePartnersTitle(isAr: _isArabic),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: cs.primary.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  AppHaptics.light();
                  unawaited(_openLiveAudienceStatsDialog());
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.groups_2_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (n != null)
              PositionedDirectional(
                end: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: n > 0 ? cs.error : cs.outline,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.surface, width: 1.2),
                  ),
                  child: Text(
                    n > 99 ? '99+' : '$n',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: n > 0 ? cs.onError : cs.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardNotificationsButton(AppLocalizations l10n, ColorScheme cs) {
    final attentionCount = _unreadNotificationsCount +
        _ownerOffersAttentionCount +
        _chatUnreadTotal;

    // لون الجرس ثابت (هوية التطبيق) — الشارة الحمراء وحدها للتنبيه.
    // سابقاً: error عند وجود غير مقروء → أحمر لبعض المستخدمين وأسود/أساسي لآخرين.
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: _IconBadgeButton(
        tooltip: l10n.communicationHubTitle,
        icon: attentionCount > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_outlined,
        badge: attentionCount,
        color: cs.primary,
        onPressed: () {
          AppHaptics.light();
          _openNotificationsPage();
        },
      ),
    );
  }

  Widget _dashboardMapButton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: Tooltip(
        message: widget.isAr ? 'خريطة الإعلانات والطلبات' : 'Listings map',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              AppHaptics.light();
              unawaited(_openMapDiscovery());
            },
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(Icons.map_outlined, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _readArgsInBuildOnce(context);
    final l10n = AppLocalizations.of(context)!;
    final hasInternet =
        context.select<AppSession, bool>((session) => session.hasInternet);
    final networkCheckBusy =
        context.select<AppSession, bool>((session) => session.networkCheckBusy);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bottomSlots = _dashboardBottomSlots();
    final navIndex = _bottomNavSelectedIndex(bottomSlots);
    final useSideNav = AppLayout.useDashboardSideNavigation(context);
    final bodyNavCanPop = _dashboardCanGoBack();

    Widget buildBottomNavBar(BoxConstraints constraints) {
      final w = constraints.maxWidth;
      final hideBottomLabels = w < 720;
      final compactBottomNav = hideBottomLabels || w < 680;
      final bar = NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: hideBottomLabels ? 0.01 : 11,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            );
          }),
        ),
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: NavigationBar(
            height: hideBottomLabels ? 56 : 68,
            labelBehavior: hideBottomLabels
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
              selectedIndex: navIndex,
              hideLabels: hideBottomLabels,
            ),
          ),
        ),
      );
      // ويب: ثابت بلا انزلاق — يمنع رفع الشاشة/الفراغ عند التحديث.
      if (kIsWeb) return bar;
      return SafeArea(
        top: false,
        child: bar,
      );
    }

    final dashboardScaffold = Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AqarBrandColors.bg,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: _isGuest ? 68 : 96,
        automaticallyImplyLeading: false,
        // X مقابل قائمة ⋮ — يظهر على الجوال والشاشات الكبيرة عند وجود صفحة للرجوع إليها.
        leading: bodyNavCanPop
            ? AppPageCloseButton(
                isArabic: _isArabic,
                tooltip: _isArabic ? 'إغلاق / رجوع' : 'Close / Back',
                onPressed: _popDashboardBodyRoute,
              )
            : null,
        title: _dashboardHomeAppBarTitle(l10n),
        actions: [
          if (!_isGuest &&
              _orgNavIsOwner &&
              _accountRoleLoaded &&
              _orgPendingJoinCount > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: _IconBadgeButton(
                tooltip: l10n.appBarOrgJoinRequestsTooltip,
                icon: Icons.how_to_reg_outlined,
                badge: _orgPendingJoinCount,
                color: cs.primary,
                onPressed: () {
                  unawaited(
                    _pushBody<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => MyOrganizationScreen(
                          lang: widget.lang,
                          initialTab: MyOrganizationTabKey.joinRequests,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          _dashboardMapButton(cs),
          _dashboardLiveAudienceButton(cs),
          _dashboardNotificationsButton(l10n, cs),
          _dashboardActionsMenu(l10n, cs),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onDashboardScrollForBottomNav,
        child: Navigator(
          key: _dashboardBodyNavKey,
          observers: <NavigatorObserver>[_dashboardBodyNavObserver],
          onGenerateInitialRoutes: (nav, initialRoute) => [
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/dashboard/root'),
              builder: (routeContext) => Builder(
                builder: (innerContext) {
                  final host = innerContext
                      .findAncestorStateOfType<_UserDashboardState>();
                  if (host == null) return const SizedBox.shrink();
                  return host._buildNestedDashboardBody(innerContext);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: useSideNav && _showBottomNavAddSlot
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
          : (kIsWeb
              ? LayoutBuilder(
                  builder: (context, constraints) =>
                      buildBottomNavBar(constraints),
                )
              : ClipRect(
                  child: AnimatedSlide(
                    duration: AppMotionPolicy.barSlide,
                    curve: AppMotionPolicy.curve,
                    offset: _bottomNavSlideVisible
                        ? Offset.zero
                        : const Offset(0, 1.15),
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          buildBottomNavBar(constraints),
                    ),
                  ),
                )),
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

    if (kIsWeb) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          unawaited(_onDashboardPopInvoked(didPop));
        },
        child: mainChrome,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        unawaited(_onDashboardPopInvoked(didPop));
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
              if (!hasInternet && !kIsWeb)
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
                                        onPressed: networkCheckBusy
                                            ? null
                                            : () => context
                                                .read<AppSession>()
                                                .refreshConnectivity(
                                                  userInitiated: true,
                                                ),
                                        icon: networkCheckBusy
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
    // ضيف ومسجّل: نفس التبويبات دائماً — الحماية عبر شيت الدخول عند الضغط.
    return const <DashboardBottomSlot>[
      DashboardBottomSlot.home,
      DashboardBottomSlot.shorts,
      DashboardBottomSlot.myAds,
      DashboardBottomSlot.mySubmissions,
      DashboardBottomSlot.addListing,
      DashboardBottomSlot.myDesk,
      DashboardBottomSlot.cart,
      DashboardBottomSlot.support,
    ];
  }

  String _dashboardNavLabel(String label, {bool allowWrap = false}) {
    // مسافات غير قابلة للكسر + وصلة غير قابلة للكسر حول "/" حتى لا يلتف «طلباتي/إعلاناتي».
    var s = label.replaceAll(' ', '\u00A0');
    s = s.replaceAll('/', '\u2060/\u2060');
    if (!allowWrap) {
      s = s.replaceAll('-', '\u2011');
    }
    return s;
  }

  int _bottomNavSelectedIndex(List<DashboardBottomSlot> slots) {
    final transient = _bottomNavTransientIndex;
    if (transient != null && transient >= 0 && transient < slots.length) {
      return transient;
    }
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
          // أبرز التبويب حتى لو كانت صلاحية السلة متغيّرة — يمنع الرجوع البصري للرئيسية.
          if (_tabIndex == 3) return i;
          break;
        case DashboardBottomSlot.support:
          if (_tabIndex == 4) return i;
          break;
        case DashboardBottomSlot.shorts:
        case DashboardBottomSlot.myDesk:
        case DashboardBottomSlot.addListing:
          break;
      }
    }
    return 0;
  }

  bool _ensureAccountRoleLoadedForNav() {
    if (_accountRoleLoaded) return true;
    // لا تحجب النقرة — حمّل الصلاحيات في الخلفية وافتح التبويب فوراً.
    unawaited(_loadAccountRole());
    return true;
  }

  void _onDashboardBottomNavSelected(List<DashboardBottomSlot> slots, int i) {
    // ويب: لا unfocus متزامن على شجرة ضخمة — كان يزيد تأخير النقرة.
    if (!kIsWeb) {
      FocusScope.of(context).unfocus();
    }
    if (!_bottomNavSlideVisible) {
      _bottomNavSlideVisible = true;
    }
    final slot = slots[i];
    // ثبّت التمييز فوراً للتبويبات الحقيقية حتى لا يومض ثم يعود للرئيسية.
    final instantTab = switch (slot) {
      DashboardBottomSlot.home => 0,
      DashboardBottomSlot.myAds => 1,
      DashboardBottomSlot.mySubmissions => 2,
      DashboardBottomSlot.cart => 3,
      DashboardBottomSlot.support => 4,
      _ => null,
    };
    if (instantTab != null && _tabIndex != instantTab) {
      setState(() {
        _tabIndex = instantTab;
        _bottomNavTransientIndex = null;
        if (kIsWeb) _webVisitedTabs.add(instantTab);
      });
    } else if (slot == DashboardBottomSlot.shorts ||
        slot == DashboardBottomSlot.myDesk) {
      setState(() => _bottomNavTransientIndex = i);
    }

    // أغلق مسارات الجسم (إضافة إعلان…) مع حارس النموذج — لا popUntil أعمى يعلّق عند canPop=false.
    unawaited(() async {
      final ok = await _popBodyRoutesWithFormGuard();
      if (!ok || !mounted) {
        if (mounted && _bottomNavTransientIndex != null) {
          setState(() => _bottomNavTransientIndex = null);
        }
        return;
      }
      _applyDashboardBottomNavSelection(slots, i);
    }());
  }

  void _applyDashboardBottomNavSelection(
    List<DashboardBottomSlot> slots,
    int i,
  ) {
    // إن كانت جولة التعريف تغطي الشاشة — أغلقها عند تنقّل يدوي دون إعادة التبويب للرئيسية.
    if (_showDashboardOnboarding) {
      unawaited(_completeDashboardOnboarding(resetTabToHome: false));
    }

    if (_isGuest) {
      final slot = slots[i];
      if (slot != DashboardBottomSlot.home &&
          slot != DashboardBottomSlot.support &&
          slot != DashboardBottomSlot.shorts) {
        unawaited(() async {
          final res = await showGuestAuthRequiredSheet(
            context: context,
            isAr: _isArabic,
          );
          if (!mounted || res == null) return;
          if (res == GuestAuthRequiredResult.login) {
            _navigateToLogin();
          } else {
            await Navigator.of(context, rootNavigator: true)
                .pushNamed('/register');
          }
        }());
        return;
      }
    }

    void goTab(int tab) {
      if (_tabIndex == tab) return;
      WebBootstrapDiag.log('nav.tab', '→ $tab');
      // ويب: حدّث المؤشر فوراً — الجسم IndexedStack لا يهدم الرئيسية.
      setState(() {
        _tabIndex = tab;
        _bottomNavTransientIndex = null;
        if (kIsWeb) _webVisitedTabs.add(tab);
      });
    }

    switch (slots[i]) {
      case DashboardBottomSlot.home:
        goTab(0);
        break;
      case DashboardBottomSlot.shorts:
        unawaited(_openHomeShortsFeed(slotsIndex: i));
        break;
      case DashboardBottomSlot.myAds:
        _ensureAccountRoleLoadedForNav();
        if (_accountRoleLoaded && !_isGuest && !_showBottomNavMyAdsSlot) {
          _showNotification(
            _isArabic ? 'تنبيه' : 'Notice',
            _isArabic
                ? 'تبويب إعلاناتي غير متاح بصلاحياتك الحالية.'
                : 'My ads tab is not available with your current permissions.',
            isError: false,
          );
          return;
        }
        // ويب: جهّز TabController قبل goTab — يمنع تجمّد المسوّق عند null ctrl.
        if (kIsWeb) _ensureSubTabControllers();
        // أول ما يُفتح صفحتي: أول تبويب يمين (index 0 في العربية).
        _focusMyPageFirstSubTab();
        goTab(1);
        if (!_isGuest) {
          // كل المنصات: حمّل صفحتي فور فتح التبويب دون انتظار تفاعل إضافي.
          _ensureSubTabControllers();
          unawaited(_ensureMyAdsHubDataLoaded());
        }
        break;
      case DashboardBottomSlot.mySubmissions:
        _ensureAccountRoleLoadedForNav();
        if (_accountRoleLoaded &&
            !_isGuest &&
            !_showBottomNavMySubmissionsSlot) {
          _showNotification(
            _isArabic ? 'تنبيه' : 'Notice',
            _isArabic
                ? 'تبويب طلباتي غير متاح بصلاحياتك الحالية.'
                : 'My requests tab is not available with your current permissions.',
            isError: false,
          );
          return;
        }
        if (kIsWeb) _ensureSubTabControllers();
        goTab(2);
        // طلباتي: حمّل mine + طلباتي السوق المخصّصة فوراً.
        if (!_isGuest) {
          unawaited(() async {
            await Future.wait([
              if (_mine.isEmpty) _loadMineAndOffers(force: false),
              _loadMyMarketSubmissions(force: false),
            ]);
            if (mounted) setState(() {});
          }());
        }
        break;
      case DashboardBottomSlot.addListing:
        _ensureAccountRoleLoadedForNav();
        if (_accountRoleLoaded && !_showBottomNavAddSlot) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCenterPlus();
        });
        break;
      case DashboardBottomSlot.myDesk:
        _ensureAccountRoleLoadedForNav();
        if (_accountRoleLoaded && !_showBottomNavMyDeskSlot) {
          if (mounted) setState(() => _bottomNavTransientIndex = null);
          _showNotification(
            _isArabic ? 'تنبيه' : 'Notice',
            _isArabic
                ? 'إدارتي غير متاحة لهذا الحساب أو بصلاحياتك الحالية.'
                : 'My desk is not available for this account or your current permissions.',
            isError: false,
          );
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(() async {
            await _openMyDeskNav();
            if (mounted) setState(() => _bottomNavTransientIndex = null);
          }());
        });
        break;
      case DashboardBottomSlot.cart:
        _ensureAccountRoleLoadedForNav();
        if (_isGuest) return;
        goTab(3);
        break;
      case DashboardBottomSlot.support:
        goTab(4);
        break;
    }
  }

  List<NavigationDestination> _dashboardBottomDestinations(
      AppLocalizations l10n, List<DashboardBottomSlot> slots,
      {bool compact = false, int selectedIndex = 0, bool hideLabels = false}) {
    var i = 0;
    return slots.map((slot) {
      final selected = i++ == selectedIndex;
      Widget wrap(Widget child) =>
          MotionSelectedIcon(selected: selected, child: child);
      String lab(String raw) =>
          hideLabels ? '' : _dashboardNavLabel(raw, allowWrap: false);
      // تعطيل تلميح Material عند ظهور الاسم تحت الرمز (تجنب نصّين عند المرور).
      const noTip = '';
      switch (slot) {
        case DashboardBottomSlot.home:
          return NavigationDestination(
            icon: wrap(const Icon(Icons.home_outlined)),
            selectedIcon: wrap(const Icon(Icons.home)),
            label: lab(l10n.navHome),
            tooltip: noTip,
          );
        case DashboardBottomSlot.shorts:
          return NavigationDestination(
            icon: wrap(const Icon(Icons.smart_display_outlined)),
            selectedIcon: wrap(const Icon(Icons.smart_display)),
            label: lab(_isArabic ? 'شورتز' : 'Shorts'),
            tooltip: noTip,
          );
        case DashboardBottomSlot.myAds:
          return NavigationDestination(
            icon: wrap(const Icon(Icons.list_alt_outlined)),
            selectedIcon: wrap(const Icon(Icons.list_alt)),
            label: lab(l10n.navMyAds),
            tooltip: noTip,
          );
        case DashboardBottomSlot.mySubmissions:
          return NavigationDestination(
            icon: wrap(const Icon(Icons.assignment_turned_in_outlined)),
            selectedIcon: wrap(const Icon(Icons.assignment_turned_in)),
            label: lab(l10n.navMySubmissions),
            tooltip: noTip,
          );
        case DashboardBottomSlot.addListing:
          final csAdd = Theme.of(context).colorScheme;
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
            icon: wrap(addChip(filled: false)),
            selectedIcon: wrap(addChip(filled: true)),
            label: lab(_isArabic ? 'إضافة إعلان' : l10n.navAdd),
            tooltip: noTip,
          );
        case DashboardBottomSlot.myDesk:
          final deskAlert = !_isGuest &&
              _orgNavIsOwner &&
              _accountRoleLoaded &&
              _orgPendingJoinCount > 0;
          // بلا Tooltip عند المرور — الاسم تحت الرمز كافٍ (ويب ويندوز/جوال/تطبيق).
          return NavigationDestination(
            icon: wrap(
              _DeskNavBottomIcon(
                icon: Icons.dashboard_outlined,
                showDot: deskAlert,
              ),
            ),
            selectedIcon: wrap(
              _DeskNavBottomIcon(
                icon: Icons.dashboard,
                showDot: deskAlert,
                filled: true,
              ),
            ),
            label: lab(l10n.navMyDesk),
            tooltip: noTip,
          );
        case DashboardBottomSlot.cart:
          final cartCs = Theme.of(context).colorScheme;
          return NavigationDestination(
            icon: wrap(
              _BadgeIcon(
                icon: Icons.handshake_outlined,
                badge: _isGuest ? 0 : _cartCount,
                color: _cartCount > 0 ? cartCs.error : _brandPrimary,
              ),
            ),
            selectedIcon: wrap(const Icon(Icons.handshake)),
            label: lab(l10n.navCart),
            tooltip: noTip,
          );
        case DashboardBottomSlot.support:
          return NavigationDestination(
            icon: wrap(const Icon(Icons.support_agent_outlined)),
            selectedIcon: wrap(const Icon(Icons.support_agent)),
            label: lab(_isArabic ? 'الدعم الفني' : l10n.navSupport),
            tooltip: noTip,
          );
      }
    }).toList();
  }

  List<NavigationRailDestination> _dashboardRailDestinations(
    AppLocalizations l10n,
    List<DashboardBottomSlot> slots,
  ) {
    final selected = _bottomNavSelectedIndex(slots);
    final nav = _dashboardBottomDestinations(
      l10n,
      slots,
      selectedIndex: selected,
    );
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
    final raw = _resolvedGreetingDisplayName();
    if (raw.isEmpty) {
      return l10n.navHome;
    }
    final width = MediaQuery.sizeOf(context).width;
    final piece = _displayNameForDashboardTitle(
      raw,
      compact: width < 480,
      medium: width < 720,
    );
    final display =
        piece.isNotEmpty ? piece : DashboardGreeting.firstChunk(raw);
    return DashboardGreeting.appBarLine(
      isAr: _isArabic,
      displayName: display,
    );
  }

  /// عنوان الرئيسية: تحية → الاسم → مسمّى الصفحة (ذكي بلا التفاف على الشاشات الصغيرة).
  Widget _dashboardHomeAppBarTitle(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final compactChrome = width < 720;
    final tabTitle = _tabTitle();

    if (_isGuest) {
      final title = _tabIndex == 0 ? l10n.navHome : tabTitle;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isArabic ? 'تصفّح كضيف' : 'Browsing as guest',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _isArabic ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                height: 1.15,
              ),
            ),
          ),
        ],
      );
    }

    final salute = DashboardGreeting.partnerSalutationLine(isAr: _isArabic);
    final raw = _resolvedGreetingDisplayName();
    final narrowToolbar = width < 480;
    final mediumToolbar = width < 720;
    final nameLine = _displayNameForDashboardTitle(
      raw,
      compact: narrowToolbar,
      medium: mediumToolbar,
    );
    // دائماً اسم الصفحة تحت الاسم — مسار مضمّن (إدارتي/إعدادات) أو التبويب الحالي.
    final nested = (_nestedShellTitle ?? '').trim();
    final pageLine = nested.isNotEmpty
        ? nested
        : (_tabIndex == 0 && !compactChrome ? l10n.navHome : tabTitle);

    final subStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: cs.onSurfaceVariant,
      height: 1.15,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final nameSize = constraints.maxWidth < 200
            ? 13.5
            : (constraints.maxWidth < 280 ? 15.0 : 16.5);
        final pageSize = constraints.maxWidth < 220 ? 11.0 : 12.5;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  _isArabic ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                salute,
                maxLines: 1,
                softWrap: false,
                style: subStyle,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  _isArabic ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                nameLine.isNotEmpty
                    ? nameLine
                    : (_tabIndex == 0 ? l10n.navHome : tabTitle),
                maxLines: 1,
                softWrap: false,
                textAlign: _isArabic ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: nameSize,
                  height: 1.1,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (pageLine.isNotEmpty) ...[
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment:
                    _isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  pageLine,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: _isArabic ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: pageSize,
                    height: 1.1,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
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
    return CompoundDisplayName.forToolbar(
      fullName,
      compact: compact,
      medium: medium ||
          (!compact && fullName.trim().split(RegExp(r'\s+')).length >= 4),
    );
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
  Future<void> _maybeConsumeDashboardTourReplayFromPrefs() async {
    if (!mounted || _isGuest) return;
    try {
      if (!await DeviceFirstRunPrefs.consumeReplayPending()) return;
      await DeviceFirstRunPrefs.clearTourAndAccentForReplay();
      if (!mounted) return;
      setState(() {
        _offerAccentAfterTourReplay = true;
        _showDashboardOnboarding = true;
        _tabIndex = 0;
      });
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    final embed = MediaQuery.sizeOf(context).width >= 580;

    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/dashboard/settings'),
        builder: (_) => SettingsPage(embedAppBar: embed),
      ),
    );
  }

  Future<void> _openMarketInsights() async {
    if (!mounted) return;
    final embed = MediaQuery.sizeOf(context).width >= 580;
    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.marketInsights),
        builder: (_) =>
            MarketInsightsPage(lang: widget.lang, embedAppBar: embed),
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
    final searchHint = switch (_tabIndex) {
      1 => _isArabic
          ? 'بحث في صفحتي (عنوان، موقع، وصف…)'
          : 'Search My page (title, location, description…)',
      2 => _isArabic
          ? 'بحث في طلباتي / إعلاناتي'
          : 'Search My requests / listings',
      _ => _isArabic
          ? 'بحث سريع بالعنوان أو الموقع أو الوصف'
          : 'Quick search by title, location or description',
    };

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

    Future<void> runToolbarRefresh() async {
      if (!mounted) return;
      setState(() => _feedFilterBusy = true);
      try {
        await _retryWithOfflineHint(onRefresh);
      } finally {
        if (mounted) setState(() => _feedFilterBusy = false);
      }
    }

    final refreshBtn = FilledButton.icon(
      onPressed: () async => await runToolbarRefresh(),
      style: compactFilledStyle,
      icon: const Icon(Icons.refresh),
      label: Text(
        _isArabic ? 'تحديث' : 'Refresh',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final advActive = _hasActiveTopFilters;
    final advancedSearchActiveStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
    );
    final advancedSearchBtn = advActive
        ? FilledButton.icon(
            onPressed: _openSearchFiltersSheet,
            style: advancedSearchActiveStyle,
            icon: const Icon(Icons.tune),
            label: Text(
              _isArabic ? 'متقدم' : 'Advanced',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : OutlinedButton.icon(
            onPressed: _openSearchFiltersSheet,
            style: compactOutlinedStyle,
            icon: const Icon(Icons.tune),
            label: Text(
              _isArabic ? 'متقدم' : 'Advanced',
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
              hintText: searchHint,
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
            color: cs.surfaceContainerHighest.withOpacity(0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _brandPrimary.withValues(alpha: _op(22)),
            ),
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
                    advancedSearchBtn,
                    refreshBtn,
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 8),
                      feedKindTabs,
                      const SizedBox(height: 8),
                      stretchRow(topActions),
                      if (_isNearestMode || _hasActiveTopFilters) ...[
                        const SizedBox(height: 6),
                        stretchRow([
                          if (_isNearestMode) clearNearestBtn,
                          if (_hasActiveTopFilters) clearAllBtn,
                        ]),
                      ],
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
              child: Builder(
                builder: (ctx) {
                  final dealBlocked = ctx.select<AppSubscriptionGate, bool>(
                    (g) => g.shouldShowSubscribeInsteadOfDeal,
                  );
                  return _MarketRequestListingStyleCard(
                    request: r,
                    isAr: _isArabic,
                    bankColor: _brandPrimary,
                    currentUserId: _uid.isEmpty ? 'guest' : _uid,
                    timeAgo: _timeAgo,
                    priorityLabel: _marketRequestPriorityL10nLabel(
                      l10n,
                      r.requestPriority,
                    ),
                    onOpen: () => _openMarketRequestDetail(r),
                    onSubmitOffer: _isGuest
                        ? null
                        : () => _openMarketRequestDetail(
                              r,
                              autoOpenSubmitOffer: true,
                            ),
                    dealSubscriptionBlocked: dealBlocked,
                    onSubscribeForDeal: _isGuest || !dealBlocked
                        ? null
                        : () => unawaited(
                              _openSubscriptionsFromGate(
                                SubscriptionGateAction.completeMarketDeal,
                              ),
                            ),
                    homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
                    onRestoreMarketRequest:
                        _isGuest ? null : _onRestoreMarketRequest,
                    onHomeHideMarketRequest: _isGuest
                        ? (r) async => _showLoginDialog()
                        : _onHomeHideMarketRequest,
                    onHomeReportMarketRequest:
                        _isGuest ? null : _onHomeReportMarketRequest,
                    onCopyMarketRequestWebLink: _copyMarketRequestPublicLink,
                    onShareMarketRequestFromCard: _shareMarketRequestFromCard,
                  );
                },
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
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return const SizedBox.shrink();
    }
    final onboardingScroll = _scrollControllerForOnboardingTab(0);
    final dealSubBlocked = context.select<AppSubscriptionGate, bool>(
      (g) => g.shouldShowSubscribeInsteadOfDeal,
    );
    void openDealSubscribe() {
      unawaited(
        _openSubscriptionsFromGate(SubscriptionGateAction.completeMarketDeal),
      );
    }

    final showListings = _homeFeedKind == HomeFeedKind.all ||
        _homeFeedKind == HomeFeedKind.listings;
    final showRequests = _homeFeedKind == HomeFeedKind.all ||
        _homeFeedKind == HomeFeedKind.requests;

    // «الكل»: انتظر الإعلانات وطلبات السوق. سابقاً كان loading=_loadingHome فقط
    // فيُرجع SizedBox.shrink() أثناء تحميل الطلبات → شاشة رئيسية فارغة/معلّقة.
    final homeFeedStillLoading = switch (_homeFeedKind) {
      HomeFeedKind.listings => _loadingHome,
      HomeFeedKind.requests => _loadingMarketRequests,
      HomeFeedKind.all => _loadingHome || _loadingMarketRequests,
    };
    final homeFeedLoadingSince =
        _loadingHome ? _homeLoadingSince : _marketRequestsLoadingSince;

    final fallback = _loadingWithFallback(
      loading: homeFeedStillLoading,
      since: homeFeedLoadingSince,
      title: _isArabic ? 'جارٍ التحميل…' : 'Loading…',
      subtitle: _isArabic
          ? 'إذا استمر التحميل، اضغط تحديث.'
          : 'If loading continues, tap refresh.',
      onRetry: () => _retryWithOfflineHint(_reloadAll),
    );

    if (_homeFeedKind == HomeFeedKind.requests) {
      if (_loadingMarketRequests &&
          homeRequestsFiltered.isEmpty &&
          _marketHomeRequests.isEmpty) {
        return const PropertyCardSkeletonList(count: 6, topPadding: 16);
      }
    } else if (_homeFeedKind == HomeFeedKind.all) {
      // لا نُجمّد الرئيسية بالكامل إن وُجدت طلبات سوق أو إعلانات جاهزة لأحد المصدرين.
      final hasAnyFeedContent = homeItems.isNotEmpty ||
          homeRequestsFiltered.isNotEmpty ||
          _all.isNotEmpty ||
          _marketHomeRequests.isNotEmpty;
      if (!hasAnyFeedContent && homeFeedStillLoading) {
        return fallback;
      }
    } else if (_loadingHome && homeItems.isEmpty && _all.isEmpty) {
      // لا تُظهر شاشة بيضاء/هيكل إذا كانت البطاقات موجودة مسبقاً أثناء التحديث.
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
    final mixedReady = _homeFeedKind == HomeFeedKind.all &&
        _sortBy == 'latest' &&
        _nestedDashboardMixedEntries.isNotEmpty;

    // لا تُظهر «لا توجد بطاقات» إن وُجدت تسليمة مختلطة جاهزة (كان يسبق رسم البطاقات).
    // ولا أثناء أول تحميل قبل اكتمال الجلب — الهيكل العظمي بدل رسالة فارغة مضلّلة.
    final homeFetchNeverCompleted = _lastHomeFetch == null &&
        (_loadingHome ||
            _loadingMarketRequests ||
            homeFeedStillLoading ||
            (_all.isEmpty && _marketHomeRequests.isEmpty));
    if (listingsEmpty &&
        requestsEmpty &&
        !mixedReady &&
        homeFetchNeverCompleted) {
      return const PropertyCardSkeletonList(count: 6, topPadding: 16);
    }
    if (listingsEmpty && requestsEmpty && !mixedReady) {
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
      final pipeL = _nestedDashboardPipelineL;
      final pipeR = _nestedDashboardPipelineR;
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

    // ويب: لا تستخدم التسليمة المختلطة — كانت تُظهر «النتائج: N» بلا بطاقات.
    // اعرض شبكة الإعلانات + قسم الطلبات مباشرة (أوثق وأسرع للرسم).
    final useMergedTimeline = !kIsWeb &&
        _homeFeedKind == HomeFeedKind.all &&
        _sortBy == 'latest' &&
        showListings &&
        showRequests;

    // ابنِ التسليمة دائماً من القوائم الممرَّرة — لا تعتمد على كاش قد يفرغ الإطار.
    var mixedEntries = useMergedTimeline
        ? (homeItems.isNotEmpty || homeRequestsFiltered.isNotEmpty
            ? buildMixedHomeTimeline(homeItems, homeRequestsFiltered)
            : _nestedDashboardMixedEntries)
        : const <HomeMixedFeedEntry>[];
    if (useMergedTimeline &&
        mixedEntries.isEmpty &&
        (homeItems.isNotEmpty || homeRequestsFiltered.isNotEmpty)) {
      mixedEntries = <HomeMixedFeedEntry>[
        ...homeItems.map(HomeMixedFeedEntry.listing),
        ...homeRequestsFiltered.map(HomeMixedFeedEntry.request),
      ];
    }

    final showRequestsBelowListings = _homeFeedKind == HomeFeedKind.listings &&
        homeRequestsFiltered.isNotEmpty;
    final webHomeHasRequestsBlock = !useMergedTimeline &&
        ((showRequests || showRequestsBelowListings) &&
            homeRequestsFiltered.isNotEmpty);
    final gridStandaloneScrollOnWeb = kIsWeb &&
        !useMergedTimeline &&
        showListings &&
        homeItems.isNotEmpty &&
        !webHomeHasRequestsBlock;

    final mixedBlock = (!useMergedTimeline || mixedEntries.isEmpty)
        ? const SizedBox.shrink()
        : RepaintBoundary(
            child: _HomeMixedTimeline(
              entries: mixedEntries,
              // ويب: مرّر المتحكم صراحة وprimaryScroll=false — primary:true كان يُظهر النتائج بلا بطاقات.
              scrollController: onboardingScroll,
              primaryScroll: true,
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
              suppressPublicOwnerIdentityOnCards: false,
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
              onCopyMarketRequestWebLink: _copyMarketRequestPublicLink,
              onShareMarketRequestFromCard: _shareMarketRequestFromCard,
            ),
          );

    final grid = useMergedTimeline
        ? const SizedBox.shrink()
        : ((!showListings || homeItems.isEmpty)
            ? const SizedBox.shrink()
            : RepaintBoundary(
                child: _PropertyGrid(
                  items: homeItems,
                  scrollController:
                      gridStandaloneScrollOnWeb ? onboardingScroll : null,
                  primaryScroll: gridStandaloneScrollOnWeb,
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
                  suppressPublicOwnerIdentityOnCards: false,
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

    // وضع «الكل»: لا تُظهر بانر الفلاتر إن وُجدت نتائج ظاهرة من أحد المصدرين
    // (كان يظهر «البيانات موجودة لكن الفلاتر…» رغم listings=1 في الويب).
    final anyVisibleFeed =
        homeItems.isNotEmpty || homeRequestsFiltered.isNotEmpty;
    final showFilterHint = _homeFeedKind == HomeFeedKind.all
        ? (!anyVisibleFeed &&
            (listingsHiddenByFilters || requestsHiddenByFilters))
        : (listingsHiddenByFilters || requestsHiddenByFilters);

    final filterHintBanner = showFilterHint
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

    // ويب: قائمة واحدة قابلة للتمرير داخل Expanded — تجنّب ListView shrinkWrap داخل SingleChildScrollView.
    if (kIsWeb && useMergedTimeline && mixedEntries.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterHintBanner,
          if (suppressFullPageHomeListingError && !_isGuest) ...[
            Material(
              color: cs.errorContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            ? 'تعذّر تحديث إعلانات العقارات؛ طلبات السوق تظهر أدناه.'
                            : 'Property listings could not refresh; market requests below.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onErrorContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(child: mixedBlock),
        ],
      );
    }

    // ويب: ارسم البطاقات مباشرة — تجنّب LayoutBuilder/grid shrink داخل ListView.
    if (kIsWeb) {
      var paintListings = showListings ? homeItems : const <Property>[];
      var paintRequests = (showRequests || showRequestsBelowListings)
          ? homeRequestsFiltered
          : const <MarketPropertyRequestRow>[];
      if (paintListings.isEmpty &&
          paintRequests.isEmpty &&
          (loadedPropertyRows > 0 || loadedRequestRows > 0)) {
        WebBootstrapDiag.warn(
          'home.paint',
          'filter emptied UI — fallback raw '
              'listings=${_all.length} requests=${_marketHomeRequests.length}',
        );
        if (showListings) {
          paintListings = List<Property>.from(_all);
        }
        if (showRequests || showRequestsBelowListings) {
          paintRequests = _isGuest || _uid.isEmpty
              ? List<MarketPropertyRequestRow>.from(_marketHomeRequests)
              : _marketHomeRequests
                  .where((r) => r.requesterId != _uid)
                  .toList();
        }
      }
      // لا تُغرق الـ Console — سجّل عند تغيّر العدد فقط.
      final paintSig =
          '${paintListings.length}|${paintRequests.length}|$_homeFeedKind';
      if (_lastWebHomePaintSig != paintSig) {
        _lastWebHomePaintSig = paintSig;
        WebBootstrapDiag.log(
          'home.paint',
          'direct listings=${paintListings.length} requests=${paintRequests.length} kind=$_homeFeedKind',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterHintBanner,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // شاشات كبيرة ≥600: أعمدة متعددة؛ جوال/ضيّق: عمود واحد — دون GridView shrink.
                final cross =
                    _homeListingGridCrossAxisCount(constraints.maxWidth);
                const spacing = 12.0;
                final equalH = _homeListingGridEqualCardHeight(
                  maxWidth: constraints.maxWidth,
                  crossAxisCount: cross,
                  horizontalPadding: 24,
                  spacing: spacing,
                );
                // خليط مرتّب: المستعجل/الفوري المدفوع أولاً ثم الأحدث.
                final mixedPaint = buildMixedHomeTimeline(
                  paintListings,
                  paintRequests,
                  limit: paintListings.length + paintRequests.length,
                );
                final totalCards = mixedPaint.length;
                if (totalCards == 0) {
                  // أثناء التحميل أو قبل أول جلب ناجح: لا رسالة فارغة مضلّلة.
                  if (homeFeedStillLoading ||
                      _lastHomeFetch == null ||
                      loadedPropertyRows > 0 ||
                      loadedRequestRows > 0) {
                    return const PropertyCardSkeletonList(
                      count: 6,
                      topPadding: 16,
                    );
                  }
                  return ListView(
                    controller: onboardingScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 48, 12, 24),
                    children: [
                      Text(
                        _isArabic ? 'لا توجد بطاقات للعرض' : 'No cards to show',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                }

                Widget listingCard(Property p) {
                  final isOwner = p.ownerId == _uid;
                  return _RealEstateCard(
                    property: p,
                    isOwner: isOwner,
                    isAr: _isArabic,
                    bankColor: _brandPrimary,
                    favorite: !_isGuest && _isFav(p.id),
                    onToggleFav: () => _toggleFav(p.id),
                    onOpenDetails: () => _openDetails(p),
                    activeCartHoldsCount: _activeReservationHoldCount(p.id),
                    isReserved: _isReservedByAnyone(p.id),
                    reservedUntil: _reservedUntil(p.id),
                    reservedByName: _reservedByName(p.id),
                    onAddToCart: _cartReservationFeaturesEnabled
                        ? () => _addToCart(p)
                        : null,
                    currentUserId: _uid.isEmpty ? 'guest' : _uid,
                    showEditDelete: false,
                    onEditProperty: null,
                    onDeleteProperty: null,
                    timeAgo: _timeAgo,
                    canShowCartButton: _cartReservationFeaturesEnabled,
                    showListingQuickActions: false,
                    suppressPublicOwnerIdentity: false,
                    // الضيف: لا بيانات مسوّق على بطاقة الرئيسية.
                    showRegulatoryIdentityOnCard: !_isGuest,
                    omitMarketingLicenseEntriesOnCard: true,
                    preferStaticPrimaryImage: true,
                    onCopyListingWebLink: _copyListingPublicLink,
                    onShareListingFromCard: () => _shareListingFromCard(p),
                    onHomeHideFromFeed: _isGuest
                        ? (x) async => _showLoginDialog()
                        : _onHomeHideProperty,
                    onHomeReportListing: _isGuest
                        ? (x) async => _showLoginDialog()
                        : _onHomeReportProperty,
                    homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
                    onRestorePropertyToHome:
                        _isGuest ? null : _onRestorePropertyToHome,
                    onWithdrawPropertyReport:
                        _isGuest ? null : _onWithdrawPropertyReport,
                  );
                }

                Widget requestCard(MarketPropertyRequestRow r) {
                  return _MarketRequestListingStyleCard(
                    request: r,
                    isAr: _isArabic,
                    bankColor: _brandPrimary,
                    currentUserId: _uid.isEmpty ? 'guest' : _uid,
                    timeAgo: _timeAgo,
                    priorityLabel: _marketRequestPriorityL10nLabel(
                      l10n,
                      r.requestPriority,
                    ),
                    onOpen: () => _openMarketRequestDetail(r),
                    onSubmitOffer: _isGuest
                        ? null
                        : () => _openMarketRequestDetail(
                              r,
                              autoOpenSubmitOffer: true,
                            ),
                    dealSubscriptionBlocked: dealSubBlocked,
                    onSubscribeForDeal:
                        _isGuest || !dealSubBlocked ? null : openDealSubscribe,
                    homeFeedShowsHiddenOnly: _homeShowHiddenOnly,
                    onRestoreMarketRequest:
                        _isGuest ? null : _onRestoreMarketRequest,
                    onHomeHideMarketRequest: _isGuest
                        ? (row) async => _showLoginDialog()
                        : _onHomeHideMarketRequest,
                    onHomeReportMarketRequest:
                        _isGuest ? null : _onHomeReportMarketRequest,
                    onCopyMarketRequestWebLink: _copyMarketRequestPublicLink,
                    onShareMarketRequestFromCard: _shareMarketRequestFromCard,
                  );
                }

                Widget cardAt(int i) {
                  final e = mixedPaint[i];
                  final p = e.listing;
                  if (p != null) return listingCard(p);
                  final req = e.request;
                  if (req == null) return const SizedBox.shrink();
                  return requestCard(req);
                }

                final rowCount = (totalCards + cross - 1) ~/ cross;
                return ListView.separated(
                  controller: onboardingScroll,
                  primary: false,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  cacheExtent: 420,
                  itemCount: rowCount,
                  separatorBuilder: (_, __) => const SizedBox(height: spacing),
                  itemBuilder: (context, row) {
                    final start = row * cross;
                    // ارتفاع موحّد عبر SizedBox — بدون IntrinsicHeight/stretch.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < cross; j++) ...[
                          if (j > 0) const SizedBox(width: spacing),
                          Expanded(
                            child: start + j < totalCards
                                ? _wrapEqualGridCardHeight(
                                    height: equalH,
                                    child: cardAt(start + j),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    }

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
    _ensureSubTabControllers();
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(1);

    final hasImmediateMyPageData =
        _mine.isNotEmpty || _hasMarketingData || _hasOwnerRequestsData;
    final hubStillLoading = _myAdsHubDataLoadStarted &&
        ((_usesMarketerMyPageHub && _loadingMarketing) ||
            (!_usesMarketerMyPageHub && _loadingOwnerRequests));
    if (!kIsWeb &&
        (_loadingMine || hubStillLoading) &&
        !hasImmediateMyPageData) {
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

    // التبويبات الكاملة (معلن/مسوّق) — اعرض ما توفر فوراً حتى قبل اكتمال الدلاء.
    final hubItems = sortedMineForHub();
    return _buildMyAdsMarketingHub(hubItems);
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

    // طلباتي/إعلاناتي: ملكي + ما نشرتُه — بدون فلتر الظهور العام للرئيسية.
    final mineFiltered = filterListDashboard(
      _propertiesOwnedOrPublishedByMe(),
      includeMyPipelineListings: true,
    );
    // طلبات السوق التي قدّمتها أنا (مسار مخصّص) — لا تعتمد على فيد الرئيسية فقط.
    final myReqSource = _myMarketSubmissions.isNotEmpty
        ? _myMarketSubmissions
        : _marketHomeRequests
            .where((r) => r.requesterId == _uid && _uid.isNotEmpty)
            .toList();
    final myReq = filterMarketRequests(myReqSource, forMySubmissions: true);

    final loading = _loadingMine ||
        (_uid.isNotEmpty &&
            (_loadingMarketRequests || _loadingMyMarketSubmissions));
    final hasPartialSubmissions = mineFiltered.isNotEmpty || myReq.isNotEmpty;

    // ويب: لا تبقَ على الهيكل العظمي أكثر من اللازم — اعرض ما توفر فوراً.
    if (loading && !hasPartialSubmissions && !kIsWeb) {
      return PropertyCardSkeletonList(
        count: 6,
        topPadding: 16,
      );
    }
    if (kIsWeb && loading && !hasPartialSubmissions) {
      // إن كانت mine جاهزة عبر مسار آخر ستظهر أعلاه؛ وإلا هيكل قصير جداً.
      return PropertyCardSkeletonList(
        count: 2,
        topPadding: 16,
      );
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
                  await _loadMyMarketSubmissions(force: true);
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

    if (mineFiltered.isEmpty && myReq.isEmpty) {
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
    // ويب/سطح مكتب: صفوف شبكة (1 أو 2 عمود) — بدون shrinkWrap GridView.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = _homeListingGridCrossAxisCount(constraints.maxWidth);
        const spacing = 12.0;
        final equalH = _homeListingGridEqualCardHeight(
          maxWidth: constraints.maxWidth,
          crossAxisCount: cross,
          horizontalPadding: 24,
          spacing: spacing,
        );
        final header = marketErr.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
              )
            : null;

        Widget listingCard(Property p) {
          final isOwner = p.ownerId == _uid;
          return _RealEstateCard(
            property: p,
            isOwner: isOwner,
            isAr: _isArabic,
            bankColor: _brandPrimary,
            favorite: !_isGuest && _isFav(p.id),
            onToggleFav: () => _toggleFav(p.id),
            onOpenDetails: () => _openDetails(p),
            activeCartHoldsCount: _activeReservationHoldCount(p.id),
            isReserved: _isReservedByAnyone(p.id),
            reservedUntil: _reservedUntil(p.id),
            reservedByName: _reservedByName(p.id),
            onAddToCart:
                _cartReservationFeaturesEnabled ? () => _addToCart(p) : null,
            currentUserId: _uid.isEmpty ? 'guest' : _uid,
            showEditDelete: isOwner,
            onEditProperty: isOwner ? () => _editProperty(p) : null,
            onDeleteProperty: isOwner ? () => _requestDeleteProperty(p) : null,
            timeAgo: _timeAgo,
            canShowCartButton: _cartReservationFeaturesEnabled,
            showListingQuickActions: true,
            onCopyListingWebLink: _copyListingPublicLink,
            suppressPublicOwnerIdentity: false,
            onShareListingFromCard: () => _shareListingFromCard(p),
            preferStaticPrimaryImage: true,
          );
        }

        Widget requestCard(MarketPropertyRequestRow r) {
          return _MarketRequestListingStyleCard(
            request: r,
            isAr: _isArabic,
            bankColor: _brandPrimary,
            currentUserId: _uid.isEmpty ? 'guest' : _uid,
            timeAgo: _timeAgo,
            priorityLabel: _marketRequestPriorityL10nLabel(
              l10n,
              r.requestPriority,
            ),
            onOpen: () => _openMarketRequestDetail(r),
            onEditMarketRequest: _editMarketRequest,
            onSubmitOffer: _isGuest
                ? null
                : () => _openMarketRequestDetail(r, autoOpenSubmitOffer: true),
            onCopyMarketRequestWebLink: _copyMarketRequestPublicLink,
            onShareMarketRequestFromCard: _shareMarketRequestFromCard,
          );
        }

        final mixedMine = buildMixedHomeTimeline(
          mineFiltered,
          myReq,
          limit: mineFiltered.length + myReq.length,
          pinPaidRequests: false,
        );
        final totalCards = mixedMine.length;
        Widget cardAt(int i) {
          final e = mixedMine[i];
          final p = e.listing;
          if (p != null) return listingCard(p);
          return requestCard(e.request!);
        }

        final rowCount =
            totalCards == 0 ? 0 : (totalCards + cross - 1) ~/ cross;
        final itemCount =
            (header != null ? 1 : 0) + (totalCards == 0 ? 1 : rowCount);

        return ListView.separated(
          controller: onboardingScroll,
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          cacheExtent: 420,
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: spacing),
          itemBuilder: (context, i) {
            if (header != null && i == 0) return header;
            final rowIdx = i - (header != null ? 1 : 0);
            if (totalCards == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  _isArabic
                      ? 'لا توجد إعلانات أو طلبات هنا بعد'
                      : 'No listings or requests here yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              );
            }
            final start = rowIdx * cross;
            // ارتفاع موحّد عبر SizedBox — بدون IntrinsicHeight/stretch.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < cross; j++) ...[
                  if (j > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: start + j < totalCards
                        ? _wrapEqualGridCardHeight(
                            height: equalH,
                            child: cardAt(start + j),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // =========================
  // Build favorites body
  // =========================
  Widget _buildFavoritesBody(List<Property> favItems) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final onboardingScroll = _scrollControllerForOnboardingTab(2);

    if (_loadingFavorites && favItems.isEmpty) {
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
      suppressPublicOwnerIdentityOnCards: false,
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
          (_visibleArchivedMarketOffersForCart.isEmpty ? 0 : 1) +
          _visibleArchivedMarketOffersForCart.length +
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
              label: _isArabic ? 'تفاصيل الطلب' : 'Request details',
              onPressed: rid.isEmpty
                  ? null
                  : () => unawaited(_openMarketRequestDetailById(rid)),
            ),
            secondaryAction: _ReservationAction(
              kind: _ReservationActionKind.outlined,
              icon: Icons.chat_bubble_outline,
              label: _isArabic ? 'مراسلة' : 'Message',
              onPressed: rid.isEmpty
                  ? null
                  : () => _openChat(
                        mode: 'market_request',
                        marketRequestId: rid,
                        kind: ConversationKind.marketRequest,
                        title: titleHint.isNotEmpty
                            ? titleHint
                            : (_isArabic
                                ? 'مراسلة الطلب'
                                : 'Request messaging'),
                      ),
            ),
            thirdAction: _ReservationAction(
              kind: _ReservationActionKind.filledDanger,
              icon: Icons.close,
              label: _isArabic ? 'إلغاء العرض' : 'Cancel offer',
              onPressed: () {
                final oid = (o['id'] ?? '').toString().trim();
                unawaited(_withdrawCartMarketOffer(rid, oid));
              },
            ),
            tryParseDt: _tryParseDt,
            timeAgo: _timeAgo,
            fmtDateTime: _fmtDateTime,
          );
        }
        final archived = _visibleArchivedMarketOffersForCart;
        final afterPending =
            i - introEnd - _myPendingMarketOffersForCart.length;
        // أرشيف العروض الخاسرة/المنتهية
        if (archived.isNotEmpty) {
          if (afterPending == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                _isArabic
                    ? 'عروض أُغلقت مع شريك آخر'
                    : 'Closed with another partner',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            );
          }
          final archIdx = afterPending - 1;
          if (archIdx >= 0 && archIdx < archived.length) {
            final o = archived[archIdx];
            final rid = (o['market_request_id'] ?? '').toString();
            final oid = (o['id'] ?? '').toString().trim();
            final titleHint = (o['_request_title'] ?? '').toString().trim();
            final lost = _marketOfferLostToOtherPartner(o);
            final st = (o['status'] ?? '').toString();
            return _ReservationCard(
              bankColor: _brandPrimary,
              icon: Icons.sentiment_dissatisfied_outlined,
              title: titleHint.isNotEmpty
                  ? titleHint
                  : (_isArabic ? 'طلب عقاري' : 'Request'),
              subtitle: Text(
                lost
                    ? (_isArabic
                        ? 'تمت الصفقة مع شريك آخر — لم يحالفك الحظ هذه المرة.'
                        : 'Deal completed with another partner — not selected this time.')
                    : (_isArabic
                        ? 'انتهى هذا العرض ولم يُعتمد.'
                        : 'This offer ended and was not accepted.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: lost ? cs.error : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
              ),
              chips: [
                _MiniChip(
                  icon: Icons.info_outline,
                  text:
                      '${_isArabic ? 'الحالة' : 'Status'}: ${_marketOfferStatusLabel(st)}',
                  color: cs.error,
                ),
              ],
              priceTable: const SizedBox.shrink(),
              primaryAction: _ReservationAction(
                kind: _ReservationActionKind.outlined,
                icon: Icons.open_in_new,
                label: _isArabic ? 'تفاصيل الطلب' : 'Request details',
                onPressed: rid.isEmpty
                    ? null
                    : () => unawaited(_openMarketRequestDetailById(rid)),
              ),
              secondaryAction: _ReservationAction(
                kind: _ReservationActionKind.filledDanger,
                icon: Icons.delete_outline,
                label: _isArabic ? 'حذف من صفقاتي' : 'Remove from My deals',
                onPressed: oid.isEmpty
                    ? null
                    : () => unawaited(_hideCartMarketOffer(oid)),
              ),
              thirdAction: null,
              tryParseDt: _tryParseDt,
              timeAgo: _timeAgo,
              fmtDateTime: _fmtDateTime,
            );
          }
        }
        final archiveBlock = archived.isEmpty ? 0 : 1 + archived.length;
        final cartIdx = afterPending - archiveBlock;
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
            label: _isArabic ? 'تفاصيل العرض' : 'Offer details',
            onPressed: p == null ? null : () => _openDetails(p),
          ),
          secondaryAction: _ReservationAction(
            kind: _ReservationActionKind.outlined,
            icon: Icons.chat_bubble_outline,
            label: _isArabic ? 'مراسلة' : 'Message',
            onPressed: () {
              final t = p?.title ??
                  (_isArabic ? 'مراسلة الحجز' : 'Reservation messaging');
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
        label: _isArabic ? 'مراسلة' : 'Message',
        onPressed: () {
          final t =
              p?.title ?? (_isArabic ? 'مراسلة الصفقة' : 'Deal messaging');
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
      return const CartRowSkeletonList(count: 5, topPadding: 24);
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
            label: _isArabic ? 'مراسلة' : 'Message',
            onPressed: () {
              final t = p?.title ??
                  (_isArabic ? 'مراسلة الحجز' : 'Reservation messaging');
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

/// إطارات خفيفة أولاً بعد تبديل التبويب حتى لا يتجمّد شريط التنقل.
class _DeferredTabBody extends StatefulWidget {
  const _DeferredTabBody({
    required this.tabIndex,
    required this.builder,
    this.deferFirstFrame = true,
    this.extraDeferFrames = 0,
  });

  final int tabIndex;
  final WidgetBuilder builder;
  final bool deferFirstFrame;
  final int extraDeferFrames;

  @override
  State<_DeferredTabBody> createState() => _DeferredTabBodyState();
}

class _DeferredTabBodyState extends State<_DeferredTabBody> {
  late bool _ready;
  int _gen = 0;

  void _armReady() {
    final gen = ++_gen;
    final frames = 1 + widget.extraDeferFrames.clamp(0, 4);
    void step(int left) {
      if (!mounted || gen != _gen) return;
      if (left <= 0) {
        setState(() => _ready = true);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => step(left - 1));
    }

    _ready = false;
    step(frames);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.deferFirstFrame) {
      _ready = true;
    } else {
      _ready = false;
      _armReady();
    }
  }

  @override
  void didUpdateWidget(covariant _DeferredTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex == widget.tabIndex) return;
    if (!widget.deferFirstFrame) {
      _ready = true;
      return;
    }
    _armReady();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    return widget.builder(context);
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
