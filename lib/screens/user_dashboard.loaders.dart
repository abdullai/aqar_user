part of 'user_dashboard.dart';

// =========================================
// user_dashboard.loaders.dart
// =========================================
// تحميل البيانات (Home / Mine / Favorites / Cart / Featured / Notifications)
// متوافق مع postgrest (استخدم inFilter)
// ويستخدم static _propertiesSelect داخل _UserDashboardState
// =========================================

extension _UserDashboardStateLoaders on _UserDashboardState {
  // =========================
  // Favorites (Local cache)
  // =========================

  String _favKey(String uid) => 'fav_ids_$uid';

  Future<void> _loadFavoritesForUid() async {
    final uid = _uid;
    if (uid.isEmpty) {
      _favoriteIds.clear();
      _favoritesLoaded = true;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favKey(uid));
    _favoriteIds.clear();

    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
        _favoriteIds.addAll(list);
      } catch (_) {}
    }

    _favoritesLoaded = true;
    if (mounted) _ss(() {});
  }

  Future<void> _saveFavoritesForUid() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favKey(uid), jsonEncode(_favoriteIds.toList()));
  }

  bool _isFav(String id) => _favoriteIds.contains(id);

  Future<void> _toggleFav(String propertyId) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    _ss(() {
      if (_favoriteIds.contains(propertyId)) {
        _favoriteIds.remove(propertyId);
        _showNotification(
          _isArabic ? 'تمت الإزالة' : 'Removed',
          _isArabic ? 'تمت إزالة العقار من المفضلة' : 'Property removed from favorites',
        );
      } else {
        _favoriteIds.add(propertyId);
        _showNotification(
          _isArabic ? 'تمت الإضافة' : 'Added',
          _isArabic ? 'تمت إضافة العقار إلى المفضلة' : 'Property added to favorites',
        );
      }
    });

    await _saveFavoritesForUid();

    if (_tabIndex == 2) {
      await _loadFavoritesList(force: true);
    }
  }

  // =========================
  // Notifications
  // =========================

  Future<void> _loadNotifications() async {
    if (_isGuest) {
      _notifications.clear();
      _unreadNotificationsCount = 0;
      if (mounted) _ss(() => _loadingNotifications = false);
      return;
    }

    _ss(() => _loadingNotifications = true);

    try {
      final data = await _net(() {
        return _sb
            .from('notifications')
            .select('*')
            .eq('user_id', _uid)
            .eq('is_read', false)
            .order('created_at', ascending: false);
      }, tag: 'NOTIF');

      if (data != null) {
        _notifications
          ..clear()
          ..addAll((data as List).cast<Map<String, dynamic>>());
        _unreadNotificationsCount = _notifications.length;

        if (kDebugMode) {
          // ignore: avoid_print
          print('[DBG][NOTIF] rows=${_notifications.length}');
        }
      }
    } catch (_) {
      // صامت
    } finally {
      if (mounted) _ss(() => _loadingNotifications = false);
    }
  }

  // =========================
  // Cache helpers
  // =========================

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

  bool _shouldFetchFeatured() {
    if (_lastFeaturedFetch == null) return true;
    return DateTime.now().difference(_lastFeaturedFetch!) >
        _UserDashboardState._cacheDuration;
  }

  bool _shouldFetchFavorites() {
    if (_lastFavoritesFetch == null) return true;
    return DateTime.now().difference(_lastFavoritesFetch!) >
        _UserDashboardState._cacheDuration;
  }

  // =========================
  // Reservation validity
  // =========================

  bool _isStillValidReservationRow(Map<String, dynamic> r) {
    final st = (r['status'] ?? '').toString();
    if (st != 'pending' && st != 'paid') return false;

    final ex = _tryParseDt(r['expires_at']);
    if (ex == null) return true;
    return ex.isAfter(DateTime.now());
  }

  // =========================
  // Profiles cache fetchers
  // =========================

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesByUserIds(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final uncachedIds =
        userIds.where((id) => !_profileCache.containsKey(id)).toList();

    if (uncachedIds.isEmpty) {
      return Map.fromEntries(
        userIds.map((id) => MapEntry(id, _profileCache[id] ?? {})),
      );
    }

    try {
      final data = await _net(() {
        return _sb
            .from('users_profiles')
            .select(
              'user_id, username, full_name, full_name_ar, full_name_en, '
              'first_name_ar, fourth_name_ar, first_name_en, fourth_name_en',
            )
            .inFilter('user_id', uncachedIds);
      }, showDialog: false, tag: 'PROFILES');

      if (data == null) return {};

      final rows = (data as List).cast<Map>();
      for (final r in rows) {
        final uid = (r['user_id'] ?? '').toString();
        if (uid.isNotEmpty) {
          _profileCache[uid] = r.cast<String, dynamic>();
        }
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][PROFILES] fetched=${rows.length} uncached=${uncachedIds.length}');
      }

      final result = <String, Map<String, dynamic>>{};
      for (final id in userIds) {
        result[id] = _profileCache[id] ?? {};
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
      final fl =
          '${pick(prof['first_name_ar'])} ${pick(prof['fourth_name_ar'])}'.trim();
      if (fl.isNotEmpty) return fl;
      final ar = pick(prof['full_name_ar']);
      if (ar.isNotEmpty) return ar;
    } else {
      final fl =
          '${pick(prof['first_name_en'])} ${pick(prof['fourth_name_en'])}'.trim();
      if (fl.isNotEmpty) return fl;
      final en = pick(prof['full_name_en']);
      if (en.isNotEmpty) return en;
    }

    final full = pick(prof['full_name']);
    if (full.isNotEmpty) return full;
    return pick(prof['username']);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchActiveReservationsByPropertyIds(
    List<String> propertyIds,
  ) async {
    if (propertyIds.isEmpty) return {};

    try {
      final data = await _net(() {
        return _sb
            .from('reservations')
            .select('property_id, user_id, status, created_at, expires_at')
            .inFilter('property_id', propertyIds)
            .inFilter('status', ['pending', 'paid'])
            .order('created_at', ascending: false);
      }, showDialog: false, tag: 'ACTIVE_RES');

      if (data == null) return {};

      final rows = (data as List).cast<Map<String, dynamic>>();

      final byProp = <String, Map<String, dynamic>>{};
      final userIds = <String>{};

      for (final r in rows) {
        if (!_isStillValidReservationRow(r)) continue;

        final pid = (r['property_id'] ?? '').toString();
        if (pid.isEmpty) continue;

        if (!byProp.containsKey(pid)) {
          byProp[pid] = r;
          final uid = (r['user_id'] ?? '').toString();
          if (uid.isNotEmpty) userIds.add(uid);
        }
      }

      final profMap = await _fetchProfilesByUserIds(userIds.toList());
      for (final e in byProp.entries) {
        final r = e.value;
        final uid = (r['user_id'] ?? '').toString();
        final prof = profMap[uid];
        r['reserved_by_name'] = _displayNameFromProfile(prof);
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][RES] rows=${rows.length} byProp=${byProp.length}');
      }

      return byProp;
    } catch (_) {
      return {};
    }
  }

  // =========================
  // Sortable images helper
  // =========================

  List<Map<String, dynamic>> _sortedImagesFromRow(Map row) {
    final raw = (row['property_images'] as List?) ?? const [];
    final images = List<Map<String, dynamic>>.from(
      raw.map((e) => (e as Map).cast<String, dynamic>()),
    );

    if (images.length > 1) {
      images.sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
    }
    return images;
  }

  // =========================
  // HOME
  // =========================

  Future<void> _loadHome({bool force = false}) async {
    if (!force && !_shouldFetchHome() && _all.isNotEmpty) return;

    _ss(() {
      _loadingHome = true;
      _errorHome = null;
      _homeLoadingSince = DateTime.now();
    });

    try {
      final data = await _net(() {
        return _sb
            .from('properties')
            .select(_UserDashboardState._propertiesSelect)
            .or('status.in.(active,available,published),status.is.null')
            .order('created_at', ascending: false);
      }, tag: 'HOME');

      if (data == null) return;

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][HOME] rows=${(data as List).length}');
      }

      final rows = (data as List).cast<Map>();

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      _activeReservationByPropertyId.removeWhere((k, v) => !propIds.contains(k));

      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds);

      final ownerIds = rows
          .map((r) => (r['owner_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final ownerProfiles = await _fetchProfilesByUserIds(ownerIds);

      final list = rows.map((row) {
        final imagesRaw = _sortedImagesFromRow(row);

        final imageUrls = imagesRaw
            .map((e) => (e['path'] as String?)?.trim())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .map((p) => _sb.storage.from('property-images').getPublicUrl(p))
            .toList();

        final ownerId = (row['owner_id'] ?? '').toString();
        final ownerName = _displayNameFromProfile(ownerProfiles[ownerId]);
        final ownerUsername = ownerName.isNotEmpty
            ? ownerName
            : ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['username'] as String).trim()
                : null;

        final property = _propertyFromDb(
          row,
          imageUrls: imageUrls,
          ownerUsername: ownerUsername,
        );

        if (property.id.isNotEmpty) {
          _propertyCache[property.id] = property;
        }

        return property;
      }).toList();

      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      _ss(() {
        _all = list;
        _lastHomeFetch = DateTime.now();
      });
    } catch (e) {
      _ss(() => _errorHome = e.toString());
    } finally {
      if (mounted) {
        _ss(() {
          _loadingHome = false;
          _homeLoadingSince = null;
        });
      }
    }
  }

  // =========================
  // FEATURED
  // =========================

  Future<void> _loadFeaturedProperties({bool force = false}) async {
    if (!force && !_shouldFetchFeatured()) return;

    _ss(() => _loadingFeatured = true);

    try {
      final data = await _net(() {
        return _sb
            .from('properties')
            .select(_UserDashboardState._propertiesSelect)
            .eq('is_featured', true)
            .or('status.in.(active,available,published),status.is.null')
            .order('created_at', ascending: false)
            .limit(5);
      }, tag: 'FEATURED');

      if (data == null) return;

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][FEATURED] rows=${(data as List).length}');
      }

      final rows = (data as List).cast<Map>();

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds);

      final ownerIds = rows
          .map((r) => (r['owner_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final ownerProfiles = await _fetchProfilesByUserIds(ownerIds);

      final featuredList = rows.map((row) {
        final imagesRaw = _sortedImagesFromRow(row);

        final imageUrls = imagesRaw
            .map((e) => (e['path'] as String?)?.trim())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .map((p) => _sb.storage.from('property-images').getPublicUrl(p))
            .toList();

        final ownerId = (row['owner_id'] ?? '').toString();
        final ownerName = _displayNameFromProfile(ownerProfiles[ownerId]);
        final ownerUsername = ownerName.isNotEmpty
            ? ownerName
            : ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['username'] as String).trim()
                : null;

        final p = _propertyFromDb(
          row,
          imageUrls: imageUrls,
          ownerUsername: ownerUsername,
        );

        if (p.id.isNotEmpty) _propertyCache[p.id] = p;
        return p;
      }).toList();

      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      _ss(() {
        _featuredProperties
          ..clear()
          ..addAll(featuredList);
        _lastFeaturedFetch = DateTime.now();
      });
    } catch (_) {
      // صامت
    } finally {
      if (mounted) _ss(() => _loadingFeatured = false);
    }
  }

  // =========================
  // FAVORITES LIST
  // =========================

  Future<void> _loadFavoritesList({bool force = false}) async {
    if (!force && !_shouldFetchFavorites() && _favoritesList.isNotEmpty) return;

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

    _ss(() {
      _loadingFavorites = true;
      _errorFavorites = null;
      _favLoadingSince = DateTime.now();
    });

    try {
      final data = await _net(() {
        return _sb
            .from('properties')
            .select(_UserDashboardState._propertiesSelect)
            .inFilter('id', _favoriteIds.toList())
            .or('status.in.(active,available,published),status.is.null')
            .order('created_at', ascending: false);
      }, tag: 'FAV_LIST');

      if (data == null) return;

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][FAV] rows=${(data as List).length} ids=${_favoriteIds.length}');
      }

      final rows = (data as List).cast<Map>();

      final propIds = rows
          .map((r) => (r['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      final activeRes = await _fetchActiveReservationsByPropertyIds(propIds);

      final ownerIds = rows
          .map((r) => (r['owner_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final ownerProfiles = await _fetchProfilesByUserIds(ownerIds);

      final favoritesList = rows.map((row) {
        final imagesRaw = _sortedImagesFromRow(row);

        final imageUrls = imagesRaw
            .map((e) => (e['path'] as String?)?.trim())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .map((p) => _sb.storage.from('property-images').getPublicUrl(p))
            .toList();

        final ownerId = (row['owner_id'] ?? '').toString();
        final ownerName = _displayNameFromProfile(ownerProfiles[ownerId]);
        final ownerUsername = ownerName.isNotEmpty
            ? ownerName
            : ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['username'] as String).trim()
                : null;

        final p = _propertyFromDb(
          row,
          imageUrls: imageUrls,
          ownerUsername: ownerUsername,
        );

        if (p.id.isNotEmpty) _propertyCache[p.id] = p;
        return p;
      }).toList();

      for (final e in activeRes.entries) {
        _activeReservationByPropertyId[e.key] = e.value;
      }

      _ss(() {
        _favoritesList = favoritesList;
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

  // =========================
  // MINE + OFFERS
  // =========================

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
            .or('status.in.(active,available,published),status.is.null')
            .order('created_at', ascending: false);
      }, tag: 'MINE');

      if (mineData == null) return;

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][MINE] rows=${(mineData as List).length} uid=$_uid');
      }

      final mineRows = (mineData as List).cast<Map>();

      final myProfile = (await _fetchProfilesByUserIds([_uid]))[_uid];
      final myName = _displayNameFromProfile(myProfile);

      final mineList = mineRows.map((row) {
        final imagesRaw = _sortedImagesFromRow(row);

        final imageUrls = imagesRaw
            .map((e) => (e['path'] as String?)?.trim())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .map((p) => _sb.storage.from('property-images').getPublicUrl(p))
            .toList();

        final ownerUsername = myName.isNotEmpty
            ? myName
            : ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                ? (row['username'] as String).trim()
                : null;

        final p = _propertyFromDb(
          row,
          imageUrls: imageUrls,
          ownerUsername: ownerUsername,
        );

        if (p.id.isNotEmpty) {
          _propertyCache[p.id] = p;
          _myPropertyById[p.id] = p;
        }
        return p;
      }).toList();

      _ss(() {
        _mine = mineList;
        _lastMineFetch = DateTime.now();
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

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][OFFERS] rowsRaw=${(offersData as List).length}');
      }

      final offersRowsRaw = (offersData as List).cast<Map<String, dynamic>>();
      final offersRows = offersRowsRaw.where(_isStillValidReservationRow).toList();

      final userIds = offersRows
          .map((r) => (r['user_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final profMap = await _fetchProfilesByUserIds(userIds);

      for (final r in offersRows) {
        final uid = (r['user_id'] ?? '').toString();
        r['reserved_by_name'] = _displayNameFromProfile(profMap[uid]);
      }

      int cnt = 0;
      for (final r in offersRows) {
        final st = (r['status'] ?? '').toString();
        if (st == 'pending' || st == 'paid') cnt++;
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
        // ignore: avoid_print
        print('[DBG][OFFERS] rowsValid=${offersRows.length} activePendingCnt=$cnt');
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

  // =========================
  // CART
  // =========================

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

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][CART] rowsRaw=${(cartData as List).length}');
      }

      final cartRowsRaw = (cartData as List).cast<Map<String, dynamic>>();
      final cartRows = cartRowsRaw.where(_isStillValidReservationRow).toList();

      final pids = cartRows
          .map((r) => (r['property_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

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
            if (kDebugMode) {
              // ignore: avoid_print
              print(
                  '[DBG][CART->PROPS] fetched=${(propsData as List).length} uncached=${uncachedIds.length}');
            }

            final rows = (propsData as List).cast<Map>();

            final ownerIds = rows
                .map((r) => (r['owner_id'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList();

            final ownerProfiles = await _fetchProfilesByUserIds(ownerIds);

            for (final row in rows) {
              final imagesRaw = _sortedImagesFromRow(row);

              final imageUrls = imagesRaw
                  .map((e) => (e['path'] as String?)?.trim())
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .map((p) => _sb.storage.from('property-images').getPublicUrl(p))
                  .toList();

              final ownerId = (row['owner_id'] ?? '').toString();
              final ownerName = _displayNameFromProfile(ownerProfiles[ownerId]);
              final ownerUsername = ownerName.isNotEmpty
                  ? ownerName
                  : ((row['username'] as String?)?.trim().isNotEmpty ?? false)
                      ? (row['username'] as String).trim()
                      : null;

              final p = _propertyFromDb(
                row,
                imageUrls: imageUrls,
                ownerUsername: ownerUsername,
              );

              if (p.id.isNotEmpty) _propertyCache[p.id] = p;
            }
          }
        }

        for (final id in pids) {
          final p = _propertyCache[id];
          if (p != null) byId[id] = p;
        }
      }

      _ss(() {
        _cart = cartRows;
        _cartPropertyById = byId;
        _cartCount = cartRows.length;
        _lastCartFetch = DateTime.now();
      });

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][CART] rowsValid=${cartRows.length} propsInMap=${byId.length}');
      }
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

  // =========================
  // RELOAD ALL
  // =========================

  Future<void> _reloadAll() async {
    // ✅ للضيف: لا تستدعي Mine/Cart/Fav/Notif لأنها قد تُظهر حوارات أو تبقى تدور
    if (_isGuest) {
      await Future.wait([
        _loadHome(force: true),
        _loadFeaturedProperties(force: true),
      ]);

      if (kDebugMode) {
        // ignore: avoid_print
        print('[DBG][RELOAD_ALL][GUEST] done');
      }
      return;
    }

    await Future.wait([
      _loadHome(force: true),
      _loadMineAndOffers(force: true),
      _loadCart(force: true),
      _loadFeaturedProperties(force: true),
      _loadNotifications(),
    ]);

    if (!_favoritesLoaded) {
      await _loadFavoritesForUid();
    }

    if (_favoritesLoaded && _favoriteIds.isNotEmpty) {
      await _loadFavoritesList(force: true);
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[DBG][RELOAD_ALL] done');
    }
  }
}
