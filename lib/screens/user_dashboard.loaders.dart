part of 'user_dashboard.dart';

// =========================================
// user_dashboard.loaders.dart
// =========================================

extension _UserDashboardStateLoaders on _UserDashboardState {
  // =========================================================
  // Favorites local storage
  // =========================================================
  String _favKey(String uid) => 'fav_ids_$uid';

  Future<void> _loadFavoritesForUid() async {
    final uid = _uid;

    if (uid.isEmpty) {
      _favoriteIds.clear();
      _favoritesLoaded = true;
      _favoritesList = <Property>[];
      if (mounted) _ss(() {});
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favKey(uid));

      _favoriteIds.clear();

      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _favoriteIds.addAll(decoded.map((e) => e.toString()).toSet());
          }
        } catch (_) {}
      }

      _favoritesLoaded = true;
      _rebuildFavoritesFromCache();

      if (mounted) {
        _ss(() {});
      }
    } catch (_) {
      _favoriteIds.clear();
      _favoritesLoaded = true;
      _favoritesList = <Property>[];
      if (mounted) _ss(() {});
    }
  }

  Future<void> _saveFavoritesForUid() async {
    final uid = _uid;
    if (uid.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _favKey(uid),
        jsonEncode(_favoriteIds.toList()),
      );
    } catch (_) {}
  }

  bool _isFav(String id) => _favoriteIds.contains(id);

  void _rebuildFavoritesFromCache() {
    if (_isGuest || _favoriteIds.isEmpty) {
      _favoritesList = <Property>[];
      return;
    }

    final seen = <String>{};
    final list = <Property>[];

    Property? findInList(List<Property> items, String id) {
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    }

    for (final id in _favoriteIds) {
      Property? p = _propertyCache[id];

      p ??= findInList(_all, id);
      p ??= findInList(_mine, id);

      if (p != null && seen.add(p.id)) {
        list.add(p);
      }
    }

    list.sort((a, b) => b.displayDate.compareTo(a.displayDate));
    _favoritesList = list;
  }

  Future<void> _toggleFav(String propertyId) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    final wasFav = _favoriteIds.contains(propertyId);

    _ss(() {
      if (wasFav) {
        _favoriteIds.remove(propertyId);
        _showNotification(
          _isArabic ? 'تمت الإزالة' : 'Removed',
          _isArabic
              ? 'تمت إزالة العقار من المفضلة'
              : 'Property removed from favorites',
        );
      } else {
        _favoriteIds.add(propertyId);
        _showNotification(
          _isArabic ? 'تمت الإضافة' : 'Added',
          _isArabic
              ? 'تمت إضافة العقار إلى المفضلة'
              : 'Property added to favorites',
        );
      }

      _rebuildFavoritesFromCache();
      _lastFavoritesFetch = DateTime.now();
    });

    await _saveFavoritesForUid();

    if (_favoriteIds.isNotEmpty) {
      await _loadFavoritesList(force: true);
    } else {
      _ss(() {
        _favoritesList = <Property>[];
        _loadingFavorites = false;
        _errorFavorites = null;
      });
    }
  }

  // =========================================================
  // Notifications
  // =========================================================
  Future<void> _loadNotifications() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isGuest) {
      _notifications.clear();
      _unreadNotificationsCount = 0;
      _chatUnreadTotal = 0;
      if (mounted) {
        _ss(() => _loadingNotifications = false);
      }
      return;
    }

    _ss(() => _loadingNotifications = true);

    try {
      await _fetchProfilesByUserIds([_uid]);
      _syncInAppHubFromProfileCache();

      // الاعتماد دائماً على user_id حتى لا يختلط عداد/قائمة الإشعارات مع مستخدم آخر
      // أو تُفقد صفوف عند تعارض/تأخر username.
      final data = await _net(() {
        return _sb
            .from('in_app_notifications')
            .select(
              'id,username,type,title,body,data,created_at,is_read',
            )
            .eq('user_id', _uid)
            .order('created_at', ascending: false)
            .limit(80);
      }, tag: 'IN_APP_NOTIF_UID');

      if (data != null) {
        final rows = (data as List).map((e) {
          final row = Map<String, dynamic>.from(e as Map);
          Map<String, dynamic> dataMap = <String, dynamic>{};
          final rawData = row['data'];
          if (rawData is Map) {
            dataMap = Map<String, dynamic>.from(rawData);
          } else if (rawData is String && rawData.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(rawData);
              if (decoded is Map) {
                dataMap = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }

          final titleLocalized = _isArabic
              ? (dataMap['title_ar'] ?? dataMap['title'] ?? '').toString()
              : (dataMap['title_en'] ?? dataMap['title'] ?? '').toString();
          final bodyLocalized = _isArabic
              ? (dataMap['body_ar'] ?? dataMap['body'] ?? '').toString()
              : (dataMap['body_en'] ?? dataMap['body'] ?? '').toString();

          final title = (titleLocalized.trim().isNotEmpty
                  ? titleLocalized
                  : (row['title'] ?? row['type'] ?? '').toString())
              .trim();
          final message = (bodyLocalized.trim().isNotEmpty
                  ? bodyLocalized
                  : (row['message'] ?? row['body'] ?? '').toString())
              .trim();
          return <String, dynamic>{
            ...row,
            'title': title.isEmpty ? l10n.notificationDefaultTitle : title,
            'message': message,
          };
        }).toList();

        final filtered = rows
            .where(
              (r) => !MarketingFlowService.isSecurityNoiseNotificationRow(
                Map<String, dynamic>.from(r),
              ),
            )
            .toList();

        _notifications
          ..clear()
          ..addAll(filtered);

        bool isUnread(Map<String, dynamic> r) {
          final v = r['is_read'];
          if (v == null) return true;
          if (v is bool) return !v;
          final s = v.toString().toLowerCase();
          return s != 'true' && s != '1';
        }

        _unreadNotificationsCount = filtered.where(isUnread).length;

        if (kDebugMode) {
          print('[DBG][NOTIF] rows=${_notifications.length}');
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        _ss(() => _loadingNotifications = false);
      }
    }
    await _refreshChatUnreadTotal();
  }

  Future<void> _refreshChatUnreadTotal() async {
    if (_isGuest) {
      _ss(() => _chatUnreadTotal = 0);
      return;
    }
    try {
      final res = await _net(
        () => _sb.rpc('get_chat_list2', params: {'p_limit': 80}),
        tag: 'CHAT_UNREAD',
        showDialog: false,
      );
      if (res == null) return;
      final list = (res is List) ? res : <dynamic>[];
      var sum = 0;
      for (final e in list) {
        if (e is! Map) continue;
        final u = e['unread_count'];
        if (u is int) sum += u;
        if (u is num) sum += u.toInt();
      }
      if (mounted) _ss(() => _chatUnreadTotal = sum);
    } catch (_) {}
  }

  // =========================================================
  // Cache policy
  // =========================================================
  bool _shouldFetchHome() {
    if (_lastHomeFetch == null) return true;
    return DateTime.now().difference(_lastHomeFetch!) >
        _UserDashboardState._cacheDuration;
  }

  bool _shouldFetchMine() {
    if (_lastMineFetch == null) return true;
    return DateTime.now().difference(_lastMineFetch!) >
        _UserDashboardState._cacheDuration;
  }

  bool _shouldFetchCart() {
    if (_lastCartFetch == null) return true;
    return DateTime.now().difference(_lastCartFetch!) >
        _UserDashboardState._cacheDuration;
  }

  bool _shouldFetchFavorites() {
    if (_lastFavoritesFetch == null) return true;
    return DateTime.now().difference(_lastFavoritesFetch!) >
        _UserDashboardState._cacheDuration;
  }

  // =========================================================
  // Reservation helpers
  // =========================================================
  bool _isStillValidReservationRow(Map<String, dynamic> r) {
    final st = (r['status'] ?? '').toString().trim();
    if (st != 'pending' && st != 'paid') return false;

    final ex = _tryParseDt(r['expires_at']);
    if (ex == null) return true;

    return ex.isAfter(DateTime.now());
  }

  // =========================================================
  // Profile loaders
  // =========================================================
  void _syncInAppHubFromProfileCache() {
    final selfUid = _uid;
    if (selfUid.isEmpty) {
      InAppNotificationHub.setSessionUserId(null);
      return;
    }
    InAppNotificationHub.setSessionUserId(selfUid);
    final me = _profileCache[selfUid];
    final un = (me?['username'] ?? '').toString().trim();
    InAppNotificationHub.setSessionUsername(un.isEmpty ? null : un);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesByUserIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final ids = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    final uncachedIds =
        ids.where((id) => !_profileCache.containsKey(id)).toList();

    if (uncachedIds.isEmpty) {
      if (ids.contains(_uid)) {
        _syncInAppHubFromProfileCache();
      }
      return Map.fromEntries(
        ids.map((id) => MapEntry(id, _profileCache[id] ?? <String, dynamic>{})),
      );
    }

    try {
      final data = await _net(() {
        return _sb
            .from('users_profiles')
            .select('user_id,username')
            .inFilter('user_id', uncachedIds);
      }, showDialog: false, tag: 'PROFILES');

      if (data == null) return {};

      final rows = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final r in rows) {
        final uid = (r['user_id'] ?? '').toString().trim();
        if (uid.isNotEmpty) {
          _profileCache[uid] = r;
        }
      }

      _syncInAppHubFromProfileCache();

      if (kDebugMode) {
        print(
          '[DBG][PROFILES] fetched=${rows.length} uncached=${uncachedIds.length}',
        );
      }

      final result = <String, Map<String, dynamic>>{};
      for (final id in ids) {
        result[id] = _profileCache[id] ?? <String, dynamic>{};
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  String _displayNameFromProfile(Map<String, dynamic>? prof) {
    if (prof == null) return '';

    String pick(dynamic v) => (v?.toString() ?? '').trim();

    if (_isArabic) {
      final quadAr = [
        pick(prof['first_name_ar']),
        pick(prof['second_name_ar']),
        pick(prof['third_name_ar']),
        pick(prof['fourth_name_ar']),
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (quadAr.isNotEmpty) return quadAr;

      final fullAr = pick(prof['full_name_ar']);
      if (fullAr.isNotEmpty) return fullAr;
    } else {
      final quadEn = [
        pick(prof['first_name_en']),
        pick(prof['second_name_en']),
        pick(prof['third_name_en']),
        pick(prof['fourth_name_en']),
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (quadEn.isNotEmpty) return quadEn;

      final fullEn = pick(prof['full_name_en']);
      if (fullEn.isNotEmpty) return fullEn;
    }

    final full = pick(prof['full_name']);
    if (full.isNotEmpty) return full;

    return pick(prof['username']);
  }

  String _phoneFromProfile(Map<String, dynamic>? prof) {
    if (prof == null) return '';
    return (prof['phone'] ?? '').toString().trim();
  }

  Future<Map<String, Map<String, dynamic>>>
      _fetchActiveReservationsByPropertyIds(
    List<String> propertyIds,
  ) async {
    if (_isGuest) return {};
    if (propertyIds.isEmpty) return {};

    final ids = propertyIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    try {
      final data = await _net(() {
        return _sb
            .from('reservations')
            .select('property_id, user_id, status, created_at, expires_at')
            .inFilter('property_id', ids)
            .inFilter('status', ['pending', 'paid']).order('created_at',
                ascending: false);
      }, showDialog: false, tag: 'ACTIVE_RES');

      if (data == null) return {};

      final rows = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final byProp = <String, Map<String, dynamic>>{};
      final userIds = <String>{};
      final counts = <String, int>{};

      for (final r in rows) {
        if (!_isStillValidReservationRow(r)) continue;

        final pid = (r['property_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;

        counts[pid] = (counts[pid] ?? 0) + 1;

        if (!byProp.containsKey(pid)) {
          byProp[pid] = r;
          final uid = (r['user_id'] ?? '').toString().trim();
          if (uid.isNotEmpty) userIds.add(uid);
        }
      }

      final profMap = await _fetchProfilesByUserIds(userIds.toList());

      for (final e in byProp.entries) {
        final r = e.value;
        final uid = (r['user_id'] ?? '').toString().trim();
        final prof = profMap[uid];
        r['reserved_by_name'] = _displayNameFromProfile(prof);
        r['_active_reservation_count'] = counts[e.key] ?? 1;
      }

      if (kDebugMode) {
        print('[DBG][RES] rows=${rows.length} byProp=${byProp.length}');
      }

      return byProp;
    } catch (_) {
      return {};
    }
  }

  // =========================================================
  // Property row helpers
  // =========================================================
  List<Map<String, dynamic>> _loaderSortedImagesFromRow(Map row) {
    final raw = row['property_images'];
    final List<Map<String, dynamic>> images;

    if (raw == null) {
      images = [];
    } else if (raw is Map) {
      images = [Map<String, dynamic>.from(raw)];
    } else if (raw is List) {
      images = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      images = [];
    }

    if (images.length > 1) {
      images.sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
    }

    return images;
  }

  String? _loaderImagePathFromMap(Map<String, dynamic> e) {
    for (final k in const [
      'path',
      'url',
      'file_path',
      'storage_path',
      'file_name',
    ]) {
      final s = e[k]?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  List<String> _loaderImageUrlsFromRow(Map row) {
    final direct = _normalizeImageUrls(
      _loaderSortedImagesFromRow(row)
          .map(_loaderImagePathFromMap)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList(),
    );

    if (direct.isNotEmpty) return direct;

    return _normalizeImageUrls([
      ...((row['images'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty),
      ...((row['image_urls'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty),
      if (((row['image_url'] ?? '').toString().trim()).isNotEmpty)
        (row['image_url'] ?? '').toString().trim(),
    ]);
  }

  Future<Map<String, Map<String, dynamic>>> _ownerProfilesForRows(
    List<Map> rows,
  ) async {
    if (_isGuest) return const {};

    final ownerIds = rows
        .map((r) => (r['owner_id'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return _fetchProfilesByUserIds(ownerIds);
  }

  Property _propertyFromRowWithProfiles(
    Map row,
    Map<String, Map<String, dynamic>> ownerProfiles,
  ) {
    final imageUrls = _loaderImageUrlsFromRow(row);

    final ownerId = (row['owner_id'] ?? '').toString().trim();
    final ownerProfile = ownerProfiles[ownerId];
    final ownerName = _displayNameFromProfile(ownerProfile);
    final ownerPhone = _phoneFromProfile(ownerProfile);

    final fallbackUsername =
        ((row['username'] as String?)?.trim().isNotEmpty ?? false)
            ? (row['username'] as String).trim()
            : null;

    final viewingAsOwner =
        _uid.isNotEmpty && (row['owner_id'] ?? '').toString().trim() == _uid;
    final effectiveShow = viewingAsOwner || _effectiveShowOwnerOnListing(row);
    final ownerUsername = effectiveShow
        ? (ownerName.isNotEmpty ? ownerName : fallbackUsername)
        : null;

    final property = _propertyFromDb(
      row,
      imageUrls: imageUrls,
      ownerUsername: ownerUsername,
      ownerPhone: ownerPhone,
      omitOwnerDisplayForPrivacy: !effectiveShow,
    );

    if (property.id.isNotEmpty) {
      _propertyCache[property.id] = property;
    }

    return property;
  }

  // =========================================================
  // Home
  // =========================================================

  bool _errorLooksLikeMissingHomeFeedSuppressedColumn(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('home_feed_suppressed') ||
        s.contains('42703') ||
        s.contains('undefined_column') ||
        (s.contains('schema cache') && s.contains('properties'));
  }

  bool _errorLooksLikeMissingRequestPriorityColumn(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('request_priority') ||
        s.contains('42703') ||
        s.contains('undefined_column') ||
        (s.contains('schema cache') && s.contains('market_property_requests'));
  }

  bool _errorLooksLikeUnauthorized(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('401') ||
        s.contains('unauthorized') ||
        s.contains('jwt') ||
        s.contains('permission denied');
  }

  Future<dynamic> _propertiesHomeQuery({required bool filterSuppressed}) {
    var qb = _sb
        .from('properties')
        .select(_UserDashboardState._propertiesSelect)
        .neq('status', 'deleted');
    if (filterSuppressed) {
      // `= false` يستبعد NULL في SQL؛ الصفوف القديمة بدون عمود أو بقيمة NULL يجب أن تبقى ظاهرة.
      qb = qb.or('home_feed_suppressed.is.null,home_feed_suppressed.eq.false');
    }
    return qb
        .or(SupabaseSchemaSelects.propertiesHomeFeedOrFilter)
        .order('created_at', ascending: false);
  }

  Future<void> _loadHome({bool force = false}) async {
    if (_loadingHome) return;

    if (!force && !_shouldFetchHome() && _all.isNotEmpty) {
      return;
    }

    _ss(() {
      _loadingHome = true;
      _errorHome = null;
      _homeLoadingSince = DateTime.now();
    });

    try {
      dynamic data;
      try {
        data = await _net(
          () => _propertiesHomeQuery(filterSuppressed: true),
          tag: 'HOME',
        );
      } catch (e) {
        if (_errorLooksLikeMissingHomeFeedSuppressedColumn(e)) {
          if (kDebugMode) {
            print('[DBG][HOME] retry without home_feed_suppressed filter');
          }
          data = await _net(
            () => _propertiesHomeQuery(filterSuppressed: false),
            tag: 'HOME_FALLBACK',
          );
        } else {
          rethrow;
        }
      }

      // إن حجبها [AppSession.hasInternet] رجع null، نُعيد المحاولة مباشرةً (بدون guard)
      // حتى لا تبقى الرئيسية فارغة بصمت.
      if (data == null) {
        try {
          data = await _propertiesHomeQuery(filterSuppressed: true);
        } catch (e) {
          if (_errorLooksLikeMissingHomeFeedSuppressedColumn(e)) {
            try {
              data = await _propertiesHomeQuery(filterSuppressed: false);
            } catch (_) {}
          }
        }
      }
      if (data == null) {
        // بدون هذا يبقى [_all] كما كان (غالباً فارغاً) دون [_errorHome] — الرئيسية تبدو «فارغة» بلا سبب.
        _ss(() {
          _errorHome = _isArabic
              ? 'تعذّر جلب إعلانات الرئيسية: لا استجابة من الشبكة أو تم إيقاف الطلب (تحقق من الاتصال وإعدادات Supabase/الـ RLS).'
              : 'Could not load home listings: no network response or the request was blocked (check connectivity and Supabase/RLS).';
        });
        return;
      }

      final rows = (data as List).cast<Map>();

      if (kDebugMode) {
        print('[DBG][HOME] rows=${rows.length}');
      }

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      _activeReservationByPropertyId
          .removeWhere((k, v) => !propIds.contains(k));

      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds);
      final ownerProfiles = await _ownerProfilesForRows(rows);

      final list = rows
          .map((row) => _propertyFromRowWithProfiles(row, ownerProfiles))
          .toList();

      if (kDebugMode && list.isNotEmpty) {
        final pub =
            list.where(ListingPermissionsHelper.shouldShowInPublicHome).length;
        if (pub == 0) {
          final s = list.first;
          print(
            '[DBG][HOME] WARNING: 0/${list.length} pass shouldShowInPublicHome '
            '(sample status=${s.status} wf=${s.workflowStage} suppressed=${s.homeFeedSuppressed})',
          );
        } else {
          print('[DBG][HOME] parsed=${list.length} publicHome=$pub');
        }
      }

      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      await UserListingPreferencesService.pruneHiddenAgainstKnownPropertyIds(
        propIds,
      );

      // إن كانت قائمة «إخفاء من الرئيسية» تغطي كل ما جلبه الخادم، تصبح الشبكة
      // فارغة دون فلاتر علوية — نمسح إخفاء الرئيسية تلقائياً (مرة لكل جلب ناجح).
      final hiddenAfterPrune =
          await UserListingPreferencesService.hiddenPropertyIds();
      final loadedIdSet = propIds.toSet();
      if (loadedIdSet.isNotEmpty &&
          loadedIdSet.every(hiddenAfterPrune.contains)) {
        await UserListingPreferencesService.clearHomeFeedHideSets();
        if (kDebugMode) {
          print(
            '[DBG][HOME] cleared home-feed hide set (all loaded rows were hidden)',
          );
        }
        if (mounted) await _reloadHiddenFeedPreferences();
      }

      _ss(() {
        _all = list;
        _lastHomeFetch = DateTime.now();
        _rebuildFavoritesFromCache();
      });
      if (mounted) {
        unawaited(_reloadHiddenFeedPreferences());
      }
    } catch (e) {
      if (_isGuest && _errorLooksLikeUnauthorized(e)) {
        if (kDebugMode) {
          print('[DBG][HOME] guest public listings blocked by RLS/auth: $e');
        }
        _ss(() {
          _all = <Property>[];
          _lastHomeFetch = DateTime.now();
          _errorHome = null;
        });
        return;
      }
      _ss(() {
        _errorHome = e.toString();
      });
    } finally {
      if (mounted) {
        _ss(() {
          _loadingHome = false;
          _homeLoadingSince = null;
        });
      }
    }
  }

  // =========================================================
  // طلبات السوق (الرئيسية) — يتجاهل الخطأ إن لم يُنفَّذ SQL بعد.
  // =========================================================
  Future<void> _loadMarketHomeRequests({bool force = false}) async {
    if (_loadingMarketRequests && !force) return;
    _ss(() {
      _loadingMarketRequests = true;
      _errorMarketRequests = null;
    });
    const selectWithPriorityDetails =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,request_priority,details_json,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    const selectWithPriority =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,request_priority,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    const selectLegacy =
        'id,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,status';

    bool _missingColumn(Object e, String col) {
      final s = e.toString().toLowerCase();
      return s.contains(col.toLowerCase()) &&
          (s.contains('column') ||
              s.contains('schema') ||
              s.contains('could not find'));
    }

    Future<List<Map<String, dynamic>>> _fetchMarketRows(
        String selectCols) async {
      final d = await _net(() {
        return _sb
            .from('market_property_requests')
            .select(selectCols)
            .inFilter(
              'status',
              SupabaseSchemaSelects.marketPropertyRequestsHomeStatuses,
            )
            .order('created_at', ascending: false)
            .limit(1000);
      }, tag: 'MARKET_REQ_HOME', showDialog: false);
      if (d == null) return const [];
      return (d as List)
          .cast<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    try {
      late List<Map<String, dynamic>> rowMaps;
      try {
        rowMaps = await _fetchMarketRows(selectWithPriorityDetails);
      } catch (e) {
        if (_missingColumn(e, 'request_public_code') ||
            _missingColumn(e, 'edit_count') ||
            _missingColumn(e, 'selected_offer_id')) {
          rowMaps = await _fetchMarketRows(selectLegacy);
        } else if (_missingColumn(e, 'details_json')) {
          if (kDebugMode) {
            print('[DBG][MARKET_REQ_HOME] retry without details_json');
          }
          try {
            rowMaps = await _fetchMarketRows(selectWithPriority);
          } catch (e2) {
            if (_missingColumn(e2, 'request_public_code') ||
                _missingColumn(e2, 'edit_count') ||
                _missingColumn(e2, 'selected_offer_id') ||
                _errorLooksLikeMissingRequestPriorityColumn(e2)) {
              rowMaps = await _fetchMarketRows(selectLegacy);
            } else {
              rethrow;
            }
          }
        } else if (_errorLooksLikeMissingRequestPriorityColumn(e)) {
          rowMaps = await _fetchMarketRows(selectLegacy);
        } else {
          rethrow;
        }
      }

      if (rowMaps.isEmpty) {
        _ss(() => _marketHomeRequests = const []);
        return;
      }

      final uids = rowMaps
          .map((m) => (m['requester_id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final avatarByUid = <String, String>{};
      if (!_isGuest && uids.isNotEmpty) {
        try {
          final prof = await _sb
              .from('users_profiles')
              .select('user_id,avatar_url')
              .inFilter('user_id', uids);
          for (final p in (prof as List).cast<Map>()) {
            final uid = (p['user_id'] ?? '').toString().trim();
            final url = (p['avatar_url'] ?? '').toString().trim();
            if (uid.isNotEmpty && url.isNotEmpty) avatarByUid[uid] = url;
          }
        } catch (_) {}
      }

      final list = rowMaps
          .map((m) {
            final uid = (m['requester_id'] ?? '').toString().trim();
            final u = avatarByUid[uid];
            if (u != null) m['requester_avatar_url'] = u;
            return MarketPropertyRequestRow.fromMap(m);
          })
          .where(
            (r) =>
                r.id.isNotEmpty &&
                ListingPermissionsHelper.shouldShowMarketRequestInPublicHome(
                  r.status,
                ),
          )
          .toList(growable: false);

      await UserListingPreferencesService.pruneHiddenAgainstKnownRequestIds(
        list.map((r) => r.id),
      );

      _ss(() => _marketHomeRequests = list);
      if (mounted) {
        unawaited(_reloadHiddenFeedPreferences());
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MARKET_REQ_HOME] skip: $e');
      }
      _ss(() {
        _errorMarketRequests = e.toString();
        _marketHomeRequests = const [];
      });
    } finally {
      if (mounted) {
        _ss(() => _loadingMarketRequests = false);
      }
    }
  }

  // =========================================================
  // Favorites list
  // =========================================================
  Future<void> _loadFavoritesList({bool force = false}) async {
    if (_isGuest || _favoriteIds.isEmpty) {
      _ss(() {
        _favoritesList = <Property>[];
        _loadingFavorites = false;
        _errorFavorites = null;
        _favLoadingSince = null;
        _lastFavoritesFetch = DateTime.now();
      });
      return;
    }

    if (!force && !_shouldFetchFavorites() && _favoritesList.isNotEmpty) {
      return;
    }

    _ss(() {
      _loadingFavorites = true;
      _errorFavorites = null;
      _favLoadingSince = DateTime.now();
      _rebuildFavoritesFromCache();
    });

    try {
      final ids = _favoriteIds.toList();

      final data = await _net(() {
        return _sb
            .from('properties')
            .select(_UserDashboardState._propertiesSelect)
            .inFilter('id', ids)
            .neq('status', 'deleted')
            .or(SupabaseSchemaSelects.propertiesHomeFeedOrFilter)
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false);
      }, tag: 'FAV_LIST');

      if (data == null) return;

      final rows = (data as List).cast<Map>();

      if (kDebugMode) {
        print('[DBG][FAV] rows=${rows.length} ids=${_favoriteIds.length}');
      }

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds);
      final ownerProfiles = await _ownerProfilesForRows(rows);

      for (final row in rows) {
        _propertyFromRowWithProfiles(row, ownerProfiles);
      }

      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      _ss(() {
        _rebuildFavoritesFromCache();
        _lastFavoritesFetch = DateTime.now();
      });
    } catch (e) {
      _ss(() => _errorFavorites = e.toString());
    } finally {
      if (mounted) {
        _ss(() {
          _loadingFavorites = false;
          _favLoadingSince = null;
        });
      }
    }
  }

  // =========================================================
  // Mine + offers
  // =========================================================
  Future<void> _loadMineAndOffers({bool force = false}) async {
    if (!force && !_shouldFetchMine() && _mine.isNotEmpty) return;

    _ss(() {
      _loadingMine = true;
      _loadingOffers = true;
      _errorMine = null;
      _errorOffers = null;
      _offersCount = 0;
      _mineLoadingSince = DateTime.now();
      _offersLoadingSince = DateTime.now();
    });

    try {
      if (_uid.isEmpty) {
        _ss(() {
          _mine = <Property>[];
          _offers = <Map<String, dynamic>>[];
          _offersCount = 0;
          _myPropertyById = {};
          _lastMineFetch = DateTime.now();
        });
        return;
      }

      _myPropertyById = {};

      final mineData = await _net(() {
        return _sb
            .from('properties')
            .select(_UserDashboardState._propertiesSelect)
            .eq('owner_id', _uid)
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false);
      }, tag: 'MINE');

      if (mineData == null) return;

      final mineRows = (mineData as List).cast<Map>();

      if (kDebugMode) {
        print('[DBG][MINE] rows=${mineRows.length} uid=$_uid');
      }

      final myProfile = (await _fetchProfilesByUserIds([_uid]))[_uid];
      final myName = _displayNameFromProfile(myProfile);
      final myPhone = _phoneFromProfile(myProfile);

      final mineList = mineRows.map((row) {
        final imageUrls = _loaderImageUrlsFromRow(row);

        final fallbackUsername =
            ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['username'] as String).trim()
                : null;

        final rowOwnerName =
            (row['owner_display_name'] ?? '').toString().trim();
        String? ownerUsername = myName.isNotEmpty
            ? myName
            : (fallbackUsername ??
                (rowOwnerName.isNotEmpty ? rowOwnerName : null));
        if ((ownerUsername ?? '').trim().isEmpty) {
          final email = _sb.auth.currentUser?.email?.trim();
          if (email != null && email.isNotEmpty) {
            final local = email.contains('@') ? email.split('@').first : email;
            if (local.isNotEmpty) ownerUsername = local;
          }
        }

        final property = _propertyFromDb(
          row,
          imageUrls: imageUrls,
          ownerUsername: ownerUsername,
          ownerPhone: myPhone,
        );

        if (property.id.isNotEmpty) {
          _propertyCache[property.id] = property;
          _myPropertyById[property.id] = property;
        }

        return property;
      }).toList();

      _ss(() {
        _mine = mineList;
        _lastMineFetch = DateTime.now();
        _rebuildFavoritesFromCache();
      });

      final myIds =
          mineList.map((p) => p.id).where((id) => id.isNotEmpty).toList();

      if (myIds.isEmpty) {
        _ss(() {
          _offers = <Map<String, dynamic>>[];
          _offersCount = 0;
        });
        return;
      }

      final offersData = await _net(() {
        return _sb
            .from('reservations')
            .select('''
              id,
              property_id,
              user_id,
              status,
              created_at,
              expires_at,
              base_price,
              platform_fee_amount,
              extra_fee_amount,
              total_amount
            ''')
            .inFilter('property_id', myIds)
            .order('created_at', ascending: false);
      }, tag: 'OFFERS');

      if (offersData == null) return;

      final offersRowsRaw = (offersData as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (kDebugMode) {
        print('[DBG][OFFERS] rowsRaw=${offersRowsRaw.length}');
      }

      final offersRows =
          offersRowsRaw.where(_isStillValidReservationRow).toList();

      final userIds = offersRows
          .map((r) => (r['user_id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final profMap = await _fetchProfilesByUserIds(userIds);

      for (final r in offersRows) {
        final uid = (r['user_id'] ?? '').toString().trim();
        final prof = profMap[uid];
        r['reserved_by_name'] = _displayNameFromProfile(prof);
        r['reserved_by_phone'] = (prof?['phone'] ?? '').toString().trim();
        r['reserved_by_city'] = (prof?['city'] ?? '').toString().trim();
        r['reserved_by_account_type'] =
            (prof?['account_type'] ?? '').toString().trim();
        r['reserved_by_license_no'] =
            (prof?['license_no'] ?? '').toString().trim();
      }

      int cnt = 0;
      for (final r in offersRows) {
        final st = (r['status'] ?? '').toString().trim();
        if (st == 'pending' || st == 'paid') {
          cnt++;
        }
      }

      final myActiveRes = await _fetchActiveReservationsByPropertyIds(myIds);
      for (final e in myActiveRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      _ss(() {
        _offers = offersRows;
        _offersCount = cnt;
      });

      if (kDebugMode) {
        print(
          '[DBG][OFFERS] rowsValid=${offersRows.length} activePendingCnt=$cnt',
        );
      }
    } catch (e) {
      _ss(() {
        _errorMine = e.toString();
        _errorOffers = e.toString();
      });
    } finally {
      if (mounted) {
        _ss(() {
          _loadingMine = false;
          _loadingOffers = false;
          _mineLoadingSince = null;
          _offersLoadingSince = null;
        });
      }
    }
  }

  // =========================================================
  // Cart
  // =========================================================
  Future<void> _loadCart({bool force = false}) async {
    if (!force && !_shouldFetchCart() && _cart.isNotEmpty) return;

    _ss(() {
      _loadingCart = true;
      _errorCart = null;
      _cartLoadingSince = DateTime.now();
      _cartCount = 0;
    });

    try {
      if (_uid.isEmpty) {
        _ss(() {
          _cart = <Map<String, dynamic>>[];
          _cartPropertyById = {};
          _completedCart = <Map<String, dynamic>>[];
          _completedCartPropertyById = {};
          _cartCount = 0;
          _lastCartFetch = DateTime.now();
        });
        return;
      }

      final cartData = await _net(() {
        return _sb
            .from('reservations')
            .select('''
              id,
              property_id,
              user_id,
              status,
              created_at,
              expires_at,
              base_price,
              platform_fee_amount,
              extra_fee_amount,
              total_amount
            ''')
            .eq('user_id', _uid)
            .inFilter('status', ['pending', 'paid'])
            .order('created_at', ascending: false);
      }, tag: 'CART');

      if (cartData == null) return;

      final cartRowsRaw = (cartData as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (kDebugMode) {
        print('[DBG][CART] rowsRaw=${cartRowsRaw.length}');
      }

      final cartRows = cartRowsRaw.where(_isStillValidReservationRow).toList();

      final completedData = await _net(() {
        return _sb
            .from('reservations')
            .select('''
              id,
              property_id,
              user_id,
              status,
              created_at,
              expires_at,
              base_price,
              platform_fee_amount,
              extra_fee_amount,
              total_amount
            ''')
            .eq('user_id', _uid)
            .inFilter('status', ['completed', 'sold'])
            .order('created_at', ascending: false);
      }, tag: 'CART_COMPLETED');

      final completedRows = completedData == null
          ? <Map<String, dynamic>>[]
          : (completedData as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final pids = <String>{
        ...cartRows
            .map((r) => (r['property_id'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty),
        ...completedRows
            .map((r) => (r['property_id'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty),
      }.toList();

      Map<String, Property> byId = {};

      if (pids.isNotEmpty) {
        final uncachedIds =
            pids.where((id) => !_propertyCache.containsKey(id)).toList();

        if (uncachedIds.isNotEmpty) {
          final propsData = await _net(() {
            return _sb
                .from('properties')
                .select(_UserDashboardState._propertiesSelect)
                .inFilter('id', uncachedIds);
          }, tag: 'CART_PROPS');

          if (propsData != null) {
            final rows = (propsData as List).cast<Map>();

            if (kDebugMode) {
              print(
                '[DBG][CART->PROPS] fetched=${rows.length} uncached=${uncachedIds.length}',
              );
            }

            final ownerProfiles = await _ownerProfilesForRows(rows);

            for (final row in rows) {
              _propertyFromRowWithProfiles(row, ownerProfiles);
            }
          }
        }

        for (final id in pids) {
          final property = _propertyCache[id];
          if (property != null) {
            byId[id] = property;
          }
        }
      }

      _ss(() {
        _cart = cartRows;
        _cartPropertyById = byId;
        _completedCart = completedRows;
        _completedCartPropertyById = byId;
        _cartCount = cartRows.length;
        _lastCartFetch = DateTime.now();
      });
    } catch (e) {
      _ss(() => _errorCart = e.toString());
    } finally {
      if (mounted) {
        _ss(() {
          _loadingCart = false;
          _cartLoadingSince = null;
        });
      }
    }
  }

  // =========================================================
  // عروضي على طلبات السوق (إخفاء من الرئيسية + قسم السلة)
  // =========================================================
  Future<void> _loadMyMarketRequestOfferTracking() async {
    if (_isGuest) {
      _ss(() {
        _marketRequestIdsWithMyPendingOffer = <String>{};
        _myPendingMarketOffersForCart = const [];
      });
      return;
    }
    try {
      final list =
          await MarketingFlowService(_sb).myActiveMarketRequestOffers();
      final ids = list
          .map((m) => (m['market_request_id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      _ss(() {
        _marketRequestIdsWithMyPendingOffer = ids;
        _myPendingMarketOffersForCart = list;
      });
    } catch (_) {
      _ss(() {
        _marketRequestIdsWithMyPendingOffer = <String>{};
        _myPendingMarketOffersForCart = const [];
      });
    }
  }

  // =========================================================
  // Full reload
  // =========================================================
  Future<void> _reloadAll() async {
    if (_isGuest) {
      _ss(() {
        _errorHome = null;
        _mine = <Property>[];
        _favoritesList = <Property>[];
        _cart = <Map<String, dynamic>>[];
        _offers = <Map<String, dynamic>>[];
        _offersCount = 0;
        _myPropertyById = {};
        _resetOwnerRequestBuckets();
        _resetMarketerBuckets();
      });

      await Future.wait([
        _loadHome(force: true),
        _loadMarketHomeRequests(force: true),
      ]);

      if (kDebugMode) {
        print('[DBG][RELOAD_ALL][GUEST] done');
      }
      return;
    }

    if (!_favoritesLoaded) {
      await _loadFavoritesForUid();
    }

    await _loadAccountRole();

    await Future.wait([
      _loadHome(force: true),
      _loadMarketHomeRequests(force: true),
      _loadMineAndOffers(force: true),
      _loadCart(force: true),
      _loadNotifications(),
      _loadMyMarketRequestOfferTracking(),
    ]);

    if (_favoritesLoaded) {
      _ss(() {
        _rebuildFavoritesFromCache();
      });

      if (_favoriteIds.isNotEmpty) {
        await _loadFavoritesList(force: true);
      }
    }

    if (_isMarketerRole) {
      await _loadMarketerBuckets(force: true);
    } else {
      await _loadOwnerRequestsBuckets(force: true);
    }

    if (kDebugMode) {
      print('[DBG][RELOAD_ALL] done');
      print(
        '[DBG][RELOAD_ALL] uid=$_uid accountType=$_accountType isMarketer=$_isMarketerRole',
      );
      print('[DBG][RELOAD_ALL] mine=${_mine.length}');
      print(
        '[DBG][RELOAD_ALL] owner listing_requests=${_ownerListingRequests.length}',
      );
      print(
        '[DBG][RELOAD_ALL] marketer invites=${_mkInvites.length} offers=${_mkOffers.length} contracts=${_mkContracts.length} permits=${_mkPermits.length} published=${_mkPublished.length}',
      );
    }
  }
}
