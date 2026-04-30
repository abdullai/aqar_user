part of 'user_dashboard.dart';

extension _UserDashboardStateFilters on _UserDashboardState {
  static Map<String, dynamic>? _citiesCache;

  String _norm(String? v) {
    var s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return '';

    const arDigits = '٠١٢٣٤٥٦٧٨٩';
    const faDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(arDigits[i], '$i').replaceAll(faDigits[i], '$i');
    }

    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[_\-–—/#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return s;
  }

  String _flattenSearchValue(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key} ${_flattenSearchValue(e.value)}')
          .join(' ');
    }
    if (value is Iterable) {
      return value.map(_flattenSearchValue).join(' ');
    }
    return value.toString();
  }

  List<String> _tokens(String? v) {
    final s = _norm(v);
    if (s.isEmpty) return const <String>[];
    return s.split(' ').where((e) => e.trim().isNotEmpty).toList();
  }

  bool _containsAllTokens(String haystack, List<String> tokens) {
    if (tokens.isEmpty) return true;
    if (haystack.isEmpty) return false;

    for (final t in tokens) {
      if (!haystack.contains(t)) return false;
    }
    return true;
  }

  int _searchScore(Property p, String queryRaw) {
    final q = _norm(queryRaw);
    if (q.isEmpty) return 0;

    final tokens = _tokens(q);
    if (tokens.isEmpty) return 0;

    String region = '';
    String ownerPhone = '';
    try {
      region = _norm((p as dynamic).region?.toString());
    } catch (_) {}
    try {
      ownerPhone = _norm((p as dynamic).ownerPhone?.toString());
    } catch (_) {}

    final typeTextAr = switch (p.type) {
      PropertyType.villa => 'فيلا',
      PropertyType.apartment => 'شقة',
      PropertyType.land => 'أرض',
    };

    final typeTextEn = switch (p.type) {
      PropertyType.villa => 'villa',
      PropertyType.apartment => 'apartment',
      PropertyType.land => 'land',
    };

    final title = _norm(p.title);
    final description = _norm(p.description);
    final publicCode = _norm(p.listingPublicCode);
    final id = _norm(p.id);
    final ownerId = _norm(p.ownerId);
    final city = _norm(p.city);
    final location = _norm(p.location);
    final address = _norm(p.addressLine);
    final locationText = _norm(p.locationText);
    final owner = _norm(p.ownerDisplayName);
    final marketer = _norm(p.marketerEntityPublicLine(_isArabic));
    final marketerSnapshot =
        _norm(_flattenSearchValue(p.marketingLicenseSnapshot));
    final guidance = _norm(_flattenSearchValue(p.listingGuidance));
    final contactPhone = _norm(p.contactPhone);
    final priceText = _norm(p.price.toStringAsFixed(0));
    final areaText = _norm(p.area.toStringAsFixed(0));
    final purpose = _norm(PropertyListingDisplay.purposeLabel(p, _isArabic));
    final purposeAr = _norm(PropertyListingDisplay.purposeLabel(p, true));
    final purposeEn = _norm(PropertyListingDisplay.purposeLabel(p, false));
    final deedNumber = _norm(p.deedNumber);
    final buildingNumber = _norm(p.buildingNumber);
    final typeAr = _norm(typeTextAr);
    final typeEn = _norm(typeTextEn);

    int scoreField(String value, int exactWeight, int containsWeight) {
      if (value.isEmpty) return 0;
      if (value == q) return exactWeight;
      if (value.contains(q)) return containsWeight;
      if (_containsAllTokens(value, tokens)) {
        return (containsWeight * 0.7).round();
      }
      return 0;
    }

    int score = 0;
    score += scoreField(publicCode, 160, 130);
    score += scoreField(id, 115, 80);
    score += scoreField(title, 120, 90);
    score += scoreField(city, 90, 70);
    score += scoreField(location, 85, 65);
    score += scoreField(address, 75, 55);
    score += scoreField(locationText, 80, 60);
    score += scoreField(region, 75, 55);
    score += scoreField(description, 55, 35);
    score += scoreField(owner, 45, 30);
    score += scoreField(ownerId, 35, 18);
    score += scoreField(marketer, 65, 45);
    score += scoreField(marketerSnapshot, 70, 48);
    score += scoreField(guidance, 34, 18);
    score += scoreField(contactPhone, 35, 25);
    score += scoreField(ownerPhone, 35, 25);
    score += scoreField(priceText, 50, 35);
    score += scoreField(areaText, 50, 35);
    score += scoreField(purpose, 50, 34);
    score += scoreField(purposeAr, 50, 34);
    score += scoreField(purposeEn, 50, 34);
    score += scoreField(deedNumber, 45, 30);
    score += scoreField(buildingNumber, 35, 24);
    score += scoreField(typeAr, 60, 40);
    score += scoreField(typeEn, 60, 40);

    return score;
  }

  // =========================
  // Load cities JSON
  // =========================

  void _ingestCityListIntoCache(
    List<dynamic> list,
    Map<String, dynamic> into,
  ) {
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final en = (m['city_en'] ?? '').toString().trim();
      final ar = (m['city_ar'] ?? '').toString().trim();
      final key = en.isNotEmpty ? en : ar;
      if (key.isEmpty) continue;
      into[key] = <String, dynamic>{
        'ar': ar,
        'en': en,
      };
    }
  }

  Future<Map<String, dynamic>> _loadCities() async {
    if (_citiesCache != null) return _citiesCache!;

    _citiesCache = <String, dynamic>{};

    Future<void> loadPath(String path) async {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final raw = json.decode(jsonStr);
        if (raw is Map<String, dynamic>) {
          _citiesCache!.addAll(raw);
          return;
        }
        if (raw is List<dynamic>) {
          _ingestCityListIntoCache(raw, _citiesCache!);
        }
      } catch (_) {}
    }

    await loadPath('assets/data/saudi_locations.json');
    await loadPath('assets/data/saudi_locations_extra.json');

    return _citiesCache!;
  }

  Future<List<String>> loadCityKeys() async {
    final data = await _loadCities();
    return data.keys.map((e) => e.toString()).toList();
  }

  String _cityLabelFromJson(String key) {
    final data = _citiesCache;
    if (data == null) return key;

    final row = data[key];
    if (row == null) return key;

    if (row is Map) {
      final ar = row['ar']?.toString().trim();
      final en = row['en']?.toString().trim();
      final name = row['name']?.toString().trim();

      if (widget.isAr) {
        return (ar != null && ar.isNotEmpty)
            ? ar
            : (name != null && name.isNotEmpty)
                ? name
                : key;
      }

      return (en != null && en.isNotEmpty)
          ? en
          : (name != null && name.isNotEmpty)
              ? name
              : key;
    }

    return row.toString();
  }

  bool _matchesCityFilter(Property p, String cityFilterRaw) {
    final cityFilter = _norm(cityFilterRaw);
    if (cityFilter.isEmpty || cityFilter == 'all') return true;

    final city = _norm(p.city);
    final location = _norm(p.location);
    final address = _norm(p.addressLine);
    final locationText = _norm(p.locationText);

    String region = '';
    try {
      region = _norm((p as dynamic).region?.toString());
    } catch (_) {}

    final candidates = <String>{
      cityFilter,
      _norm(_cityLabel(cityFilterRaw)),
      _norm(_cityLabelFromJson(cityFilterRaw)),
    }..removeWhere((e) => e.isEmpty);

    final data = _citiesCache;
    if (data != null) {
      final key = cityFilterRaw.trim();
      final row = data[key];
      if (row is Map) {
        for (final k in const ['ar', 'en', 'name']) {
          final s = row[k]?.toString().trim();
          if (s != null && s.isNotEmpty) candidates.add(_norm(s));
        }
      }
    }

    final haystack = <String>[
      city,
      location,
      address,
      locationText,
      region,
    ].where((e) => e.isNotEmpty).join(' | ');

    if (haystack.isEmpty) return false;

    bool matchPair(String a, String b) {
      if (a.isEmpty || b.isEmpty) return false;
      return a.contains(b) || b.contains(a);
    }

    for (final c in candidates) {
      if (haystack.contains(c)) return true;
    }
    for (final c in candidates) {
      if (matchPair(city, c)) return true;
    }
    for (final h in [city, location, address, locationText, region]) {
      if (h.isEmpty) continue;
      for (final c in candidates) {
        if (matchPair(h, c)) return true;
      }
    }

    return false;
  }

  bool _matchesSearch(Property p, String queryRaw) {
    final q = _norm(queryRaw);
    if (q.isEmpty) return true;
    return _searchScore(p, q) > 0;
  }

  bool _matchesCityFilterForRequest(
    MarketPropertyRequestRow r,
    String cityFilterRaw,
  ) {
    final cityFilter = _norm(cityFilterRaw);
    if (cityFilter.isEmpty || cityFilter == 'all') return true;

    final city = _norm(r.city);
    final label1 = _norm(_cityLabel(cityFilterRaw));
    final label2 = _norm(_cityLabelFromJson(cityFilterRaw));

    final candidates = <String>{
      cityFilter,
      label1,
      label2,
    }.where((e) => e.isNotEmpty).toList();

    if (city.isEmpty) return false;
    for (final c in candidates) {
      if (city.contains(c) || c.contains(city)) return true;
    }
    return false;
  }

  int _searchScoreForRequest(MarketPropertyRequestRow r, String queryRaw) {
    final q = _norm(queryRaw);
    if (q.isEmpty) return 1;
    final tokens = _tokens(q);
    if (tokens.isEmpty) return 0;
    final typeAr = switch (_norm(r.propertyType)) {
      'villa' => 'فيلا',
      'apartment' => 'شقه شقة',
      'land' => 'ارض أرض',
      _ => '',
    };
    final purposeAr = switch (_norm(r.purpose)) {
      'rent' ||
      'daily rent' ||
      'monthly rent' ||
      'yearly rent' =>
        'ايجار للايجار',
      'auction' => 'مزاد',
      'investment' => 'استثمار',
      _ => 'شراء بيع للبيع',
    };
    final hay = _norm(
      '${r.id} ${r.requesterId} '
      '${r.title} ${r.description ?? ''} ${r.city} ${r.districts.join(' ')} '
      '${r.requesterPublicName ?? ''} '
      '${r.propertyType} $typeAr ${r.purpose} $purposeAr ${r.status} '
      '${r.budgetMin?.toStringAsFixed(0) ?? ''} '
      '${r.budgetMax?.toStringAsFixed(0) ?? ''} '
      '${r.areaMinM2?.toStringAsFixed(0) ?? ''} '
      '${_flattenSearchValue(r.details)} '
      '${r.requestPriority.wireValue} '
      'مرن عادي اولوية مستعجل فوري flexible standard priority urgent immediate',
    );
    if (hay.isEmpty) return 0;
    if (hay.contains(q)) return 100;
    if (_containsAllTokens(hay, tokens)) return 70;
    return 0;
  }

  bool _matchesSearchForRequest(MarketPropertyRequestRow r, String queryRaw) {
    return _searchScoreForRequest(r, queryRaw) > 0;
  }

  bool _requestMatchesTypeFilter(MarketPropertyRequestRow r) {
    if (_typeFilter == null) return true;
    final code = switch (_typeFilter!) {
      PropertyType.villa => 'villa',
      PropertyType.apartment => 'apartment',
      PropertyType.land => 'land',
    };
    return _norm(r.propertyType) == _norm(code);
  }

  bool _requestMatchesPurposeFilter(MarketPropertyRequestRow r) {
    final f = _purposeFilter;
    if (f == null) return true;
    final p = r.purpose.toLowerCase().trim();
    const rentPurposes = {
      'rent',
      'daily_rent',
      'monthly_rent',
      'yearly_rent',
    };

    if (f == 'rent') {
      return rentPurposes.contains(p);
    }

    if (f == 'sale') {
      if (rentPurposes.contains(p)) return false;
      // الخادم يستخدم purchase لطلب شراء؛ قديم أو فارغ يُعامل كشراء عند فلتر «للبيع».
      return p.isEmpty || p == 'purchase' || p == 'sale' || p == 'buy';
    }
    if (f == 'auction') {
      if (rentPurposes.contains(p)) return false;
      return p == 'auction' || p == 'purchase' || p == 'sale' || p == 'buy';
    }
    if (f == 'investment') {
      if (rentPurposes.contains(p)) return false;
      return p == 'investment' || p == 'purchase' || p == 'sale' || p == 'buy';
    }
    return true;
  }

  /// طلبات السوق في الرئيسية — نفس فلاتر البحث/المدينة/النوع/الغرض قدر الإمكان.
  List<MarketPropertyRequestRow> filterMarketRequests(
    List<MarketPropertyRequestRow> src,
  ) {
    final q = _searchQuery.trim();
    final cityFilter = _cityFilter.trim();

    final filtered = src.where((r) {
      if (!ListingPermissionsHelper.shouldShowMarketRequestInPublicHome(
        r.status,
      )) {
        return false;
      }
      if (!_isGuest &&
          _uid.isNotEmpty &&
          _marketRequestIdsWithMyPendingOffer.contains(r.id)) {
        return false;
      }
      if (!_matchesCityFilterForRequest(r, cityFilter)) return false;
      if (!_matchesSearchForRequest(r, q)) return false;
      if (!_requestMatchesTypeFilter(r)) return false;
      if (!_requestMatchesPurposeFilter(r)) return false;
      if (!_matchesRequestPriceRange(r)) return false;
      if (!_matchesNumberRange(r.areaMinM2, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      return true;
    }).toList();

    int cmpDate(MarketPropertyRequestRow a, MarketPropertyRequestRow b) {
      return b.sortTime.compareTo(a.sortTime);
    }

    filtered.sort(cmpDate);
    if (filtered.isNotEmpty || cityFilter.isEmpty || cityFilter == 'all') {
      return filtered;
    }

    // Fallback silently in background: widen scope when city bucket is empty.
    final expanded = src.where((r) {
      if (!ListingPermissionsHelper.shouldShowMarketRequestInPublicHome(
        r.status,
      )) {
        return false;
      }
      if (!_isGuest &&
          _uid.isNotEmpty &&
          _marketRequestIdsWithMyPendingOffer.contains(r.id)) {
        return false;
      }
      if (!_matchesSearchForRequest(r, q)) return false;
      if (!_requestMatchesTypeFilter(r)) return false;
      if (!_requestMatchesPurposeFilter(r)) return false;
      if (!_matchesRequestPriceRange(r)) return false;
      if (!_matchesNumberRange(r.areaMinM2, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      return true;
    }).toList();
    expanded.sort(cmpDate);
    return expanded;
  }

  /// خليط زمني: الأحدث أولاً (إعلانات + طلبات) عند تبويب «الكل» وترتيب «الأحدث».
  List<HomeMixedFeedEntry> buildMixedHomeTimeline(
    List<Property> listings,
    List<MarketPropertyRequestRow> requests, {
    int limit = 200,
  }) {
    final out = <HomeMixedFeedEntry>[
      ...listings.map(HomeMixedFeedEntry.listing),
      ...requests.map(HomeMixedFeedEntry.request),
    ];
    out.sort((a, b) => b.sortAt.compareTo(a.sortAt));
    if (out.length > limit) return out.sublist(0, limit);
    return out;
  }

  // =========================
  // Filtering + sorting
  // =========================

  bool _matchesFurnishedFilter(Property p) {
    final f = _furnishedFilter;
    if (f == null) return true;
    if (f == true) return p.furnished == true;
    return p.furnished != true;
  }

  bool _matchesNumberRange(num? value, double? min, double? max) {
    if (min == null && max == null) return true;
    final v = value?.toDouble();
    if (v == null || v <= 0) return false;
    if (min != null && v < min) return false;
    if (max != null && v > max) return false;
    return true;
  }

  bool _matchesRequestPriceRange(MarketPropertyRequestRow r) {
    if (_priceMinFilter == null && _priceMaxFilter == null) return true;
    final min = r.budgetMin;
    final max = r.budgetMax;
    if (min == null && max == null) return false;
    if (_priceMinFilter != null && max != null && max < _priceMinFilter!) {
      return false;
    }
    if (_priceMaxFilter != null && min != null && min > _priceMaxFilter!) {
      return false;
    }
    return true;
  }

  List<Property> filterListDashboard(
    List<Property> src, {
    bool excludePropertiesInCart = false,

    /// عند true (تبويب الرئيسية): إعلانات العقار المنشورة/العامة فقط؛ المسار الكامل في «صفحتي».
    bool homeDiscoveryListingCardsOnly = false,
  }) {
    final q = _searchQuery.trim();
    final cityFilter = _cityFilter.trim();

    final cartPropIds = excludePropertiesInCart
        ? _cart
            .map((r) => (r['property_id'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
        : null;

    final filtered = src.where((p) {
      if (cartPropIds != null && cartPropIds.contains(p.id)) return false;
      if (!_matchesCityFilter(p, cityFilter)) return false;
      if (!_matchesSearch(p, q)) return false;
      if (_typeFilter != null && p.type != _typeFilter) return false;
      if (!PropertyListingDisplay.matchesPurposeFilter(p, _purposeFilter)) {
        return false;
      }
      if (!_matchesFurnishedFilter(p)) return false;
      if (!_matchesNumberRange(p.price, _priceMinFilter, _priceMaxFilter)) {
        return false;
      }
      if (!_matchesNumberRange(p.area, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      if (!ListingPermissionsHelper.shouldShowInPublicHome(p)) return false;
      if (homeDiscoveryListingCardsOnly &&
          !ListingPermissionsHelper.shouldShowOnHomeDiscoveryCard(p)) {
        return false;
      }
      return true;
    }).toList();

    _applyLocalSorting(filtered, queryRaw: q);
    if (filtered.isNotEmpty || cityFilter.isEmpty || cityFilter == 'all') {
      return filtered;
    }

    // Fallback silently in background: show nearest matches when selected city has no data.
    final expanded = src.where((p) {
      if (cartPropIds != null && cartPropIds.contains(p.id)) return false;
      if (!_matchesSearch(p, q)) return false;
      if (_typeFilter != null && p.type != _typeFilter) return false;
      if (!PropertyListingDisplay.matchesPurposeFilter(p, _purposeFilter)) {
        return false;
      }
      if (!_matchesFurnishedFilter(p)) return false;
      if (!_matchesNumberRange(p.price, _priceMinFilter, _priceMaxFilter)) {
        return false;
      }
      if (!_matchesNumberRange(p.area, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      if (!ListingPermissionsHelper.shouldShowInPublicHome(p)) return false;
      if (homeDiscoveryListingCardsOnly &&
          !ListingPermissionsHelper.shouldShowOnHomeDiscoveryCard(p)) {
        return false;
      }
      return true;
    }).toList();

    expanded.sort((a, b) {
      final da = _distanceFor(a);
      final db = _distanceFor(b);

      final aInf = !da.isFinite;
      final bInf = !db.isFinite;
      if (aInf && bInf) return b.createdAt.compareTo(a.createdAt);
      if (aInf) return 1;
      if (bInf) return -1;

      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      return b.createdAt.compareTo(a.createdAt);
    });
    return expanded;
  }

  /// فلتر «المخفية» المحلي: إما إظهار المخفية فقط أو إخفاؤها من الرئيسية.
  ///
  /// الضيف لا يضيف لقائمة الإخفاء من الواجهة، لكن المفتاح في [SharedPreferences] عام
  /// (`user_hidden_property_ids_v1`) فيرث نفس الجهاز قيماً من جلسة مسجّل سابقاً — نتجاهلها للضيف.
  List<Property> _applyHiddenFeedFilterToProperties(List<Property> list) {
    bool completedDeal(Property p) {
      final s = (p.status ?? '').trim().toLowerCase();
      final rs = (p.reservationStatus ?? '').trim().toLowerCase();
      return s == 'sold' ||
          s == 'closed' ||
          s == 'completed' ||
          rs == 'sold' ||
          rs == 'closed' ||
          rs == 'completed';
    }

    final activeList = list.where((p) => !completedDeal(p)).toList();
    if (_isGuest) {
      if (_homeShowHiddenOnly) return const [];
      return activeList;
    }
    if (_homeShowHiddenOnly) {
      return activeList
          .where((p) => _hiddenPropertyIds.contains(p.id))
          .toList();
    }
    return activeList.where((p) => !_hiddenPropertyIds.contains(p.id)).toList();
  }

  List<MarketPropertyRequestRow> _applyHiddenFeedFilterToRequests(
    List<MarketPropertyRequestRow> list,
  ) {
    if (_isGuest) {
      if (_homeShowHiddenOnly) return const [];
      return list;
    }
    if (_homeShowHiddenOnly) {
      return list.where((r) => _hiddenMarketRequestIds.contains(r.id)).toList();
    }
    return list.where((r) => !_hiddenMarketRequestIds.contains(r.id)).toList();
  }

  /// مصدر إعلانات الرئيسية: [_all] من استعلام الرئيسية (PostgREST + فلتر الحالات)،
  /// وللمستخدم المسجّل نُلحق من [\_mine] ما يحقق الظهور العام ولم يُرجَع في [_all]
  /// (مثلاً اختلاف حالة/حرف كبير/تأخر جلب الرئيسية عن «صفحتي»).
  List<Property> _mergedHomePropertyPool() {
    final uid = _uid.trim();
    final out = _isGuest || uid.isEmpty
        ? List<Property>.from(_all)
        : _all.where((p) => p.ownerId != uid).toList();
    if (_isGuest) return out;
    final seen = out.map((p) => p.id).where((id) => id.isNotEmpty).toSet();
    for (final p in _mine) {
      if (p.id.isEmpty || seen.contains(p.id)) continue;
      if (uid.isNotEmpty && p.ownerId == uid) continue;
      if (!ListingPermissionsHelper.shouldShowInPublicHome(p)) continue;
      seen.add(p.id);
      out.add(p);
    }
    return out;
  }

  /// أعداد تشخيصية للرئيسية: [server] بعد دمج [\_mine] الظاهر عالمياً، [filtered] بعد فلاتر الواجهة، [shown] بعد إخفاء الرئيسية.
  ({int server, int filtered, int shown}) _homePropertyFeedPipelineCounts() {
    final pool = _mergedHomePropertyPool();
    final filteredList = filterListDashboard(
      pool,
      excludePropertiesInCart: false,
      homeDiscoveryListingCardsOnly: true,
    );
    final shownList = _applyHiddenFeedFilterToProperties(filteredList);
    return (
      server: pool.length,
      filtered: filteredList.length,
      shown: shownList.length,
    );
  }

  ({int server, int filtered, int shown}) _homeRequestFeedPipelineCounts() {
    final uid = _uid.trim();
    final publicRequests = _isGuest || uid.isEmpty
        ? _marketHomeRequests
        : _marketHomeRequests.where((r) => r.requesterId != uid).toList();
    final filteredList = filterMarketRequests(publicRequests);
    final shownList = _applyHiddenFeedFilterToRequests(filteredList);
    return (
      server: publicRequests.length,
      filtered: filteredList.length,
      shown: shownList.length,
    );
  }

  /// ترتيب إعلاناتي في تبويب «صفحتي» حسب [_sortBy] + نفس البحث/فلاتر الواجهة العلوية.
  List<Property> sortedMineForHub() {
    final q = _searchQuery.trim();
    final cityFilter = _cityFilter.trim();

    final list = _mine.where((p) {
      if (!_matchesCityFilter(p, cityFilter)) return false;
      if (!_matchesSearch(p, q)) return false;
      if (_typeFilter != null && p.type != _typeFilter) return false;
      if (!PropertyListingDisplay.matchesPurposeFilter(p, _purposeFilter)) {
        return false;
      }
      if (!_matchesFurnishedFilter(p)) return false;
      if (!_matchesNumberRange(p.price, _priceMinFilter, _priceMaxFilter)) {
        return false;
      }
      if (!_matchesNumberRange(p.area, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      return true;
    }).toList();

    _applyLocalSorting(list, queryRaw: q);
    return list;
  }

  // =========================
  // Sorting
  // =========================

  void _applyLocalSorting(
    List<Property> list, {
    String queryRaw = '',
  }) {
    final sort = _sortBy.toString();
    final hasQuery = _norm(queryRaw).isNotEmpty;

    int compareLatest(Property a, Property b) {
      return b.createdAt.compareTo(a.createdAt);
    }

    int compareNearest(Property a, Property b) {
      final da = _distanceFor(a);
      final db = _distanceFor(b);

      final aInf = !da.isFinite;
      final bInf = !db.isFinite;

      if (aInf && bInf) return compareLatest(a, b);
      if (aInf) return 1;
      if (bInf) return -1;

      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;

      return compareLatest(a, b);
    }

    int compareSearchThenLatest(Property a, Property b) {
      final sa = _searchScore(a, queryRaw);
      final sb = _searchScore(b, queryRaw);

      final cmpScore = sb.compareTo(sa);
      if (cmpScore != 0) return cmpScore;

      return compareLatest(a, b);
    }

    if (sort == 'price_low') {
      list.sort((a, b) {
        final cmp = a.price.compareTo(b.price);
        if (cmp != 0) return cmp;

        if (hasQuery) {
          final sCmp = compareSearchThenLatest(a, b);
          if (sCmp != 0) return sCmp;
        }

        return compareLatest(a, b);
      });
      return;
    }

    if (sort == 'price_high') {
      list.sort((a, b) {
        final cmp = b.price.compareTo(a.price);
        if (cmp != 0) return cmp;

        if (hasQuery) {
          final sCmp = compareSearchThenLatest(a, b);
          if (sCmp != 0) return sCmp;
        }

        return compareLatest(a, b);
      });
      return;
    }

    if (sort == 'area_high') {
      list.sort((a, b) {
        final cmp = b.area.compareTo(a.area);
        if (cmp != 0) return cmp;

        if (hasQuery) {
          final sCmp = compareSearchThenLatest(a, b);
          if (sCmp != 0) return sCmp;
        }

        return compareLatest(a, b);
      });
      return;
    }

    if (sort == 'nearest') {
      list.sort((a, b) {
        if (hasQuery) {
          final sa = _searchScore(a, queryRaw);
          final sb = _searchScore(b, queryRaw);
          final cmpScore = sb.compareTo(sa);
          if (cmpScore != 0) return cmpScore;
        }
        return compareNearest(a, b);
      });
      return;
    }

    if (sort == 'most_viewed') {
      list.sort((a, b) {
        final cv = b.views.compareTo(a.views);
        if (cv != 0) return cv;
        return compareLatest(a, b);
      });
      return;
    }

    if (hasQuery) {
      list.sort(compareSearchThenLatest);
      return;
    }

    list.sort(compareLatest);
  }

  // =========================
  // Cities dropdown options
  // =========================

  List<String> get _cityOptions {
    final data = _citiesCache;

    if (data == null || data.isEmpty) {
      return const [''];
    }

    final keys = data.keys.map((e) => e.toString()).toList()
      ..sort((a, b) => _cityLabel(a).compareTo(_cityLabel(b)));

    return ['', ...keys];
  }

  String _cityLabel(String v) {
    if (v.isEmpty || v == 'all') {
      return widget.isAr ? 'الكل' : 'All';
    }

    return _cityLabelFromJson(v);
  }

  // =========================
  // Nearby chip text
  // =========================

  String get _nearbyChipText {
    if (_sortBy == 'nearest') {
      if (_cityFilter == 'all' || _cityFilter.isEmpty) {
        return widget.isAr ? 'الترتيب: الأقرب' : 'Sort: Nearest';
      }

      final name = _cityLabel(_cityFilter);
      return widget.isAr ? 'الأقرب داخل: $name' : 'Nearest in: $name';
    }

    if (_cityFilter == 'all' || _cityFilter.isEmpty) {
      return widget.isAr ? 'كل المدن' : 'All cities';
    }

    final name = _cityLabel(_cityFilter);
    return widget.isAr ? 'المدينة: $name' : 'City: $name';
  }
}
