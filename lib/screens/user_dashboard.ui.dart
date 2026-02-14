part of 'user_dashboard.dart';

// === ملف: user_dashboard.ui.dart ===
// الهدف: يحتوي تعريف UserDashboard و _UserDashboardState (الحقول الأساسية + init/dispose وربط التبويبات).

class UserDashboard extends StatefulWidget {
  final String lang;
  const UserDashboard({super.key, required this.lang});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
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
  // ✅ إسكات خطأ _nearbyCityQuery (إذا كان _SearchField مازال يستخدمه)
  // =========================
  String _nearbyCityQuery = '';

  // =========================
  // ✅ GPS (Nearest)
  // =========================
  double? _myLat;
  double? _myLng;

  // =========================
  // ثابتات/مراجع
  // =========================
  static const Color _bankColor = Color(0xFF0F766E);
  final _sb = Supabase.instance.client;

  // =========================
  // ✅ Auth + reload guards (FIELDS يجب أن تكون هنا)
  // =========================
  StreamSubscription<AuthState>? _authSub;

  // ✅ prevents double initial load after splitting
  bool _didInitialLoad = false;

  // ✅ prevent overlapping reloads (auth state change)
  bool _reloading = false;

  // ✅ track last auth user id to avoid duplicate reloads
  String? _lastAuthUserId;

  // =========================
  // Tabs + filters
  // =========================
  // Tabs: 0 Home, 1 My Ads, 2 Favorites, 3 Cart, 4 Reservations, 5 Chat
  int _tabIndex = 0;

  String _searchQuery = '';

  // ✅ NEW: فلاتر عصرية (بدل nearbyCityQuery)
  String _cityFilter = 'all'; // all | riyadh | jeddah | ...
  PropertyType? _typeFilter; // null = all

  // Sorting: latest | price_low | price_high | area_high | nearest
  String _sortBy = 'latest';
  Timer? _debounce;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isArabic => langNotifier.value == 'ar';
  String get _lang => langNotifier.value;

  String get _uid => _sb.auth.currentUser?.id ?? '';
  bool get _isGuest => _uid.isEmpty;

	// =========================
	// ✅ Internet Guard wrapper (ONE PLACE) + TIMEOUT + DEBUG TAG
	// =========================
	Future<T?> _net<T>(
	  Future<T> Function() action, {
	  bool showDialog = true,
	  Duration timeout = const Duration(seconds: 15),
	  String tag = 'NET',
	}) async {
	  final session = context.read<AppSession>();
	  final sw = Stopwatch()..start();

	  try {
		final fut = session.runNetworkGuarded<T>(
		  context: context,
		  isAr: _isArabic,
		  showDialogOnNoInternet: showDialog,
		  action: action,
		);

		final res = await fut.timeout(timeout);

		if (kDebugMode) {
		  // ignore: avoid_print
		  print('[DBG][NET][$tag] ok ${sw.elapsedMilliseconds}ms null=${res == null}');
		}
		return res;
	  } on TimeoutException catch (e) {
		if (kDebugMode) {
		  // ignore: avoid_print
		  print('[DBG][NET][$tag] TIMEOUT ${sw.elapsedMilliseconds}ms $e');
		}
		rethrow;
	  } catch (e) {
		if (kDebugMode) {
		  // ignore: avoid_print
		  print('[DBG][NET][$tag] ERR ${sw.elapsedMilliseconds}ms $e');
		}
		rethrow;
	  }
	}

  // =========================
  // Shared helpers required by split parts
  // =========================

  /// Opacity helper:
  /// - If value is 0..1 returns as-is
  /// - If value is 0..255 converts to 0..1
  double _op(num v) {
    final d = v.toDouble();
    if (d <= 1.0) return d.clamp(0.0, 1.0);
    return (d / 255.0).clamp(0.0, 1.0);
  }

