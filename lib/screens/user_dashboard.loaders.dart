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
    final prune = <String>[];

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

      if (p == null) continue;
      if (_listingCompletedDealForFavorites(p)) {
        prune.add(p.id);
        continue;
      }
      if (seen.add(p.id)) {
        list.add(p);
      }
    }

    if (prune.isNotEmpty) {
      _favoriteIds.removeAll(prune);
      unawaited(_saveFavoritesForUid());
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

        _unreadNotificationsCount = filtered
            .where(MarketingFlowService.countsForInboxUnreadBadge)
            .length;

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
    // ضيف: RLS يرفض users_profiles بدون auth.uid → 401 حتمي يُثقل الشبكة والكونسول.
    if (_isGuest || userIds.isEmpty) return {};

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
            .select(
              'user_id,username,phone,'
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name',
            )
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

      // حدّث كاش اسم التحية فوراً بعد جلب ملفي.
      if (_uid.isNotEmpty && _profileCache.containsKey(_uid)) {
        final nm = _displayNameFromProfile(_profileCache[_uid]).trim();
        if (nm.isNotEmpty) {
          unawaited(DashboardGreetingCache.save(_uid, nm));
          if (nm != _greetingNameCache) {
            _greetingNameCache = nm;
          }
        }
      }

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

    final u = pick(prof['username']);
    final email = _sb.auth.currentUser?.email?.trim();
    if (email != null &&
        email.contains('@') &&
        u.isNotEmpty &&
        RegExp(r'^\d{9,12}$').hasMatch(u)) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return u;
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
        .where((s) => s.isNotEmpty);

    final marketerIds = rows
        .map((r) => (r['published_by_marketer_id'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty);

    final ids = <String>{...ownerIds, ...marketerIds}.toList();
    if (ids.isEmpty) return {};
    return _fetchProfilesByUserIds(ids);
  }

  /// يستبدل سطر المسوّق على البطاقة إذا كان من الترخيص يبدو كرقم هوية وتوفر اسم من users_profiles.
  Property _propertyWithMarketerProfileOverlay(
    Property p,
    Map<String, Map<String, dynamic>> profiles,
  ) {
    final mid = (p.publishedByMarketerId ?? '').trim();
    if (mid.isEmpty) return p;
    final prof = profiles[mid];
    final nm = _displayNameFromProfile(prof);
    if (nm.isEmpty) return p;

    final current = (p.marketerEntityPublicLine(_isArabic) ?? '').trim();
    final digitsOnly =
        current.replaceAll(RegExp(r'[\s\-\.]'), '').trim().isNotEmpty &&
            RegExp(r'^\d+$').hasMatch(
              current.replaceAll(RegExp(r'[\s\-\.]'), ''),
            );
    final shortLicense =
        current.isNotEmpty && current.length <= 12 && digitsOnly;
    final useProfile = current.isEmpty || shortLicense;

    if (!useProfile) return p;

    final snap = p.marketingLicenseSnapshot;
    final merged = snap == null || snap.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(snap);
    merged['fal_broker_full_name'] = nm;
    merged['fal_broker_name'] = nm;
    merged['brokerage_name'] = nm;
    return p.copyWith(marketingLicenseSnapshot: merged);
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

    final property = _propertyWithMarketerProfileOverlay(
      _propertyFromDb(
        row,
        imageUrls: imageUrls,
        ownerUsername: ownerUsername,
        ownerPhone: ownerPhone,
        omitOwnerDisplayForPrivacy: !effectiveShow,
      ),
      ownerProfiles,
    );

    if (property.id.isNotEmpty) {
      _propertyCache[property.id] = property;
    }

    return property;
  }

  /// يملأ سعر/مساحة/عمولة التسويق من listing_requests إن كان سجل العقار ناقصاً بعد النشر.
  Future<List<Property>> _enrichPublishedPropertiesFromRequests(
    List<Property> list,
    List<Map<dynamic, dynamic>> rows,
  ) async {
    if (list.isEmpty || rows.isEmpty || list.length != rows.length) {
      return list;
    }

    final reqIds = <String>{};
    for (var i = 0; i < list.length; i++) {
      final p = list[i];
      if (p.price > 0 && p.area > 0 && p.marketingLicenseSnapshot != null) {
        continue;
      }
      final rid = (rows[i]['request_id'] ?? '').toString().trim();
      if (rid.isNotEmpty) reqIds.add(rid);
    }
    if (reqIds.isEmpty) return list;

    try {
      final raw = await _net<dynamic>(
        () => _sb
            .from('listing_requests')
            .select(
              'id,price,request_price,preview_price,'
              'price_includes_vat,vat_rate,marketing_commission_kind,'
              'marketing_commission_rate,marketing_commission_amount,payload_json',
            )
            .inFilter('id', reqIds.toList()),
        tag: 'ENRICH_PROP_FROM_REQ',
      );
      final byId = <String, Map<String, dynamic>>{};
      for (final e in (raw as List)) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? '').toString().trim();
        if (id.isNotEmpty) byId[id] = m;
      }
      if (byId.isEmpty) return list;

      double pickPrice(Map<String, dynamic> req, Property p) {
        if (p.price > 0) return p.price;
        num? n;
        for (final k in ['preview_price', 'request_price', 'price']) {
          final v = req[k];
          if (v is num && v > 0) return v.toDouble();
          n = num.tryParse('$v');
          if (n != null && n > 0) return n.toDouble();
        }
        final pl = req['payload_json'];
        if (pl is Map) {
          final pv = pl['price'];
          if (pv is num && pv > 0) return pv.toDouble();
          final parsed = num.tryParse('$pv');
          if (parsed != null && parsed > 0) return parsed.toDouble();
        }
        return p.price;
      }

      double pickArea(Map<String, dynamic> req, Property p) {
        if (p.area > 0) return p.area;
        final pl = req['payload_json'];
        if (pl is Map) {
          final av = pl['area'];
          if (av is num && av > 0) return av.toDouble();
        }
        return p.area;
      }

      final out = <Property>[];
      for (var i = 0; i < list.length; i++) {
        var p = list[i];
        final rid = (rows[i]['request_id'] ?? '').toString().trim();
        final req = byId[rid];
        if (req == null) {
          out.add(p);
          continue;
        }
        final price = pickPrice(req, p);
        final area = pickArea(req, p);
        if (price != p.price ||
            area != p.area ||
            req['marketing_commission_kind'] != null) {
          p = p.copyWith(
            price: price > 0 ? price : p.price,
            area: area > 0 ? area : p.area,
            priceIncludesVat: p.priceIncludesVat,
            vatRate: (req['vat_rate'] as num?)?.toDouble() ?? p.vatRate,
            marketingCommissionKind:
                (req['marketing_commission_kind'] ?? p.marketingCommissionKind)
                    ?.toString(),
            marketingCommissionRate:
                (req['marketing_commission_rate'] as num?)?.toDouble() ??
                    p.marketingCommissionRate,
            marketingCommissionAmount:
                (req['marketing_commission_amount'] as num?)?.toDouble() ??
                    p.marketingCommissionAmount,
          );
        }
        out.add(p);
      }
      return out;
    } catch (_) {
      return list;
    }
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

  /// PostgREST 42501 when RLS policies call helper functions without anon EXECUTE.
  bool _errorLooksLikeHomeFeedRlsDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('42501') ||
        (s.contains('permission denied') &&
            (s.contains('property_marketer_public_verified') ||
                s.contains('property_public_publish_ready') ||
                s.contains('property_has_listing_media') ||
                s.contains('property_image_public_home_readable')));
  }

  String _homeFeedRlsDeniedMessage() {
    return _isArabic
        ? 'تعذّر عرض إعلانات الرئيسية: صلاحيات قاعدة البيانات للزائر غير مكتملة. طبّق migration «20260518120000_public_home_feed_function_grants» على Supabase ثم أعد المحاولة.'
        : 'Home listings are blocked: database guest permissions are incomplete. Apply migration «20260518120000_public_home_feed_function_grants» on Supabase, then retry.';
  }

  String _homeFeedUnauthorizedMessage() {
    return _isArabic
        ? 'تعذّر جلب الإعلانات (401). الأسباب الشائعة:\n'
            '• سياسة RLS لجدول property_images غير مطبّقة — نفّذ supabase/sql/APPLY_NOW_fix_property_images_401_home_feed.sql\n'
            '• جلسة JWT قديمة — Ctrl+F5 أو مسح بيانات الموقع\n'
            '• مفتاح Publishable ناقص في web/supabase_config.json'
        : 'Could not load listings (401). Common causes:\n'
            '• Missing property_images RLS — run APPLY_NOW_fix_property_images_401_home_feed.sql on Supabase\n'
            '• Stale JWT in browser — hard refresh / clear site data\n'
            '• Incomplete Publishable key in web/supabase_config.json';
  }

  Future<List<dynamic>> _propertiesHomeQuery({
    required bool filterSuppressed,
    bool allowBypassCircuit = false,
  }) {
    final limit = kIsWeb
        ? _UserDashboardState.homeFeedFetchLimitWeb
        : _UserDashboardState.homeFeedFetchLimit;
    return PropertiesHomeFeedService.fetch(
      client: _sb,
      filterSuppressed: filterSuppressed,
      limit: limit,
      allowBypassCircuit: allowBypassCircuit,
    );
  }

  Future<void> _retryHomeFeedLoad() async {
    PropertiesHomeFeedService.resetCircuit();
    await _loadHome(force: true, userInitiated: true);
  }

  /// تحليل صفوف الرئيسية على دفعات — يمنع تجمّد واجهة الويب عند `select(*)` ثقيل.
  Future<List<Property>> _parseHomeRowsYielding(
    List<Map> rows,
    Map<String, Map<String, dynamic>> ownerProfiles,
  ) async {
    final batch = kIsWeb ? 3 : 6;
    final list = <Property>[];
    for (var i = 0; i < rows.length; i++) {
      if (!mounted) break;
      list.add(_propertyFromRowWithProfiles(rows[i], ownerProfiles));
      if (kIsWeb && (i + 1) % batch == 0 && i + 1 < rows.length) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }
    return list;
  }

  /// بعد أول إطار على الويب: حجوزات فقط — بدون إعادة بناء القائمة (يمنع وميض البطاقة).
  Future<void> _enrichHomeFeedAfterFirstPaint(
    List<String> propIds,
    List<Map> rows,
  ) async {
    if (!kIsWeb || !mounted) return;
    if (_isGuest) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds)
          .timeout(const Duration(seconds: 12));
      if (!mounted || activeRes.isEmpty) return;
      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }
      _ssHomeFeed(() {});
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][HOME] web enrich deferred failed: $e');
      }
    }
  }

  Future<void> _loadHome({
    bool force = false,
    bool userInitiated = false,
  }) async {
    if (!userInitiated && PropertiesHomeFeedService.isCircuitOpen) {
      WebBootstrapDiag.warn('home.fetch', 'skipped — circuit open');
      _ssHomeFeed(() {
        if (_errorHome == null) {
          _errorHome = _isArabic
              ? 'تعذّر جلب الإعلانات مؤقتاً بعد خطأ مصادقة. انتظر دقيقة أو اضغط «تحديث».'
              : 'Home listings are temporarily paused after an auth error. Wait a minute or tap Refresh.';
        }
      });
      return;
    }
    if (userInitiated) {
      PropertiesHomeFeedService.resetCircuit();
    }

    // منع عاصفة home.fetch: لا تُعِد الجلب القسري إن كانت البيانات حديثة.
    if (force &&
        !userInitiated &&
        _all.isNotEmpty &&
        _lastHomeFetch != null &&
        DateTime.now().difference(_lastHomeFetch!) <
            const Duration(seconds: 4)) {
      return;
    }

    // السماح بـ «تحديث قسري» حتى لو جلب سابق لم ينتهِ بعد (تجنّب زر تحديث بلا أثر).
    if (_loadingHome && !force && !userInitiated) return;
    if (force && _loadingHome) {
      final since = _homeLoadingSince;
      if (since != null &&
          DateTime.now().difference(since) > const Duration(seconds: 28)) {
        if (kDebugMode) {
          print('[DBG][HOME] reset stuck _loadingHome before force reload');
        }
        _loadingHome = false;
      } else {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (_loadingHome && mounted && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    }

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
      // ويب: لا تمرّ عبر [_net]/runNetworkGuarded — بعد تسجيل الدخول قد يعيد null
      // (context/token) فيفرّغ الرئيسية بينما الضيف يرى نفس البيانات عبر fetch مباشر.
      Future<dynamic> loadProps({required bool filterSuppressed}) async {
        if (kIsWeb) {
          return _propertiesHomeQuery(
            filterSuppressed: filterSuppressed,
            allowBypassCircuit: true,
          );
        }
        return _net(
          () => _propertiesHomeQuery(
            filterSuppressed: filterSuppressed,
            allowBypassCircuit: userInitiated,
          ),
          tag: filterSuppressed ? 'HOME' : 'HOME_FALLBACK',
        );
      }

      try {
        data = await loadProps(filterSuppressed: true);
      } catch (e) {
        if (_errorLooksLikeUnauthorized(e) ||
            SupabasePublicReadGuard.isAuthError(e)) {
          rethrow;
        }
        if (_errorLooksLikeMissingHomeFeedSuppressedColumn(e)) {
          if (kDebugMode) {
            print('[DBG][HOME] retry without home_feed_suppressed filter');
          }
          data = await loadProps(filterSuppressed: false);
        } else {
          rethrow;
        }
      }

      if (data == null) {
        // بدون هذا يبقى [_all] كما كان (غالباً فارغاً) دون [_errorHome] — الرئيسية تبدو «فارغة» بلا سبب.
        WebBootstrapDiag.warn('home.fetch', 'null response (net guard?)');
        _ssHomeFeed(() {
          _errorHome = _isArabic
              ? 'تعذّر جلب إعلانات الرئيسية: لا استجابة من الشبكة أو تم إيقاف الطلب (تحقق من الاتصال وإعدادات Supabase/الـ RLS).'
              : 'Could not load home listings: no network response or the request was blocked (check connectivity and Supabase/RLS).';
        });
        return;
      }
      if (kIsWeb) {
        final n = (data is List) ? data.length : -1;
        WebBootstrapDiag.log(
          'home.fetch',
          'raw=$n circuit=${PropertiesHomeFeedService.isCircuitOpen}',
        );
      }

      final rows = (data as List).cast<Map>();

      if (kDebugMode) {
        print('[DBG][HOME] rows=${rows.length}');
      }
      if (kIsWeb && rows.isEmpty && _errorHome == null) {
        WebBootstrapDiag.warn(
          'home.empty',
          'server returned 0 properties — not a UI freeze; check Supabase data/RLS',
        );
      }

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      _activeReservationByPropertyId
          .removeWhere((k, v) => !propIds.contains(k));

      var list = kIsWeb
          ? await _parseHomeRowsYielding(
              rows,
              const <String, Map<String, dynamic>>{},
            )
          : rows
              .map(
                (row) => _propertyFromRowWithProfiles(
                  row,
                  <String, Map<String, dynamic>>{},
                ),
              )
              .toList();

      var activeRes = <String, Map<String, dynamic>>{};

      if (kIsWeb) {
        // طبّق فوراً — الطابور المؤجّل كان يترك rows=0 رغم raw>0 عند الازدواج/الفلَش.
        _all = list;
        _lastHomeFetch = DateTime.now();
        _rebuildFavoritesFromCache();
        _nestedDashboardFeedCacheBuiltKey = -1;
        _webTabChildren = null;
        _webTabChildrenFeedSig = -1;
        _markDashboardFeedDirty();
        WebBootstrapDiag.log('home.apply', 'sync rows=${_all.length}');
        // إطار واحد لإعادة الرسم دون تأجيل الطابور السابق على _all الفارغ.
        if (mounted) {
          _ssHomeFeed(() {});
        }
        unawaited(_enrichHomeFeedAfterFirstPaint(propIds, rows));
        unawaited(() async {
          final enriched = await _enrichPublishedPropertiesFromRequests(
            list,
            rows.cast<Map<dynamic, dynamic>>(),
          );
          if (!mounted || identical(enriched, list)) return;
          var changed = false;
          if (enriched.length != list.length) {
            changed = true;
          } else {
            for (var i = 0; i < list.length; i++) {
              final a = list[i];
              final b = enriched[i];
              if (a.price != b.price ||
                  a.area != b.area ||
                  a.marketingCommissionKind != b.marketingCommissionKind ||
                  a.marketingCommissionRate != b.marketingCommissionRate ||
                  a.marketingCommissionAmount != b.marketingCommissionAmount ||
                  a.vatRate != b.vatRate) {
                changed = true;
                break;
              }
            }
          }
          // لا تستبدل القائمة إن لم يتغيّر شيء — يمنع وميض البطاقة.
          if (!changed) return;
          _ssHomeFeed(() {
            _all = enriched;
            _rebuildFavoritesFromCache();
          });
        }());
      } else {
        // ملفّات المالك + الحجوزات معاً، ثم إثراء واحد (تجنّب إثراء يُستبدل فوراً).
        final homeEnrich =
            await Future.wait<Map<String, Map<String, dynamic>>>([
          _fetchActiveReservationsByPropertyIds(propIds),
          _ownerProfilesForRows(rows),
        ]);
        activeRes = homeEnrich[0];
        final ownerProfiles = homeEnrich[1];
        list = rows
            .map((row) => _propertyFromRowWithProfiles(row, ownerProfiles))
            .toList();
        list = await _enrichPublishedPropertiesFromRequests(
          list,
          rows.cast<Map<dynamic, dynamic>>(),
        );
      }

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

      if (!_isGuest) {
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
      }

      if (!kIsWeb) {
        _ssHomeFeed(() {
          _all = list;
          _lastHomeFetch = DateTime.now();
          _rebuildFavoritesFromCache();
        });
      }
      // الضيف يتجاهل قائمة الإخفاء محلياً — لا تحملها من الجهاز (كانت تورّث من جلسة سابقة).
      if (mounted && !_isGuest) {
        unawaited(_reloadHiddenFeedPreferences());
      }
    } catch (e) {
      if (_errorLooksLikeUnauthorized(e) ||
          SupabasePublicReadGuard.isAuthError(e)) {
        if (kDebugMode) {
          print('[DBG][HOME] auth/401 blocked home feed: $e');
        }
        _ssHomeFeed(() {
          _all = <Property>[];
          _lastHomeFetch = DateTime.now();
          _errorHome = _homeFeedUnauthorizedMessage();
        });
        return;
      }
      if (_errorLooksLikeHomeFeedRlsDenied(e)) {
        if (kDebugMode) {
          print('[DBG][HOME] public listings blocked by RLS: $e');
        }
        _ssHomeFeed(() {
          _all = <Property>[];
          _lastHomeFetch = DateTime.now();
          _errorHome = _homeFeedRlsDeniedMessage();
        });
        return;
      }
      _ssHomeFeed(() {
        _errorHome = e.toString();
      });
    } finally {
      if (mounted) {
        _ss(() {
          _loadingHome = false;
          _homeLoadingSince = null;
        });
        _flushHomeFeedMutationsSync();
      }
    }
  }

  // =========================================================
  // طلبات السوق التي قدّمها المستخدم (تبويب «طلباتي»)
  // =========================================================
  Future<void> _loadMyMarketSubmissions({bool force = false}) async {
    if (_isGuest || _uid.isEmpty) {
      _ss(() {
        _myMarketSubmissions = const [];
        _loadingMyMarketSubmissions = false;
      });
      return;
    }
    if (_loadingMyMarketSubmissions && !force) return;
    _ss(() => _loadingMyMarketSubmissions = true);
    const selectCols =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,request_priority,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    try {
      final rows = await _net(() {
        return _sb
            .from('market_property_requests')
            .select(selectCols)
            .eq('requester_id', _uid)
            .order('created_at', ascending: false)
            .limit(60);
      }, tag: 'MY_MARKET_SUBMISSIONS', showDialog: false);
      if (rows == null) {
        _ss(() => _myMarketSubmissions = const []);
        return;
      }
      final list = (rows as List)
          .cast<Map>()
          .map((m) => MarketPropertyRequestRow.fromMap(
                Map<String, dynamic>.from(m),
              ))
          .where((r) => r.id.isNotEmpty)
          .toList(growable: false);
      _ss(() => _myMarketSubmissions = list);
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MY_MARKET_SUBMISSIONS] skip: $e');
      }
      _ss(() => _myMarketSubmissions = const []);
    } finally {
      if (mounted) {
        _ss(() => _loadingMyMarketSubmissions = false);
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
      _marketRequestsLoadingSince = DateTime.now();
      _errorMarketRequests = null;
    });
    const selectWithPriorityDetails =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,request_priority,details_json,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    const selectWithPriority =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,request_priority,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    const selectLegacy =
        'id,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,status';

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
        return SupabasePublicReadGuard.run(_sb, () {
          return _sb
              .from('market_property_requests')
              .select(selectCols)
              .inFilter(
                'status',
                SupabaseSchemaSelects.marketPropertyRequestsHomeStatuses,
              )
              .order('created_at', ascending: false)
              .limit(
                kIsWeb
                    ? _UserDashboardState.marketHomeRequestsFetchLimitWeb
                    : _UserDashboardState.marketHomeRequestsFetchLimit,
              );
        });
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
        // الويب: استعلام أخف أولاً (بدون details_json) لتقليل زمن الانتظار ومحاولات 400 المتتابعة.
        rowMaps = kIsWeb
            ? await _fetchMarketRows(selectWithPriority)
            : await _fetchMarketRows(selectWithPriorityDetails);
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
        _ssHomeFeed(() => _marketHomeRequests = const []);
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
          // يجب _net/timeout — بدونها يعلق التحميل ويبقى _loadingMarketRequests=true
          // فيُرجع _buildHomeBody شاشة فارغة إلى الأبد.
          final prof = await _net(() {
            return _sb
                .from('users_profiles')
                .select('user_id,avatar_url')
                .inFilter('user_id', uids);
          }, tag: 'MARKET_REQ_AVATARS', showDialog: false);
          if (prof != null) {
            for (final p in (prof as List).cast<Map>()) {
              final uid = (p['user_id'] ?? '').toString().trim();
              final url = (p['avatar_url'] ?? '').toString().trim();
              if (uid.isNotEmpty && url.isNotEmpty) avatarByUid[uid] = url;
            }
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
                ListingPermissionsHelper.shouldShowMarketRequestWithoutDeal(r),
          )
          .toList(growable: false);

      await UserListingPreferencesService.pruneHiddenAgainstKnownRequestIds(
        list.map((r) => r.id),
      );

      _ssHomeFeed(() => _marketHomeRequests = list);
      if (mounted) {
        unawaited(_reloadHiddenFeedPreferences());
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MARKET_REQ_HOME] skip: $e');
      }
      _ssHomeFeed(() {
        _errorMarketRequests = e.toString();
        _marketHomeRequests = const [];
      });
    } finally {
      if (mounted) {
        _ss(() {
          _loadingMarketRequests = false;
          _marketRequestsLoadingSince = null;
        });
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

      final favEnrich =
          await Future.wait<Map<String, Map<String, dynamic>>>([
        _fetchActiveReservationsByPropertyIds(propIds),
        _ownerProfilesForRows(rows),
      ]);
      final activeRes = favEnrich[0];
      final ownerProfiles = favEnrich[1];

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

      final mineLimit = kIsWeb
          ? _UserDashboardState.minePropertiesFetchLimitWeb
          : _UserDashboardState.minePropertiesFetchLimit;
      final mineSelect = _UserDashboardState._propertiesSelect;

      final minePair = await Future.wait<dynamic>([
        _net(() {
          return _sb
              .from('properties')
              .select(mineSelect)
              .eq('owner_id', _uid)
              .order('updated_at', ascending: false)
              .order('created_at', ascending: false)
              .limit(mineLimit);
        }, tag: 'MINE'),
        _net(() {
          return _sb
              .from('properties')
              .select(mineSelect)
              .eq('published_by_marketer_id', _uid)
              .order('updated_at', ascending: false)
              .order('created_at', ascending: false)
              .limit(mineLimit);
        }, tag: 'MINE_PUBLISHED_BY'),
      ]);
      final mineData = minePair[0];
      final publishedByMeData = minePair[1];

      if (mineData == null && publishedByMeData == null) return;

      final byId = <String, Map>{};
      for (final raw in [
        if (mineData is List) ...mineData,
        if (publishedByMeData is List) ...publishedByMeData,
      ]) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byId[id] = raw;
      }
      final mineRows = byId.values.toList();

      if (kDebugMode) {
        print('[DBG][MINE] rows=${mineRows.length} uid=$_uid');
      }

      final myIdsEarly = mineRows
          .map((r) => (r['id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final mineParallel = <Future<dynamic>>[
        _ownerProfilesForRows(mineRows),
      ];
      if (myIdsEarly.isNotEmpty) {
        mineParallel.add(
          _net(() {
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
                .inFilter('property_id', myIdsEarly)
                .order('created_at', ascending: false);
          }, tag: 'OFFERS'),
        );
      }

      final mineParallelOut = await Future.wait(mineParallel);
      final mineProfiles =
          mineParallelOut[0] as Map<String, Map<String, dynamic>>;
      final offersDataPrefetched =
          myIdsEarly.isNotEmpty ? mineParallelOut[1] : null;
      final myProfile = mineProfiles[_uid];
      final myName = _displayNameFromProfile(myProfile);
      final myPhone = _phoneFromProfile(myProfile);

      final mineList = <Property>[];
      for (var i = 0; i < mineRows.length; i++) {
        final row = mineRows[i];
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

        final property = _propertyWithMarketerProfileOverlay(
          _propertyFromDb(
            row,
            imageUrls: imageUrls,
            ownerUsername: ownerUsername,
            ownerPhone: myPhone,
          ),
          mineProfiles,
        );

        if (property.id.isNotEmpty) {
          _propertyCache[property.id] = property;
          _myPropertyById[property.id] = property;
        }
        mineList.add(property);
        if (kIsWeb && (i + 1) % 5 == 0 && i + 1 < mineRows.length) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      _ss(() {
        _mine = mineList;
        _lastMineFetch = DateTime.now();
        _rebuildFavoritesFromCache();
        // إعلاناتي جاهزة — لا ننتظر جلب العروض/الحجوزات لإخفاء حالة التحميل.
        _loadingMine = false;
        _mineLoadingSince = null;
      });

      final myIds =
          mineList.map((p) => p.id).where((id) => id.isNotEmpty).toList();

      if (myIds.isEmpty) {
        _ss(() {
          _offers = <Map<String, dynamic>>[];
          _offersCount = 0;
          _loadingOffers = false;
          _offersLoadingSince = null;
        });
        return;
      }

      final offersData = offersDataPrefetched;

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

      final offersEnrich =
          await Future.wait<Map<String, Map<String, dynamic>>>([
        _fetchProfilesByUserIds(userIds),
        _fetchActiveReservationsByPropertyIds(myIds),
      ]);
      final profMap = offersEnrich[0];
      final myActiveRes = offersEnrich[1];

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

      final cartParallel = await Future.wait([
        _net(() {
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
        }, tag: 'CART'),
        _net(() {
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
        }, tag: 'CART_COMPLETED'),
      ]);

      final cartData = cartParallel[0];
      final completedData = cartParallel[1];

      if (cartData == null) return;

      final cartRowsRaw = (cartData as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (kDebugMode) {
        print('[DBG][CART] rowsRaw=${cartRowsRaw.length}');
      }

      final cartRows = cartRowsRaw.where(_isStillValidReservationRow).toList();

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

      // _ssHomeFeed: يبلّغ تبويب الرئيسية بإعادة التصفية الفورية حتى يختفي
      // أي إعلان أصبح في السلة دون الحاجة للضغط على «تحديث».
      _ssHomeFeed(() {
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
      _ssHomeFeed(() {
        _marketRequestIdsWithMyPendingOffer = <String>{};
        _marketRequestIdsHiddenAfterTwoWithdrawals = <String>{};
        _myPendingMarketOffersForCart = const [];
        _myArchivedMarketOffersForCart = const [];
      });
      return;
    }
    try {
      final svc = MarketingFlowService(_sb);
      final uid = _uid;
      final results = await Future.wait([
        svc.myActiveMarketRequestOffers(),
        svc.myArchivedMarketRequestOffers(),
        _net(() {
          return _sb
              .from('market_request_offer_user_withdrawals')
              .select('market_request_id,withdrawn_count')
              .eq('user_id', uid)
              .gte('withdrawn_count', 2);
        }, tag: 'MR_OFFER_WITHDRAWALS', showDialog: false),
      ]);
      final list = (results[0] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final archived = (results[1] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      final withdrawList = (results[2] as List?) ?? const [];
      final ids = list
          .map((m) => (m['market_request_id'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      final hiddenAfterTwo = <String>{};
      for (final raw in withdrawList) {
        if (raw is! Map) continue;
        final rid = (raw['market_request_id'] ?? '').toString().trim();
        final count = int.tryParse('${raw['withdrawn_count'] ?? 0}') ?? 0;
        if (rid.isNotEmpty && count >= 2) hiddenAfterTwo.add(rid);
      }
      // _ssHomeFeed: يضمن إخفاء أي طلب قُدِّم عليه عرض من الرئيسية فوراً.
      _ssHomeFeed(() {
        _marketRequestIdsWithMyPendingOffer = ids;
        _marketRequestIdsHiddenAfterTwoWithdrawals = hiddenAfterTwo;
        _myPendingMarketOffersForCart = list;
        _myArchivedMarketOffersForCart = archived;
      });
    } catch (_) {
      _ssHomeFeed(() {
        _marketRequestIdsWithMyPendingOffer = <String>{};
        _marketRequestIdsHiddenAfterTwoWithdrawals = <String>{};
        _myPendingMarketOffersForCart = const [];
        _myArchivedMarketOffersForCart = const [];
      });
    }
  }

  // =========================================================
  // Full reload
  // =========================================================
  Future<void> _reloadAll() async {
    PropertiesHomeFeedService.resetCircuit();

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

    // الويب: الرئيسية + طلبات السوق معاً؛ باقي التبويبات في الخلفية.
    if (kIsWeb) {
      await Future.wait([
        _loadHome(force: true),
        _loadMarketHomeRequests(force: true),
      ]);
      unawaited(_reloadAllLoggedInDeferred());
      return;
    }

    if (!_favoritesLoaded) {
      await _loadFavoritesForUid();
    }

    await Future.wait([
      _loadAccountRole(),
      _loadHome(force: true),
      _loadMarketHomeRequests(force: true),
    ]);

    if (!_favoritesLoaded) {
      await _loadFavoritesForUid();
    }

    await Future.wait([
      _loadMineAndOffers(force: true),
      _loadMyMarketRequestOfferTracking(),
    ]);

    await Future.wait([
      _loadCart(force: true),
      _loadNotifications(),
    ]);

    if (_favoritesLoaded) {
      _ss(() {
        _rebuildFavoritesFromCache();
      });
    }

    final tail = <Future<void>>[];
    if (_favoriteIds.isNotEmpty) {
      tail.add(_loadFavoritesList(force: true));
    }
    if (_isMarketerRole || _usesMarketerMyPageHub) {
      tail.add(_loadMarketerBuckets(force: true));
      tail.add(_loadOwnerRequestsBuckets(force: true));
    } else {
      tail.add(_loadOwnerRequestsBuckets(force: true));
    }
    if (tail.isNotEmpty) {
      await Future.wait(tail);
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

  /// باقي تحميل التبويبات بعد «تحديث» الرئيسية على الويب (لا يعطّل main thread).
  Future<void> _reloadAllLoggedInDeferred() async {
    if (!mounted || _isGuest) return;
    try {
      if (!_favoritesLoaded) {
        await _loadFavoritesForUid();
      }
      // الدور أولاً — buckets المسوّق/المالك تعتمد عليه.
      await _loadAccountRole();
      if (!mounted) return;
      await Future.wait([
        _loadMineAndOffers(force: true),
        _loadMyMarketRequestOfferTracking(),
      ]);
      if (!mounted) return;
      await Future.wait([
        _loadCart(force: true),
        _loadNotifications(),
      ]);
      if (!mounted) return;
      if (_favoritesLoaded) {
        _ss(() {
          _rebuildFavoritesFromCache();
        });
      }
      final tail = <Future<void>>[];
      if (_favoriteIds.isNotEmpty) {
        tail.add(_loadFavoritesList(force: true));
      }
      if (_isMarketerRole) {
        tail.add(_loadMarketerBuckets(force: true));
      } else {
        tail.add(_loadOwnerRequestsBuckets(force: true));
      }
      if (tail.isNotEmpty) {
        await Future.wait(tail);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][RELOAD_ALL][WEB_DEFERRED] $e');
      }
    }
  }

  bool _hasValidMapCoordinates(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.abs() < 1e-5 && lng.abs() < 1e-5) return false;
    return true;
  }

  /// إعلانات منشورة تملك إحداثيات — للخريطة العامة (أوسع من شريحة الرئيسية المحمّلة).
  Future<List<Property>> _loadPublishedPropertiesWithCoordinatesForMap() async {
    try {
      final data = await _net(
        () => PropertiesHomeFeedService.fetch(
          client: _sb,
          filterSuppressed: false,
          limit: _UserDashboardState.mapDiscoveryFetchLimit,
          allowBypassCircuit: true,
        ),
        tag: 'MAP_PROP_COORDS',
        showDialog: false,
      );
      if (data == null) return const [];
      final rows = (data as List).cast<Map>();
      final coordRows = <Map>[];
      for (final r in rows) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (!_hasValidMapCoordinates(lat, lng)) continue;
        coordRows.add(r);
      }
      if (coordRows.isEmpty) return const [];

      final ownerProfiles = await _ownerProfilesForRows(coordRows);
      return coordRows
          .map(
            (row) => _propertyFromRowWithProfiles(
              Map<String, dynamic>.from(row),
              ownerProfiles,
            ),
          )
          .where((p) => p.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP_PROP_COORDS] skip: $e');
      }
      return const [];
    }
  }

  /// طلبات السوق الظاهرة للعامة التي يمكن رسمها على الخريطة.
  Future<List<MarketPropertyRequestRow>>
      _loadMarketRequestsWithCoordinatesForMap() async {
    const selectWithDetails =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,request_priority,details_json,status,'
        'edit_count,max_edits,deletion_requested_at,completed_at,selected_offer_id';
    const selectLegacy =
        'id,request_public_code,title,description,purpose,property_type,city,districts,'
        'budget_min,budget_max,area_min_m2,created_at,updated_at,'
        'requester_id,show_requester_name,requester_public_name,'
        'cover_image_storage_path,default_cover_used,status';

    Future<List<Map<String, dynamic>>> fetch(String cols) async {
      final d = await _net(
        () => _sb
            .from('market_property_requests')
            .select(cols)
            .inFilter(
              'status',
              SupabaseSchemaSelects.marketPropertyRequestsHomeStatuses,
            )
            .order('created_at', ascending: false)
            .limit(_UserDashboardState.mapDiscoveryFetchLimit),
        tag: 'MAP_REQ_COORDS',
        showDialog: false,
      );
      if (d == null) return const [];
      return (d as List)
          .cast<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    try {
      List<Map<String, dynamic>> rowMaps;
      try {
        rowMaps = await fetch(selectWithDetails);
      } catch (e) {
        final s = e.toString().toLowerCase();
        if (s.contains('details_json') ||
            s.contains('request_priority') ||
            s.contains('42703') ||
            s.contains('column')) {
          rowMaps = await fetch(selectLegacy);
        } else {
          rethrow;
        }
      }

      return rowMaps
          .map(MarketPropertyRequestRow.fromMap)
          .where(
            (r) =>
                r.id.isNotEmpty &&
                ListingPermissionsHelper.shouldShowMarketRequestWithoutDeal(r),
          )
          .where((r) => _hasValidMapCoordinates(r.latitude, r.longitude))
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP_REQ_COORDS] skip: $e');
      }
      return const [];
    }
  }
}
