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

  static bool _citiesExtraLoaded = false;

  /// ملف `saudi_locations_extra.json` ≈900KB — تحميله + `json.decode` على الويب
  /// يجمّد المتصفح بعد الدخول (يظهر «قيد التحميل» في Network).
  Future<Map<String, dynamic>> _loadCities({bool includeExtra = true}) async {
    if (_citiesCache != null) {
      if (!includeExtra || _citiesExtraLoaded) {
        return _citiesCache!;
      }
      if (kIsWeb) {
        return _citiesCache!;
      }
    }

    _citiesCache ??= <String, dynamic>{};

    Future<void> loadPath(String path) async {
      try {
        final jsonStr = await rootBundle.loadString(path);
        // compute يعمل على isolate في الجوال؛ على الويب يبقى على نفس الـ event loop
        // لذلك نؤجّل الملف الكبير عبر [_ensureCitiesExtraLoaded] فقط عند الحاجة.
        WebBootstrapDiag.log('cities.decode', 'start $path');
        final dynamic raw = await compute(decodeDashboardJsonString, jsonStr);
        WebBootstrapDiag.log('cities.decode', 'done $path');
        if (raw is Map<String, dynamic>) {
          _citiesCache!.addAll(raw);
          return;
        }
        if (raw is List<dynamic>) {
          _ingestCityListIntoCache(raw, _citiesCache!);
        }
      } catch (e) {
        WebBootstrapDiag.warn('cities.decode', '$path — $e');
      }
    }

    if (_citiesCache!.isEmpty) {
      await loadPath('assets/data/saudi_locations.json');
    }
    if (includeExtra && !_citiesExtraLoaded) {
      await _ensureCitiesExtraLoaded();
    }
    return _citiesCache!;
  }

  /// الملف الكبير (~900KB) عند الحاجة فقط (فلاتر متقدمة) — لا عند أول دخول.
  Future<void> _ensureCitiesExtraLoaded() async {
    if (_citiesExtraLoaded) return;
    _citiesCache ??= <String, dynamic>{};
    if (_citiesCache!.isEmpty) {
      await _loadCities(includeExtra: false);
    }
    try {
      final jsonStr =
          await rootBundle.loadString('assets/data/saudi_locations_extra.json');
      await _webYieldUi();
      WebBootstrapDiag.log('cities.decode', 'start extra');
      final raw = await compute(decodeDashboardJsonString, jsonStr);
      WebBootstrapDiag.log('cities.decode', 'done extra');
      if (raw is Map<String, dynamic>) {
        _citiesCache!.addAll(raw);
      } else if (raw is List<dynamic>) {
        _ingestCityListIntoCache(raw, _citiesCache!);
      }
      _citiesExtraLoaded = true;
    } catch (e) {
      WebBootstrapDiag.warn('cities.decode', 'extra — $e');
    }
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

  /// مطابقة هرمية: المنطقة/المحافظة/الحي (إن طُلب) — تعمل على نص العنوان
  /// والمدينة وأي حقل موقع مرتبط في `Property`. تُستدعى بعد _matchesCityFilter.
  bool _matchesHierarchyFilters(Property p) {
    final region = _norm(_regionFilter);
    final gov = _norm(_governorateFilter);
    final district = _norm(_districtFilter);
    if (region.isEmpty && gov.isEmpty && district.isEmpty) return true;

    String pRegion = '';
    String pGov = '';
    try {
      pRegion = _norm((p as dynamic).region?.toString());
    } catch (_) {}
    try {
      pGov = _norm((p as dynamic).governorate?.toString());
    } catch (_) {}

    final haystack = <String>[
      _norm(p.city),
      _norm(p.location),
      _norm(p.addressLine),
      _norm(p.locationText),
      pRegion,
      pGov,
    ].where((e) => e.isNotEmpty).join(' | ');

    bool matchOne(String needle) {
      if (needle.isEmpty) return true;
      if (haystack.contains(needle)) return true;
      // مطابقة جزئية على المقاطع (مثلاً "ال" + "رياض").
      for (final part in needle.split(' ')) {
        if (part.length >= 3 && haystack.contains(part)) return true;
      }
      return false;
    }

    if (!matchOne(region)) return false;
    if (!matchOne(gov)) return false;
    if (!matchOne(district)) return false;
    return true;
  }

  bool _matchesHierarchyFiltersForRequest(MarketPropertyRequestRow r) {
    final region = _norm(_regionFilter);
    final gov = _norm(_governorateFilter);
    final district = _norm(_districtFilter);
    if (region.isEmpty && gov.isEmpty && district.isEmpty) return true;

    String dyn(String key) {
      try {
        final v = (r as dynamic).toJson?.call();
        if (v is Map) {
          final s = v[key]?.toString();
          if (s != null) return _norm(s);
        }
      } catch (_) {}
      return '';
    }

    final haystack = <String>[
      _norm(r.city),
      dyn('region'),
      dyn('governorate'),
      dyn('district'),
      dyn('location_text'),
      dyn('address_line'),
    ].where((e) => e.isNotEmpty).join(' | ');

    bool matchOne(String needle) {
      if (needle.isEmpty) return true;
      if (haystack.contains(needle)) return true;
      for (final part in needle.split(' ')) {
        if (part.length >= 3 && haystack.contains(part)) return true;
      }
      return false;
    }

    if (!matchOne(region)) return false;
    if (!matchOne(gov)) return false;
    if (!matchOne(district)) return false;
    return true;
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
      return p == 'auction';
    }
    if (f == 'investment') {
      if (rentPurposes.contains(p)) return false;
      return p == 'investment';
    }
    return true;
  }

  /// طلبات السوق في الرئيسية — نفس فلاتر البحث/المدينة/النوع/الغرض قدر الإمكان.
  List<MarketPropertyRequestRow> filterMarketRequests(
    List<MarketPropertyRequestRow> src, {
    /// «طلباتي»: لا تُخفِ الطلبات بعد صفقة/اختيار عرض — هي طلبات المستخدم نفسه.
    bool forMySubmissions = false,
  }) {
    final q = _searchQuery.trim();
    final cityFilter = _cityFilter.trim();

    final filtered = src.where((r) {
      if (!forMySubmissions &&
          !ListingPermissionsHelper.shouldShowMarketRequestWithoutDeal(r)) {
        return false;
      }
      if (!forMySubmissions &&
          !_isGuest &&
          _uid.isNotEmpty &&
          _marketRequestIdsWithMyPendingOffer.contains(r.id)) {
        return false;
      }
      // الطلبات التي سحب المستخدم عرضه عليها مرتين تختفي نهائياً.
      if (!_isGuest &&
          _uid.isNotEmpty &&
          _marketRequestIdsHiddenAfterTwoWithdrawals.contains(r.id)) {
        return false;
      }
      if (!_matchesCityFilterForRequest(r, cityFilter)) return false;
      if (!_matchesHierarchyFiltersForRequest(r)) return false;
      if (!_matchesSearchForRequest(r, q)) return false;
      if (!_requestMatchesTypeFilter(r)) return false;
      if (!_requestMatchesPurposeFilter(r)) return false;
      if (!_matchesRequestPriceRange(r)) return false;
      if (!_matchesNumberRange(r.areaMinM2, _areaMinFilter, _areaMaxFilter)) {
        return false;
      }
      if (_paidPriorityOnlyFilter &&
          !InstantMarketRequestFeed.isPaidPriorityPin(r)) {
        return false;
      }
      return true;
    }).toList();

    int cmpDate(MarketPropertyRequestRow a, MarketPropertyRequestRow b) {
      return InstantMarketRequestFeed.compare(
        a,
        b,
        viewerRegion: _regionFilter.trim().isNotEmpty
            ? _regionFilter.trim()
            : _cityFilter.trim(),
        viewerLat: _myLat,
        viewerLng: _myLng,
      );
    }

    filtered.sort(cmpDate);
    return filtered;
  }

  /// خليط زمني: الأحدث أولاً (إعلانات + طلبات) عند تبويب «الكل» وترتيب «الأحدث».
  List<HomeMixedFeedEntry> buildMixedHomeTimeline(
    List<Property> listings,
    List<MarketPropertyRequestRow> requests, {
    int? limit,
    String? viewerRegion,
    bool pinPaidRequests = true,
  }) {
    final effectiveLimit = limit ??
        (kIsWeb ? 40 : 120);
    final region = (viewerRegion ?? _regionFilter).trim();
    final viewer = region.isNotEmpty ? region : _cityFilter.trim();
    final out = <HomeMixedFeedEntry>[
      ...listings.map(HomeMixedFeedEntry.listing),
      ...requests.map(
        (r) => HomeMixedFeedEntry.request(r, viewerRegion: viewer),
      ),
    ];
    // المستعجل/الفوري المدفوع أولاً في الرئيسية فقط (pinPaidRequests).
    out.sort((a, b) {
      if (pinPaidRequests) {
        final aPaid = a.request != null &&
            InstantMarketRequestFeed.isPaidPriorityPin(a.request!);
        final bPaid = b.request != null &&
            InstantMarketRequestFeed.isPaidPriorityPin(b.request!);
        if (aPaid != bPaid) return aPaid ? -1 : 1;
        if (aPaid && bPaid) {
          return InstantMarketRequestFeed.compare(
            a.request!,
            b.request!,
            viewerRegion: viewer,
          );
        }
      }
      return b.sortAt.compareTo(a.sortAt);
    });
    if (out.length > effectiveLimit) {
      return out.sublist(0, effectiveLimit);
    }
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

    /// تبويب «طلباتي/إعلاناتي»: لا تطبّق فلتر الظهور العام — أظهر كل ما يخصّ المستخدم.
    bool includeMyPipelineListings = false,
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
      if (!_matchesHierarchyFilters(p)) return false;
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
      if (!includeMyPipelineListings &&
          !ListingPermissionsHelper.shouldShowInPublicHome(p)) {
        return false;
      }
      if (homeDiscoveryListingCardsOnly &&
          !ListingPermissionsHelper.shouldShowOnHomeDiscoveryCard(p)) {
        return false;
      }
      return true;
    }).toList();

    _applyLocalSorting(filtered, queryRaw: q);
    return filtered;
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
    bool completedRequest(MarketPropertyRequestRow r) {
      final st = r.status.trim().toLowerCase();
      if (r.completedAt != null) return true;
      return st == 'completed' ||
          st == 'closed' ||
          st == 'sold' ||
          st == 'cancelled' ||
          st == 'canceled';
    }

    final active = list.where((r) => !completedRequest(r)).toList();
    if (_isGuest) {
      if (_homeShowHiddenOnly) return const [];
      return active;
    }
    if (_homeShowHiddenOnly) {
      return active.where((r) => _hiddenMarketRequestIds.contains(r.id)).toList();
    }
    return active.where((r) => !_hiddenMarketRequestIds.contains(r.id)).toList();
  }

  /// مصدر إعلانات الرئيسية: [_all] من استعلام الرئيسية (PostgREST + فلتر الحالات)،
  /// وللمستخدم المسجّل نُلحق من [\_mine] ما يحقق الظهور العام ولم يُرجَع في [_all]
  /// (مثلاً اختلاف حالة/حرف كبير/تأخر جلب الرئيسية عن «صفحتي»).
  ///
  /// قاعدة الملكية الموحَّدة لرؤية «صفحتي ≠ الرئيسية»:
  /// - إعلانات المستخدم المعلن (`ownerId == uid`) لا تظهر له في الرئيسية —
  ///   تظهر في تبويب «إعلاناتي/طلباتي» المجاور.
  /// - إعلانات المسوّق الذي نشرها أو اختير لها (`publishedByMarketerId` /
  ///   `selectedMarketerId`) كذلك لا تظهر له في الرئيسية.
  List<Property> _mergedHomePropertyPool() {
    final uid = _uid.trim();
    bool ownedByCurrentUser(Property p) {
      if (uid.isEmpty) return false;
      if (p.ownerId == uid) return true;
      final pubBy = (p.publishedByMarketerId ?? '').trim();
      if (pubBy.isNotEmpty && pubBy == uid) return true;
      final selected = (p.selectedMarketerId ?? '').trim();
      if (selected.isNotEmpty && selected == uid) return true;
      return false;
    }

    if (_isGuest || uid.isEmpty) {
      return List<Property>.from(_all);
    }

    // لا نُظهر إعلاناتك/منشوراتك في الرئيسية حتى لو كان الكتالوج كله ملكك —
    // مكانها «طلباتي/إعلاناتي».
    final out = _all.where((p) => !ownedByCurrentUser(p)).toList();

    final seen = out.map((p) => p.id).where((id) => id.isNotEmpty).toSet();
    for (final p in _mine) {
      if (p.id.isEmpty || seen.contains(p.id)) continue;
      if (ownedByCurrentUser(p)) continue;
      if (!ListingPermissionsHelper.shouldShowInPublicHome(p)) continue;
      seen.add(p.id);
      out.add(p);
    }
    return out;
  }

  /// إعلانات «يخصّني»: إعلانات أملكها كمعلن فرد + إعلانات نشرتُها كمسوّق نيابة
  /// عن مالك. تُجمَع من [_mine] (المستعلَمة بـ `owner_id = uid`) و[_all]
  /// (تجمّع الرئيسية الذي يحوي الإعلانات المنشورة علناً) دون تكرار.
  List<Property> _propertiesOwnedOrPublishedByMe() {
    final uid = _uid.trim();
    if (uid.isEmpty) return const <Property>[];
    final out = <String, Property>{};
    for (final p in _mine) {
      if (p.id.isEmpty) continue;
      final pubBy = (p.publishedByMarketerId ?? '').trim();
      final selected = (p.selectedMarketerId ?? '').trim();
      final isOwnerOfRow = p.ownerId == uid;
      final isMarketerOfRow = (pubBy.isNotEmpty && pubBy == uid) ||
          (selected.isNotEmpty && selected == uid);
      if (!isOwnerOfRow && !isMarketerOfRow) continue;
      out[p.id] = p;
    }
    for (final p in _all) {
      if (p.id.isEmpty || out.containsKey(p.id)) continue;
      final pubBy = (p.publishedByMarketerId ?? '').trim();
      final selected = (p.selectedMarketerId ?? '').trim();
      final isOwnerOfRow = p.ownerId == uid;
      final isMarketerOfRow = (pubBy.isNotEmpty && pubBy == uid) ||
          (selected.isNotEmpty && selected == uid);
      if (!isOwnerOfRow && !isMarketerOfRow) continue;
      out[p.id] = p;
    }
    return out.values.toList(growable: false);
  }

  int _nestedDashboardFeedCacheKey() {
    final uid = _uid.trim();
    // لا تُدرج [_tabIndex] — تبديل التبويب كان يُبطل الكاش ويعيد فلترة كل القوائم
    // على خيط الواجهة فيتجمّد التطبيق عند أي ضغط على شريط التنقل.
    return Object.hash(
      Object.hash(
        _homeFeedDataEpoch,
        uid,
        _isGuest,
        _searchQuery,
        _cityFilter,
        _regionFilter,
        _governorateFilter,
        _districtFilter,
        _sortBy,
        _typeFilter,
        _purposeFilter,
        _furnishedFilter,
        _priceMinFilter,
        _priceMaxFilter,
        _areaMinFilter,
        _areaMaxFilter,
        // لا تُدرج [_homeFeedKind] — تبديل الكل/إعلانات/طلبات يجب ألا يعيد الفلترة.
        _homeShowHiddenOnly,
      ),
      Object.hash(
        _myLat,
        _myLng,
        _all.length,
        _mine.length,
        _marketHomeRequests.length,
        _cart.length,
        _myPendingMarketOffersForCart.length,
        _marketRequestIdsWithMyPendingOffer.length,
        _hiddenPropertyIds.length,
        _hiddenMarketRequestIds.length,
      ),
    );
  }

  /// مايو: إعادة بناء كاش العرض متزامناً — بدون await/_webYieldUi.
  void _rebuildNestedDashboardFeedCacheSync() {
    final key = _nestedDashboardFeedCacheKey();
    if (_nestedDashboardFeedCacheBuiltKey == key) return;

    final uid = _uid.trim();
    final homePropertyPool = _mergedHomePropertyPool();
    _nestedDashboardHomePropertyPoolSize = homePropertyPool.length;

    final filteredList = filterListDashboard(
      homePropertyPool,
      excludePropertiesInCart: !_isGuest && uid.isNotEmpty,
      homeDiscoveryListingCardsOnly: true,
    );
    _nestedDashboardHomeItems = _applyHiddenFeedFilterToProperties(
      filteredList,
    );
    _nestedDashboardPipelineL = (
      server: homePropertyPool.length,
      filtered: filteredList.length,
      shown: _nestedDashboardHomeItems.length,
    );

    final publicRequests = _isGuest || uid.isEmpty
        ? _marketHomeRequests
        : _marketHomeRequests.where((r) => r.requesterId != uid).toList();
    final filteredRequests = filterMarketRequests(publicRequests);
    _nestedDashboardHomeRequests = _applyHiddenFeedFilterToRequests(
      filteredRequests,
    );
    _nestedDashboardPipelineR = (
      server: publicRequests.length,
      filtered: filteredRequests.length,
      shown: _nestedDashboardHomeRequests.length,
    );

    final mixedTimeline = _sortBy == 'latest'
        ? buildMixedHomeTimeline(
            _nestedDashboardHomeItems,
            _nestedDashboardHomeRequests,
          )
        : const <HomeMixedFeedEntry>[];
    _nestedDashboardMixedEntries = mixedTimeline;
    _nestedDashboardMixedHomeCount =
        mixedTimeline.isEmpty ? null : mixedTimeline.length;
    _nestedDashboardMySubmissionsCount = buildMixedHomeTimeline(
      filterListDashboard(_mine, excludePropertiesInCart: true),
      _marketHomeRequests
          .where((r) => r.requesterId == uid && uid.isNotEmpty)
          .toList(),
    ).length;
    _nestedDashboardFeedCacheBuiltKey = key;
  }

  void _ensureNestedDashboardFeedCacheForBuild() {
    _rebuildNestedDashboardFeedCacheSync();
  }

  void _scheduleNestedDashboardFeedCacheRebuild() {
    _rebuildNestedDashboardFeedCacheSync();
  }

  Future<void> _runNestedDashboardFeedCacheRebuildAsync() async {
    // حماية ضد الاستدعاء المباشر المتكرر من مسار الإقلاع (كان يسبب عاصفة setState).
    if (_nestedDashboardFeedCacheRebuildRunning) {
      WebBootstrapDiag.warn('feed.cache', 'skip overlapping run');
      return;
    }
    _nestedDashboardFeedCacheRebuildRunning = true;
    _nestedDashboardFeedCacheRebuildPending = true;
    try {
      await _webYieldUi();
      if (!mounted) return;
      final keyBefore = _nestedDashboardFeedCacheKey();
      if (_nestedDashboardFeedCacheBuiltKey == keyBefore) return;

      WebBootstrapDiag.start('feed.cache');
      await _rebuildNestedDashboardFeedCacheIfStaleAsync();
      WebBootstrapDiag.end(
        'feed.cache',
        'listings=${_nestedDashboardHomeItems.length} requests=${_nestedDashboardHomeRequests.length}',
      );

      if (!mounted) return;
      if (_nestedDashboardFeedCacheKey() != keyBefore &&
          _nestedDashboardFeedCacheBuiltKey != _nestedDashboardFeedCacheKey()) {
        _scheduleNestedDashboardFeedCacheRebuild();
        return;
      }
      // بعد إعادة بناء ناجحة يصبح BuiltKey == keyBefore — هذا متوقع.
      // الشرط السابق كان `== keyBefore → return` فيمنع setState دائماً فتبقى
      // الرئيسية فارغة رغم feed.pipeline shown>0 (سبب الشاشة البيضاء بعد الدخول).
      if (mounted) {
        WebBootstrapDiag.log(
          'feed.paint',
          'setState listings=${_nestedDashboardHomeItems.length} '
              'requests=${_nestedDashboardHomeRequests.length} '
              'mixed=${_nestedDashboardMixedEntries.length}',
        );
        // ويب: لا تهدم IndexedStack — feedSig الجديد يكفي لإعادة رسم الرئيسية عند الحاجة.
        if (!kIsWeb) {
          _webTabChildren = null;
          _webTabChildrenFeedSig = -1;
        }
        setState(() {});
      }
    } finally {
      _nestedDashboardFeedCacheRebuildRunning = false;
      _nestedDashboardFeedCacheRebuildPending = false;
    }
  }

  Future<void> _rebuildNestedDashboardFeedCacheIfStaleAsync() async {
    final key = _nestedDashboardFeedCacheKey();
    if (_nestedDashboardFeedCacheBuiltKey == key) return;

    final uid = _uid.trim();
    final homePropertyPool = _mergedHomePropertyPool();
    _nestedDashboardHomePropertyPoolSize = homePropertyPool.length;
    await _webYieldUi();
    if (!mounted || _nestedDashboardFeedCacheKey() != key) return;

    final filteredList = filterListDashboard(
      homePropertyPool,
      excludePropertiesInCart: !_isGuest && uid.isNotEmpty,
      homeDiscoveryListingCardsOnly: true,
    );
    _nestedDashboardHomeItems = _applyHiddenFeedFilterToProperties(
      filteredList,
    );
    _nestedDashboardPipelineL = (
      server: homePropertyPool.length,
      filtered: filteredList.length,
      shown: _nestedDashboardHomeItems.length,
    );
    await _webYieldUi();
    if (!mounted || _nestedDashboardFeedCacheKey() != key) return;

    final publicRequests = _isGuest || uid.isEmpty
        ? _marketHomeRequests
        : _marketHomeRequests.where((r) => r.requesterId != uid).toList();
    final filteredRequests = filterMarketRequests(publicRequests);
    _nestedDashboardHomeRequests = _applyHiddenFeedFilterToRequests(
      filteredRequests,
    );
    _nestedDashboardPipelineR = (
      server: publicRequests.length,
      filtered: filteredRequests.length,
      shown: _nestedDashboardHomeRequests.length,
    );
    if (kIsWeb) {
      WebBootstrapDiag.log(
        'feed.pipeline',
        'props pool=${_nestedDashboardPipelineL.server} '
            'filt=${_nestedDashboardPipelineL.filtered} '
            'shown=${_nestedDashboardPipelineL.shown} | '
            'req server=${_nestedDashboardPipelineR.server} '
            'filt=${_nestedDashboardPipelineR.filtered} '
            'shown=${_nestedDashboardPipelineR.shown}',
      );
    }
    await _webYieldUi();
    if (!mounted || _nestedDashboardFeedCacheKey() != key) return;

    // ابنِ التسليمة المختلطة دائماً عند latest — اختيار HomeFeedKind عرض فقط.
    final mixedTimeline = _sortBy == 'latest'
        ? buildMixedHomeTimeline(
            _nestedDashboardHomeItems,
            _nestedDashboardHomeRequests,
          )
        : const <HomeMixedFeedEntry>[];
    _nestedDashboardMixedEntries = mixedTimeline;
    _nestedDashboardMixedHomeCount =
        mixedTimeline.isEmpty ? null : mixedTimeline.length;
    _nestedDashboardMySubmissionsCount = buildMixedHomeTimeline(
      filterListDashboard(_mine, excludePropertiesInCart: true),
      _marketHomeRequests
          .where((r) => r.requesterId == uid && uid.isNotEmpty)
          .toList(),
    ).length;
    _nestedDashboardFeedCacheBuiltKey = key;
  }

  void _rebuildNestedDashboardFeedCacheIfStale() {
    // مسار متزامن ثقيل — لا يُستدعى من build؛ التوجيه عبر الجدول المؤجّل فقط.
    _scheduleNestedDashboardFeedCacheRebuild();
  }

  void _ensureNestedDashboardFeedCache() {
    _rebuildNestedDashboardFeedCacheIfStale();
  }

  /// أعداد تشخيصية للرئيسية: [server] بعد دمج [\_mine] الظاهر عالمياً، [filtered] بعد فلاتر الواجهة، [shown] بعد إخفاء الرئيسية.
  ({int server, int filtered, int shown}) _homePropertyFeedPipelineCounts() {
    final pool = _mergedHomePropertyPool();
    final filteredList = filterListDashboard(
      pool,
      excludePropertiesInCart: !_isGuest && _uid.isNotEmpty,
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
    // ويب أثناء التحميل: لا تُفلتر مئات الصفوف على خيط الواجهة.
    if (kIsWeb && _loadingMine && _mine.isEmpty) {
      return const <Property>[];
    }
    final q = _searchQuery.trim();
    final cityFilter = _cityFilter.trim();

    final list = _mine.where((p) {
      if (!_matchesCityFilter(p, cityFilter)) return false;
      if (!_matchesHierarchyFilters(p)) return false;
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

  String _cityLabel(String v) {
    if (v.isEmpty || v == 'all') {
      return widget.isAr ? 'الكل' : 'All';
    }

    return _cityLabelFromJson(v);
  }
}

/// مسودة ورقة «بحث متقدم» — حفظ ديناميكي واستعادة عند إعادة فتح الورقة.
class _DashboardAdvDraftHolder {
  _DashboardAdvDraftHolder({
    required this.query,
    required this.city,
    required this.type,
    required this.purpose,
    required this.furnished,
    required this.priceMin,
    required this.priceMax,
    required this.areaMin,
    required this.areaMax,
    required this.sort,
    required this.homeKind,
    required this.hidden,
    this.region = '',
    this.governorate = '',
    this.district = '',
  });

  factory _DashboardAdvDraftHolder.fromState(_UserDashboardState s) {
    return _DashboardAdvDraftHolder(
      query: s._searchQuery,
      city: s._cityFilter,
      type: s._typeFilter,
      purpose: s._purposeFilter,
      furnished: s._furnishedFilter,
      priceMin: s._priceMinFilter?.toStringAsFixed(0) ?? '',
      priceMax: s._priceMaxFilter?.toStringAsFixed(0) ?? '',
      areaMin: s._areaMinFilter?.toStringAsFixed(0) ?? '',
      areaMax: s._areaMaxFilter?.toStringAsFixed(0) ?? '',
      sort: s._sortBy,
      homeKind: s._homeFeedKind,
      hidden: s._homeShowHiddenOnly,
      region: s._regionFilter,
      governorate: s._governorateFilter,
      district: s._districtFilter,
    );
  }

  String query;
  String city;
  PropertyType? type;
  String? purpose;
  bool? furnished;
  String priceMin;
  String priceMax;
  String areaMin;
  String areaMax;
  String sort;
  HomeFeedKind homeKind;
  bool hidden;

  /// تدرّج الموقع — حقول نصّية بسيطة. عند اختيار «المدينة» يُسحب القيمة إلى
  /// [city] أيضاً ليعمل فلتر المدينة الحالي. عند ترك «الحيّ» سيُلحَق نصُّه
  /// بالاستعلام النصي [query] عند التطبيق ليبحث ضمن العنوان/الاسم.
  String region;
  String governorate;
  String district;

  void resetAll() {
    query = '';
    city = 'all';
    type = null;
    purpose = null;
    furnished = null;
    priceMin = '';
    priceMax = '';
    areaMin = '';
    areaMax = '';
    sort = 'latest';
    homeKind = HomeFeedKind.all;
    hidden = false;
    region = '';
    governorate = '';
    district = '';
  }

  static PropertyType? _parseType(Object? o) {
    if (o == null) return null;
    final s = o.toString().trim().toLowerCase();
    switch (s) {
      case 'villa':
        return PropertyType.villa;
      case 'apartment':
        return PropertyType.apartment;
      case 'land':
        return PropertyType.land;
      default:
        return null;
    }
  }

  static HomeFeedKind _parseHomeKind(Object? o) {
    final s = (o ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'listings':
        return HomeFeedKind.listings;
      case 'requests':
        return HomeFeedKind.requests;
      case 'all':
      default:
        return HomeFeedKind.all;
    }
  }

  Future<void> mergePersistedIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString(AppConfig.prefDashboardAdvancedSearchDraftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final dec = jsonDecode(raw);
      if (dec is! Map) return;
      final m = Map<String, dynamic>.from(dec);
      if (m['q'] is String) query = m['q'] as String;
      if (m['city'] is String) city = m['city'] as String;
      if (m.containsKey('type')) type = _parseType(m['type']);
      if (m.containsKey('purpose')) {
        purpose = m['purpose']?.toString();
      }
      if (m.containsKey('fur')) {
        final f = m['fur'];
        if (f is bool) {
          furnished = f;
        } else {
          furnished = null;
        }
      }
      if (m['priceMin'] is String) priceMin = m['priceMin'] as String;
      if (m['priceMax'] is String) priceMax = m['priceMax'] as String;
      if (m['areaMin'] is String) areaMin = m['areaMin'] as String;
      if (m['areaMax'] is String) areaMax = m['areaMax'] as String;
      if (m['sort'] is String) sort = m['sort'] as String;
      if (m['homeKind'] is String) {
        homeKind = _parseHomeKind(m['homeKind']);
      }
      if (m['hidden'] is bool) hidden = m['hidden'] as bool;
      if (m['region'] is String) region = (m['region'] as String).trim();
      if (m['governorate'] is String) {
        governorate = (m['governorate'] as String).trim();
      }
      if (m['district'] is String) {
        district = (m['district'] as String).trim();
      }
    } catch (_) {}
  }

  Map<String, dynamic> toJson() {
    String? typeStr;
    switch (type) {
      case PropertyType.villa:
        typeStr = 'villa';
        break;
      case PropertyType.apartment:
        typeStr = 'apartment';
        break;
      case PropertyType.land:
        typeStr = 'land';
        break;
      case null:
        typeStr = null;
    }
    return {
      'q': query,
      'city': city,
      'type': typeStr,
      'purpose': purpose,
      'fur': furnished,
      'priceMin': priceMin,
      'priceMax': priceMax,
      'areaMin': areaMin,
      'areaMax': areaMax,
      'sort': sort,
      'homeKind': homeKind.name,
      'hidden': hidden,
      'region': region,
      'governorate': governorate,
      'district': district,
    };
  }
}

extension _UserDashboardAdvSearchDraft on _UserDashboardState {
  void _scheduleAdvSearchDraftSave(_DashboardAdvDraftHolder sheet) {
    _advancedSearchDraftTimer?.cancel();
    _advancedSearchDraftTimer = Timer(const Duration(milliseconds: 420), () {
      unawaited(_persistAdvSearchDraft(sheet));
    });
  }

  Future<void> _persistAdvSearchDraft(_DashboardAdvDraftHolder sheet) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConfig.prefDashboardAdvancedSearchDraftKey,
        jsonEncode(sheet.toJson()),
      );
    } catch (_) {}
  }

  Future<void> _clearAdvSearchDraftPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConfig.prefDashboardAdvancedSearchDraftKey);
    } catch (_) {}
  }
}