  /// setState wrapper used across actions/loaders
  void _ss(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// Snack helper (toast) used for user notifications
  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red : _bankColor,
          content: Text(msg),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Settings navigation (used by UI)
  Future<void> _openSettings() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage(lang: widget.lang)),
    );
    if (!mounted) return;
    setState(() {});
  }

  // =========================
  // Haversine distance in KM
  // =========================
  double _distanceKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const r = 6371.0;
    double toRad(double d) => d * 3.141592653589793 / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _distanceFor(Property p) {
    final lat = p.latitude;
    final lng = p.longitude;
    final myLat = _myLat;
    final myLng = _myLng;
    if (lat == null || lng == null || myLat == null || myLng == null) {
      return double.infinity;
    }
    return _distanceKm(lat1: myLat, lon1: myLng, lat2: lat, lon2: lng);
  }

  // === DASH_HELPERS_BEGIN ===
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    return double.tryParse(s);
  }

  double _toDouble0(dynamic v, [double fallback = 0.0]) {
    return _toDouble(v) ?? fallback;
  }

  DateTime? _tryParseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    return DateTime.tryParse(s);
  }

  String _timeAgo(DateTime dt, [bool? isArabic]) {
    final ar = isArabic ?? _isArabic;

    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return ar ? 'الآن' : 'Now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return ar ? 'قبل $m دقيقة' : '$m min ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return ar ? 'قبل $h ساعة' : '$h h ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return ar ? 'قبل $d يوم' : '$d days ago';
    }
    final d = diff.inDays;
    final w = (d / 7).floor();
    if (w < 5) return ar ? 'قبل $w أسبوع' : '$w weeks ago';
    return ar ? 'منذ مدة' : 'A while ago';
  }
  // === DASH_HELPERS_END ===

  // =========================
  // العقارات المميزة
  // =========================
  final List<Property> _featuredProperties = [];
  bool _loadingFeatured = false;

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
      _tabIndex = 5; // تبويب الدردشة
    });
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            _isArabic ? 'تسجيل الدخول' : 'Login Required',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            _isArabic
                ? 'يجب تسجيل الدخول للوصول إلى هذه الميزة. هل تريد تسجيل الدخول الآن؟'
                : 'You need to login to access this feature. Would you like to login now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_isArabic ? 'لاحقاً' : 'Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToLogin();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
              ),
              child: Text(_isArabic ? 'تسجيل الدخول' : 'Login'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  // =========================
  // عرض إشعارات
  // =========================
  final List<Map<String, dynamic>> _notifications = [];
  bool _loadingNotifications = false;

  void _showNotification(String title, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red : _bankColor,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // =========================
  // Caching
  // =========================
  static const String _propertiesSelect = '''
id,
owner_id,
title,
description,
city,
address_line,
price,
status,
created_at,
updated_at,
type,
area,
is_auction,
current_bid,
views,
username,
latitude,
longitude,
currency,
bedrooms,
bathrooms,
parking_spots,
furnished,
year_built,
floor,
total_floors,
amenities,
video_url,
virtual_tour_url,
availability_date,
negotiable,
is_featured,
property_images ( sort_order, path )
''';

  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Map<String, Property> _propertyCache = {};
  DateTime? _lastHomeFetch;
  DateTime? _lastMineFetch;
  DateTime? _lastCartFetch;
  DateTime? _lastFeaturedFetch;
  DateTime? _lastFavoritesFetch;
  static const Duration _cacheDuration = Duration(minutes: 1);

  // =========================
  // Loading / error states
  // =========================
  // ✅ مهم: لا تبدأ true حتى لا تعلق لو لم يتم استدعاء loaders
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
  List<Property> _mine = <Property>[];
  List<Property> _favoritesList = <Property>[];

  Map<String, Property> _myPropertyById = {};

  List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _cart = <Map<String, dynamic>>[];
  Map<String, Property> _cartPropertyById = {};
  int _cartCount = 0;

  final Map<String, Map<String, dynamic>> _activeReservationByPropertyId = {};

  int _offersCount = 0;
  int _unreadNotificationsCount = 0;

  final Set<String> _favoriteIds = <String>{};
  bool _favoritesLoaded = false;

  bool _loggingOut = false;

  // =========================
  // ✅ Initial load (لا يعتمد على onAuthStateChange)
  // =========================
  Future<void> _runInitialLoad() async {
    if (!mounted) return;
    if (_didInitialLoad) return;

    _didInitialLoad = true;
    _lastAuthUserId = _sb.auth.currentUser?.id;

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

      // Home دائمًا
      _loadingHome = true;
      _loadingFeatured = true;

      // تبويبات المستخدم فقط إذا ليس ضيف
      if (!_isGuest) {
        _loadingMine = true;
        _loadingFavorites = true;
        _loadingCart = true;
        _loadingOffers = true;
      } else {
        _loadingMine = false;
        _loadingFavorites = false;
        _loadingCart = false;
        _loadingOffers = false;
        _favoritesLoaded = true;
      }
    });

    try {
      await _loadHome(force: true);
      await _loadFeaturedProperties(force: true);

      // إشعارات/مفضلة/سلة/حجوزات فقط للمستخدم
      if (!_isGuest) {
        await _loadNotifications();
        await _loadFavoritesForUid().then((_) => _loadFavoritesList(force: true));
        await _loadCart(force: true);
        await _loadMineAndOffers(force: true);
      }
    } catch (_) {
      // مهم: لا نعلق
    } finally {
      if (!mounted) return;
      _ss(() {
        _loadingHome = false;
        _loadingFeatured = false;

        if (_isGuest) {
          _loadingMine = false;
          _loadingFavorites = false;
          _loadingCart = false;
          _loadingOffers = false;
        }
      });
    }
  }

  // =========================
  // ✅ Auth reload: فقط عند تغيّر المستخدم (دخل/خرج)
  // =========================
  void _handleAuthReloadIfNeeded() {
    final uid = _sb.auth.currentUser?.id;
    if (_lastAuthUserId == uid) return;
    _lastAuthUserId = uid;

    if (!mounted) return;
    if (!_didInitialLoad) return; // initState سيعمل التحميل الأول

    if (_reloading) return;
    _reloading = true;

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

      // Home دائمًا
      _loadingHome = true;
      _loadingFeatured = true;

      if (uid != null && uid.isNotEmpty) {
        _loadingMine = true;
        _loadingFavorites = true;
        _loadingCart = true;
        _loadingOffers = true;
      } else {
        _loadingMine = false;
        _loadingFavorites = false;
        _loadingCart = false;
        _loadingOffers = false;
        _favoritesLoaded = true;
        _favoriteIds.clear();
        _favoritesList = <Property>[];
        _cart = <Map<String, dynamic>>[];
        _cartPropertyById = {};
        _cartCount = 0;
        _offers = <Map<String, dynamic>>[];
        _offersCount = 0;
      }
    });

    () async {
      try {
        await _loadHome(force: true);
        await _loadFeaturedProperties(force: true);

        if (uid != null && uid.isNotEmpty) {
          await _loadNotifications();
          await _loadFavoritesForUid().then((_) => _loadFavoritesList(force: true));
          await _loadCart(force: true);
          await _loadMineAndOffers(force: true);
        }
      } catch (_) {
      } finally {
        if (!mounted) return;
        _ss(() {
          _loadingHome = false;
          _loadingFeatured = false;
        });
        _reloading = false;
      }
    }();
  }

  // =========================
  // init / dispose
  // =========================
  @override
  void initState() {
    super.initState();

    // ✅ تحميل أولي مضمون (حتى لو لم يأتِ حدث Auth على الويب/ضيف)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _runInitialLoad();
    });

    // ✅ إعادة التحميل عند تسجيل الدخول / الخروج (فقط عند تغيّر المستخدم)
    _authSub = _sb.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      _handleAuthReloadIfNeeded();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    _readArgsInBuildOnce(context);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final homeItems = _filterList(_all);
    final myItems = _filterList(_mine);
    final favItems = _filterList(_favoritesList);

    // ✅ زر الإضافة أصبح تبويب بالمنتصف (index=2 في NavigationBar)
    // 0 Home, 1 MyAds, 2 Add, 3 Favorites, 4 Cart, 5 Reservations, 6 Chat
    final int navIndex = (_tabIndex <= 1) ? _tabIndex : _tabIndex + 1;

    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: WillPopScope(
        onWillPop: () async {
          if (_isGuest) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
            return false;
          }
          return false;
        },
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            elevation: 0,
            title: Text(
              _tabTitle(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              _IconBadgeButton(
                tooltip: _isArabic ? 'الإشعارات' : 'Notifications',
                icon: Icons.notifications_outlined,
                badge: _unreadNotificationsCount,
                color: Colors.orange,
                onPressed: _openNotificationsPage,
              ),
              if (!_isGuest)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.5),
                        ),
                        color: cs.surfaceContainerHighest.withOpacity(0.55),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: Colors.redAccent.withOpacity(0.95),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_favoriteIds.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              _IconBadgeButton(
                tooltip: _isArabic ? 'السلة (حجوزاتي)' : 'Cart (My reservations)',
                icon: Icons.shopping_cart_outlined,
                badge: _cartCount,
                color: _bankColor,
                onPressed: () {
                  if (_isGuest) {
                    _showLoginDialog();
                    return;
                  }
                  setState(() => _tabIndex = 3);
                },
              ),
              _IconBadgeButton(
                tooltip: _isArabic ? 'الحجوزات' : 'Reservations',
                icon: Icons.receipt_long_outlined,
                badge: _offersCount,
                color: _bankColor,
                onPressed: () {
                  if (_isGuest) {
                    _showLoginDialog();
                    return;
                  }
                  setState(() => _tabIndex = 4);
                },
              ),
              IconButton(
                tooltip: _isArabic ? 'الدردشة' : 'Chat',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () {
                  if (_isGuest) {
                    _showLoginDialog();
                    return;
                  }
                  setState(() => _tabIndex = 5);
                },
              ),
              IconButton(
                tooltip: _isArabic ? 'الدعم الفني' : 'Support',
                icon: const Icon(Icons.help_outline),
                onPressed: () {
                  if (_isGuest) {
                    _showLoginDialog();
                    return;
                  }
                  _openSupportPage();
                },
              ),
              IconButton(
                tooltip: _isArabic ? 'إعدادات' : 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
              ),
              IconButton(
                tooltip: _isArabic ? 'تسجيل خروج' : 'Logout',
                icon: _loggingOut
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                onPressed: _loggingOut ? null : _logout,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_tabIndex == 0 || _tabIndex == 1 || _tabIndex == 2)
                  _buildTopFilters(
                    onRefresh: () async {
                      if (_tabIndex == 0) {
                        await _loadHome(force: true);
                      } else if (_tabIndex == 1) {
                        await _loadMineAndOffers(force: true);
                      } else if (_tabIndex == 2) {
                        await _loadFavoritesList(force: true);
                      }
                      await _loadCart(force: true);
                    },
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      RefreshIndicator(
                        onRefresh: () async {
                          await _loadHome(force: true);
                          await _loadCart(force: true);
                        },
                        child: _buildHomeBody(),
                      ),
                      RefreshIndicator(
                        onRefresh: () async {
                          await _loadMineAndOffers(force: true);
                          await _loadCart(force: true);
                        },
                        child: _buildPropertiesBody(
                          loading: _loadingMine,
                          loadingSince: _mineLoadingSince,
                          error: _errorMine,
                          items: myItems,
                          emptyTitle: _isArabic ? 'لا توجد إعلانات لك' : 'No listings for you',
                          emptySubtitle: _isArabic
                              ? 'أضف إعلاناً جديداً وسيظهر هنا.'
                              : 'Add a new listing and it will appear here.',
                          showEditDelete: true,
                          onRetry: () => _retryWithOfflineHint(_reloadAll),
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: () async {
                          await _loadFavoritesList(force: true);
                          await _loadCart(force: true);
                        },
                        child: _buildFavoritesBody(),
                      ),
                      RefreshIndicator(
                        onRefresh: () async {
                          await _loadCart(force: true);
                          await _loadHome(force: true);
                          await _loadMineAndOffers(force: true);
                        },
                        child: _buildCartBody(),
                      ),
                      RefreshIndicator(
                        onRefresh: () async {
                          await _loadMineAndOffers(force: true);
                          await _loadCart(force: true);
                        },
                        child: _buildOffersBody(),
                      ),
                      _buildChatBody(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: navIndex,
              onDestinationSelected: (i) async {
                final needsLogin = i != 0;
                if (needsLogin && _isGuest) {
                  _showLoginDialog();
                  return;
                }

                if (i == 2) {
                  await _openAdd();
                  return;
                }

                setState(() {
                  if (i <= 1) {
                    _tabIndex = i;
                  } else {
                    _tabIndex = i - 1;
                  }

                  if (_tabIndex == 1) {
                    _searchQuery = '';
                    _sortBy = 'latest';
                  }
                });
              },
              indicatorColor: _bankColor.withOpacity(_op(28)),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: _isArabic ? 'الرئيسية' : 'Home',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.list_alt_outlined),
                  selectedIcon: const Icon(Icons.list_alt),
                  label: _isArabic ? 'إعلاناتي' : 'My Ads',
                ),
                NavigationDestination(
                  icon: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _bankColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                          color: Colors.black.withOpacity(0.18),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  selectedIcon: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _bankColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                          color: Colors.black.withOpacity(0.22),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  label: _isArabic ? 'إضافة' : 'Add',
                ),
                NavigationDestination(
                  icon: _BadgeIcon(
                    icon: Icons.favorite_outline,
                    badge: _favoriteIds.length,
                    color: Colors.red,
                  ),
                  selectedIcon: const Icon(Icons.favorite),
                  label: _isArabic ? 'المفضلة' : 'Favorites',
                ),
                NavigationDestination(
                  icon: _BadgeIcon(
                    icon: Icons.shopping_cart_outlined,
                    badge: _cartCount,
                    color: _bankColor,
                  ),
                  selectedIcon: const Icon(Icons.shopping_cart),
                  label: _isArabic ? 'سلتي' : 'Cart',
                ),
                NavigationDestination(
                  icon: _BadgeIcon(
                    icon: Icons.receipt_long_outlined,
                    badge: _offersCount,
                    color: _bankColor,
                  ),
                  selectedIcon: const Icon(Icons.receipt_long),
                  label: _isArabic ? 'الحجوزات' : 'Reservations',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.chat_bubble_outline),
                  selectedIcon: const Icon(Icons.chat_bubble),
                  label: _isArabic ? 'الدردشة' : 'Chat',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopFilters({required Future<void> Function() onRefresh}) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Column(
        children: [
          _SearchField(
            isAr: _isArabic,
            hint: _isArabic ? 'ابحث (عنوان / مدينة / وصف)...' : 'Search (title / city / description)...',
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                if (!mounted) return;
                setState(() => _searchQuery = v);
              });
            },

            // ✅ المدينة (بدل nearbyCityQuery)
            nearbyValue: _cityFilter == 'all' ? '' : _cityFilter,
            onNearbyChanged: (v) {
              final value = v.trim().toLowerCase();
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                if (!mounted) return;
                setState(() => _cityFilter = value.isEmpty ? 'all' : value);
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SortMenu(
                  isAr: _isArabic,
                  value: _sortBy,
                  onChanged: (v) => setState(() => _sortBy = v),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () async => await onRefresh(),
                icon: const Icon(Icons.refresh),
                label: Text(_isArabic ? 'تحديث' : 'Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================
  // Body builders
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

  Future<void> _retryWithOfflineHint(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      final msg = e.toString();
      final offline = _isOfflineErrorStr(msg);
      if (!mounted) return;

      _showNotification(
        offline ? (_isArabic ? 'لا يوجد اتصال' : 'No connection') : (_isArabic ? 'فشل التحديث' : 'Refresh failed'),
        offline
            ? (_isArabic ? 'تحقق من الإنترنت ثم أعد المحاولة.' : 'Check your internet connection then try again.')
            : (_isArabic ? 'حدث خطأ: $msg' : 'Error: $msg'),
        isError: true,
      );
    }
  }

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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 120),
        ],
      );
    }

    // ✅ إذا طال التحميل: لا نترك المؤشر يلف بلا نهاية
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.info_outline, size: 54, color: _bankColor),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _bankColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeBody() {
    final cs = Theme.of(context).colorScheme;

    final fallback = _loadingWithFallback(
      loading: _loadingHome,
      since: _homeLoadingSince,
      title: _isArabic ? 'جارٍ التحميل…' : 'Loading…',
      subtitle: _isArabic ? 'إذا استمر التحميل، اضغط تحديث.' : 'If loading continues, tap refresh.',
      onRetry: () => _retryWithOfflineHint(_reloadAll),
    );
    if (_loadingHome) return fallback;

    if (_errorHome != null) {
      final offline = _isOfflineErrorStr(_errorHome);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline ? (_isArabic ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection') : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.' : 'Make sure you are online, then retry.')
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
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    final homeItems = _filterList(_all);

    if (homeItems.isEmpty && _featuredProperties.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.home_outlined,
                  size: 84,
                  color: _bankColor.withOpacity(_op(180)),
                ),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'لا توجد إعلانات متاحة' : 'No listings available',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _isArabic ? 'قد تكون المشكلة من فلترة الحالة/السياسات أو لا توجد بيانات.' : 'It may be filters/policies or no data.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => _retryWithOfflineHint(_reloadAll),
                  icon: const Icon(Icons.refresh),
                  label: Text(_isArabic ? 'تحديث' : 'Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bankColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_featuredProperties.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      _isArabic ? 'عقارات مميزة' : 'Featured Properties',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _featuredProperties.length,
                    itemBuilder: (context, index) {
                      final p = _featuredProperties[index];
                      final isOwner = p.ownerId == _uid;
                      final isGuest = _isGuest;

                      return Container(
                        width: 280,
                        margin: const EdgeInsetsDirectional.only(end: 12),
                        child: _FeaturedPropertyCard(
                          property: p,
                          isOwner: isOwner,
                          isAr: _isArabic,
                          bankColor: _bankColor,
                          favorite: !isGuest && _isFav(p.id),
                          onToggleFav: isGuest ? () => _showLoginDialog() : () => _toggleFav(p.id),
                          onOpenDetails: () => _openDetails(p),
                          isReserved: _isReservedByAnyone(p.id),
                          reservedUntil: _reservedUntil(p.id),
                          reservedByName: _reservedByName(p.id),
                          onAddToCart: (isGuest || isOwner) ? null : () => _addToCart(p),
                          currentUserId: _uid.isEmpty ? 'guest' : _uid,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
              ],
            ),
          ),
        _PropertyGrid(
          items: homeItems,
          currentUserId: _uid.isEmpty ? 'guest' : _uid,
          isAr: _isArabic,
          bankColor: _bankColor,
          isFav: (id) => _isFav(id),
          onToggleFav: (id) => _toggleFav(id),
          onOpenDetails: (p) => _openDetails(p),
          isReserved: (pid) => _isReservedByAnyone(pid),
          reservedUntil: (pid) => _reservedUntil(pid),
          reservedByName: (pid) => _reservedByName(pid),
          onAddToCart: (p) => _addToCart(p),
          showEditDelete: false,
          onEditProperty: _editProperty,
          onDeleteProperty: _deleteProperty,
        ),
      ],
    );
  }

  Widget _buildPropertiesBody({
    required bool loading,
    required DateTime? loadingSince,
    required String? error,
    required List<Property> items,
    required String emptyTitle,
    required String emptySubtitle,
    required bool showEditDelete,
    required VoidCallback onRetry,
  }) {
    final cs = Theme.of(context).colorScheme;

    final fallback = _loadingWithFallback(
      loading: loading,
      since: loadingSince,
      title: _isArabic ? 'جارٍ التحميل…' : 'Loading…',
      subtitle: _isArabic ? 'إذا استمر التحميل، اضغط تحديث.' : 'If loading continues, tap refresh.',
      onRetry: onRetry,
    );
    if (loading) return fallback;

    if (error != null) {
      final offline = _isOfflineErrorStr(error);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline ? (_isArabic ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection') : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.' : 'Make sure you are online, then retry.')
                  : _failLoadSubtitle(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          if (kDebugMode) Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.home_outlined, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  emptyTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  emptySubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(_isArabic ? 'تحديث' : 'Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bankColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _PropertyGrid(
      items: items,
      currentUserId: _uid.isEmpty ? 'guest' : _uid,
      isAr: _isArabic,
      bankColor: _bankColor,
      isFav: (id) => _isFav(id),
      onToggleFav: (id) => _toggleFav(id),
      onOpenDetails: (p) => _openDetails(p),
      isReserved: (pid) => _isReservedByAnyone(pid),
      reservedUntil: (pid) => _reservedUntil(pid),
      reservedByName: (pid) => _reservedByName(pid),
      onAddToCart: (p) => _addToCart(p),
      showEditDelete: showEditDelete,
      onEditProperty: _editProperty,
      onDeleteProperty: _deleteProperty,
    );
  }

  Widget _buildFavoritesBody() {
    final cs = Theme.of(context).colorScheme;

    if (_loadingFavorites) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 120),
        ],
      );
    }

    if (_errorFavorites != null) {
      final offline = _isOfflineErrorStr(_errorFavorites);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              offline ? (_isArabic ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection') : _failLoadTitle(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.' : 'Make sure you are online, then retry.')
                  : _failLoadSubtitle(),
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
              onPressed: () => _retryWithOfflineHint(() => _loadFavoritesList(force: true)),
              icon: const Icon(Icons.refresh),
              label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    if (_isGuest) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'سجّل الدخول لعرض المفضلة' : 'Login to view favorites',
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
                      backgroundColor: _bankColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Text(
                      _isArabic ? 'تسجيل الدخول الآن' : 'Login Now',
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

    final favItems = _filterList(_favoritesList);

    if (favItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(Icons.favorite_border, size: 84, color: _bankColor.withOpacity(_op(180))),
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
                  label: Text(_isArabic ? 'استعرض الإعلانات' : 'Browse Listings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bankColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      bankColor: _bankColor,
      isFav: (id) => _isFav(id),
      onToggleFav: (id) => _toggleFav(id),
      onOpenDetails: (p) => _openDetails(p),
      isReserved: (pid) => _isReservedByAnyone(pid),
      reservedUntil: (pid) => _reservedUntil(pid),
      reservedByName: (pid) => _reservedByName(pid),
      onAddToCart: (p) => _addToCart(p),
      showEditDelete: false,
      onEditProperty: _editProperty,
      onDeleteProperty: _deleteProperty,
    );
  }

  Widget _buildChatBody() {
    final cs = Theme.of(context).colorScheme;

    if (_isGuest) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.lock_outline, size: 84, color: _bankColor.withOpacity(_op(180))),
          const SizedBox(height: 18),
          Text(
            _isArabic ? 'سجّل الدخول لاستخدام الدردشة' : 'Login to use Chat',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _isArabic ? 'الدردشة مرتبطة بالعقار والحجز لضمان الموثوقية.' : 'Chat is tied to property and reservation for trust.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: _navigateToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Text(
                _isArabic ? 'تسجيل الدخول الآن' : 'Login Now',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      );
    }

    final title = _chatTitle?.trim();
    final hasContext = ((_chatPropertyId ?? '').isNotEmpty || (_chatReservationId ?? '').isNotEmpty);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 10),
                color: cs.shadow.withOpacity(0.08),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _bankColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.chat_bubble_outline, color: _bankColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isArabic ? 'الدردشات' : 'Chats',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isArabic
                    ? 'يمكنك الدردشة مع البائع أو المشتري فيما يخص العقار أو الحجز.'
                    : 'You can chat with seller or buyer regarding property or reservation.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasContext)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isArabic ? 'آخر سياق محدد' : 'Last selected context',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniChip(
                      icon: Icons.home_work_outlined,
                      text: title?.isNotEmpty == true ? title! : (_isArabic ? 'محادثة عقار' : 'Property chat'),
                      bankColor: _bankColor,
                    ),
                    if ((_chatReservationId ?? '').isNotEmpty)
                      _MiniChip(
                        icon: Icons.receipt_long_outlined,
                        text: _isArabic
                            ? 'حجز: ${_chatReservationId!.substring(0, _chatReservationId!.length.clamp(0, 8))}...'
                            : 'Res: ${_chatReservationId!.substring(0, _chatReservationId!.length.clamp(0, 8))}...',
                        bankColor: _bankColor,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                              // إذا كان ChatPage عندك يدعم تمرير السياق لاحقاً، مرره هنا
                              // حالياً تركناه بدون باراميترات لتفادي أخطاء تجميع
                              ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(
                      _isArabic ? 'فتح الدردشة' : 'Open Chat',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!hasContext)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isArabic
                        ? 'لفتح دردشة مرتبطة بعقار/حجز: اذهب للسلة أو الحجوزات واضغط "دردشة".'
                        : 'To open a property/reservation chat: go to Cart or Reservations and tap "Chat".',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCartBody() {
    final cs = Theme.of(context).colorScheme;

    if (_loadingCart) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 120),
        ],
      );
    }

    if (_errorCart != null) {
      final offline = _isOfflineErrorStr(_errorCart);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              offline ? (_isArabic ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection') : (_isArabic ? 'تعذر تحميل السلة' : 'Failed to load cart'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.' : 'Make sure you are online, then retry.')
                  : (_isArabic ? 'تحقق من الاتصال ثم أعد المحاولة.' : 'Check connection then retry.'),
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
              onPressed: () => _retryWithOfflineHint(() => _loadCart(force: true)),
              icon: const Icon(Icons.refresh),
              label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    if (_uid.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'سجّل الدخول لعرض السلة' : 'Login to view cart',
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
                      backgroundColor: _bankColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Text(
                      _isArabic ? 'تسجيل الدخول الآن' : 'Login Now',
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

    if (_cart.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'سلّتك فارغة' : 'Your cart is empty',
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
                  label: Text(_isArabic ? 'اذهب للرئيسية' : 'Go to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bankColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      padding: const EdgeInsets.all(12),
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _cart[i];
        final reservationId = (r['id'] ?? '').toString();
        final propertyId = (r['property_id'] ?? '').toString();
        final p = _cartPropertyById[propertyId];

        final basePrice = _toDouble0(r['base_price']);
        final platformFee = _toDouble0(r['platform_fee_amount']);
        final extraFee = _toDouble0(r['extra_fee_amount']);
        final total = _toDouble0(r['total_amount']);

        final createdAt = _tryParseDt(r['created_at']);
        final expiresAt = _tryParseDt(r['expires_at']);
        final createdText = createdAt == null ? (_isArabic ? 'غير معروف' : 'Unknown') : _timeAgo(createdAt, _isArabic);
        final expiresText = expiresAt == null ? (_isArabic ? 'غير معروف' : 'Unknown') : _fmtDateTime(expiresAt);

        return _ReservationCard(
          bankColor: _bankColor,
          icon: Icons.shopping_cart_outlined,
          title: p?.title ?? (_isArabic ? 'عقار' : 'Property'),
          chips: [
            _MiniChip(
              icon: Icons.schedule,
              text: _isArabic ? 'منذ: $createdText' : 'Since: $createdText',
              bankColor: _bankColor,
            ),
            _MiniChip(
              icon: Icons.timer_outlined,
              text: _isArabic ? 'ينتهي: $expiresText' : 'Expires: $expiresText',
              bankColor: _bankColor,
            ),
          ],
          priceTable: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _priceRow(context, label: _isArabic ? 'السعر الأساسي' : 'Base price', value: basePrice),
              const SizedBox(height: 6),
              _priceRow(context, label: _isArabic ? 'عمولة المنصة (5%)' : 'Platform fee (5%)', value: platformFee),
              const SizedBox(height: 6),
              _priceRow(context, label: _isArabic ? 'رسوم إضافية (2.5%)' : 'Extra fee (2.5%)', value: extraFee),
              const Divider(height: 16),
              _priceRow(context, label: _isArabic ? 'الإجمالي' : 'Total', value: total, bold: true),
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
              final t = p?.title ?? (_isArabic ? 'دردشة الحجز' : 'Reservation chat');
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
        );
      },
    );
  }

  Widget _buildOffersBody() {
    final cs = Theme.of(context).colorScheme;

    if (_loadingOffers) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 120),
        ],
      );
    }

    if (_errorOffers != null) {
      final offline = _isOfflineErrorStr(_errorOffers);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection')
                  : (_isArabic ? 'تعذر تحميل الحجوزات' : 'Failed to load reservations'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              offline
                  ? (_isArabic ? 'تأكد من اتصال الإنترنت ثم أعد المحاولة.' : 'Make sure you are online, then retry.')
                  : (_isArabic ? 'تحقق من الاتصال ثم أعد المحاولة.' : 'Check connection then retry.'),
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
              onPressed: () => _retryWithOfflineHint(() => _loadMineAndOffers(force: true)),
              icon: const Icon(Icons.refresh),
              label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      );
    }

    if (_uid.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'سجّل الدخول لعرض الحجوزات' : 'Login to view reservations',
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
                      backgroundColor: _bankColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Text(
                      _isArabic ? 'تسجيل الدخول الآن' : 'Login Now',
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 84, color: _bankColor.withOpacity(_op(180))),
                const SizedBox(height: 18),
                Text(
                  _isArabic ? 'لا توجد حجوزات على إعلاناتك' : 'No reservations on your listings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => _retryWithOfflineHint(() => _loadMineAndOffers(force: true)),
                  icon: const Icon(Icons.refresh),
                  label: Text(_isArabic ? 'تحديث' : 'Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bankColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        final createdText = createdAt == null ? (_isArabic ? 'غير معروف' : 'Unknown') : _timeAgo(createdAt, _isArabic);
        final expiresText = expiresAt == null ? (_isArabic ? 'غير معروف' : 'Unknown') : _fmtDateTime(expiresAt);

        final status = (r['status'] ?? '').toString().trim();
        final buyerName = (r['reserved_by_name'] ?? '').toString().trim();
        final buyerLabel = buyerName.isNotEmpty ? buyerName : ((r['user_id'] ?? 'N/A').toString());

        return _ReservationCard(
          bankColor: _bankColor,
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
              bankColor: _bankColor,
            ),
            _MiniChip(
              icon: Icons.person_outline,
              text: _isArabic ? 'الحاجز: $buyerLabel' : 'Reserved by: $buyerLabel',
              bankColor: _bankColor,
            ),
            _MiniChip(
              icon: Icons.timer_outlined,
              text: _isArabic ? 'ينتهي: $expiresText' : 'Expires: $expiresText',
              bankColor: _bankColor,
            ),
          ],
          priceTable: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _priceRow(context, label: _isArabic ? 'السعر الأساسي' : 'Base price', value: basePrice),
              const SizedBox(height: 6),
              _priceRow(context, label: _isArabic ? 'عمولة المنصة (5%)' : 'Platform fee (5%)', value: platformFee),
              const SizedBox(height: 6),
              _priceRow(context, label: _isArabic ? 'رسوم إضافية (2.5%)' : 'Extra fee (2.5%)', value: extraFee),
              const Divider(height: 16),
              _priceRow(context, label: _isArabic ? 'الإجمالي' : 'Total', value: total, bold: true),
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
              final t = p?.title ?? (_isArabic ? 'دردشة الحجز' : 'Reservation chat');
              _openChat(
                mode: 'reservation',
                propertyId: propertyId,
                reservationId: reservationId,
                title: t,
              );
            },
          ),
          thirdAction: null,
        );
      },
    );
  }
}
