part of 'user_dashboard.dart';

/// مواصفة مسار التسويق الكاملة (نقاط المنتج وحالة التنفيذ): `docs/MARKETING_FULL_FLOW_USER_SPEC_AR.md`

bool _previewImageUrlsEmpty(Map<String, dynamic> r) {
  final urls = ((r['preview_image_urls'] as List?) ?? const <dynamic>[])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return urls.isEmpty;
}

/// لا نستخدم `id` هنا: في صفوف listing_offers يكون id معرف العرض وليس الطلب.
String _listingRequestIdForImageBackfill(Map<String, dynamic> r) {
  final a = (r['request_id'] ?? '').toString().trim();
  if (a.isNotEmpty) return a;
  return (r['listing_request_id'] ?? '').toString().trim();
}

DateTime? _marketerRowCreatedAt(Map<String, dynamic> m) {
  return DateTime.tryParse((m['created_at'] ?? '').toString());
}

/// مهلة ردّ المالك على عرض المسوّق قبل إعادة إظهار الطلب في «الدعوات» (وإخفاء العرض مؤقتاً).
const Duration _kMarketerOwnerOfferGrace = Duration(hours: 48);

bool _marketerOfferIsOwnerWaitingGrace(
  Map<String, dynamic> o,
  Map<String, Map<String, dynamic>> reqMap,
  String marketerUid,
) {
  final reqId =
      (o['request_id'] ?? o['listing_request_id'] ?? '').toString().trim();
  if (reqId.isEmpty) return false;
  final req = reqMap[reqId];
  final selected = (req?['selected_marketer_id'] ?? '').toString().trim();
  if (selected.isNotEmpty && selected != marketerUid) return false;

  final st = (o['status'] ?? '').toString().toLowerCase().trim();
  const terminal = <String>{
    'declined',
    'withdrawn',
    'cancelled',
    'expired',
    'rejected',
    'accepted',
    'approved',
  };
  if (terminal.contains(st)) return false;

  final responded = o['owner_responded_at'] ?? o['owner_decided_at'];
  if (responded != null && responded.toString().trim().isNotEmpty) {
    return false;
  }

  final created = _marketerRowCreatedAt(o)?.toUtc();
  if (created == null) return true;
  return DateTime.now().toUtc().difference(created) < _kMarketerOwnerOfferGrace;
}

bool _marketerOfferBlocksInviteRound(
  Map<String, dynamic> o,
  Map<String, Map<String, dynamic>> reqMap,
  String marketerUid,
) {
  final reqId =
      (o['request_id'] ?? o['listing_request_id'] ?? '').toString().trim();
  if (reqId.isEmpty) return false;
  final req = reqMap[reqId];
  final selected = (req?['selected_marketer_id'] ?? '').toString().trim();
  if (selected.isNotEmpty && selected != marketerUid) return false;

  final st = (o['status'] ?? '').toString().toLowerCase().trim();
  if (<String>{'withdrawn', 'cancelled', 'expired'}.contains(st)) {
    return false;
  }
  return true;
}

bool _marketerOfferExcludedFromOffersList(
  Map<String, dynamic> o,
  Map<String, Map<String, dynamic>> reqMap,
  String marketerUid,
) {
  final reqId =
      (o['request_id'] ?? o['listing_request_id'] ?? '').toString().trim();
  if (reqId.isNotEmpty) {
    final req = reqMap[reqId];
    final selected = (req?['selected_marketer_id'] ?? '').toString().trim();
    if (selected.isNotEmpty && selected != marketerUid) return true;
  }

  if (_marketerOfferIsOwnerWaitingGrace(o, reqMap, marketerUid)) {
    return true;
  }

  final st = (o['status'] ?? '').toString().toLowerCase().trim();
  const terminal = <String>{
    'declined',
    'withdrawn',
    'cancelled',
    'expired',
    'rejected',
    'accepted',
    'approved',
  };
  if (terminal.contains(st)) return false;

  final responded = o['owner_responded_at'] ?? o['owner_decided_at'];
  if (responded != null && responded.toString().trim().isNotEmpty) {
    return false;
  }

  final created = _marketerRowCreatedAt(o)?.toUtc();
  if (created == null) return false;
  return DateTime.now().toUtc().difference(created) >=
      _kMarketerOwnerOfferGrace;
}

/// أكثر من صف دعوة لنفس الطلب/الجولة يظهر كبطاقات مكررة — نبقي الأحدث.
List<Map<String, dynamic>> _dedupeMarketerInvites(
  List<Map<String, dynamic>> list,
  Map<String, Map<String, dynamic>> reqMap,
) {
  final best = <String, Map<String, dynamic>>{};
  for (final r in list) {
    final rid =
        (r['request_id'] ?? r['listing_request_id'] ?? '').toString().trim();
    final roundNo = (r['round_no'] as num?)?.toInt() ??
        (reqMap[rid]?['marketing_round'] as num?)?.toInt() ??
        1;
    final k = rid.isEmpty
        ? 'invite:${(r['id'] ?? '').toString().trim()}'
        : '$rid#$roundNo';
    final prev = best[k];
    if (prev == null) {
      best[k] = r;
      continue;
    }
    final a = _marketerRowCreatedAt(r);
    final b = _marketerRowCreatedAt(prev);
    if (a != null && (b == null || a.isAfter(b))) {
      best[k] = r;
    }
  }
  final out = best.values.toList();
  out.sort((a, b) {
    final da = _marketerRowCreatedAt(a);
    final db = _marketerRowCreatedAt(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return out;
}

extension _UserDashboardStateMarketingLoaders on _UserDashboardState {
  // =========================================================
  // Account role
  // =========================================================
  Future<({bool isOwner, Map<String, dynamic>? permissions})>
      _fetchOrgMembershipNavFlags(String uid) async {
    var isOwner = false;
    Map<String, dynamic>? permissions;
    try {
      final orgSvc = OrgTeamService(_sb);
      final ctx = await orgSvc.myOrgContext();
      final oid = ctx?['org_id']?.toString();
      if (oid != null && oid.isNotEmpty) {
        isOwner = ctx?['is_owner'] == true;
        if (!isOwner) {
          final mem = await _sb
              .from('org_memberships')
              .select('permissions')
              .eq('org_id', oid)
              .eq('user_id', uid)
              .maybeSingle();
          final p = mem?['permissions'];
          if (p is Map) {
            permissions = Map<String, dynamic>.from(
              p.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }
    } catch (_) {}
    return (isOwner: isOwner, permissions: permissions);
  }

  Future<void> _loadAccountRole() async {
    if (_isGuest) {
      await AccountRoleCache.clear();
      _ss(() {
        _accountType = 'user';
        _verified = false;
        _accountRoleLoaded = true;
        _orgNavResolved = true;
        _orgNavIsOwner = false;
        _orgMembershipPermissions = null;
        if (_tabIndex == 3) _tabIndex = 0;
      });
      _ensureSubTabControllers();
      return;
    }

    try {
      final uid = _uid;

      final row = await _net<Map<String, dynamic>?>(() async {
        final ap = await _sb
            .from('account_profiles')
            .select('account_type, verified')
            .eq('user_id', uid)
            .maybeSingle();

        Map<String, dynamic>? data =
            ap == null ? null : Map<String, dynamic>.from(ap);

        if (data == null) {
          final fb = await _sb
              .from('users_profiles')
              .select('account_type, verification_status')
              .eq('user_id', uid)
              .maybeSingle();
          if (fb == null) return null;
          final vs = (fb['verification_status'] ?? '').toString().toLowerCase();
          data = {
            'account_type': (fb['account_type'] ?? 'user').toString().trim(),
            'verified':
                vs == 'verified' || vs == 'approved' || vs == 'complete',
          };
        }
        return data;
      }, tag: 'ACCOUNT_ROLE');

      if (!mounted) return;

      final orgFlags = await _fetchOrgMembershipNavFlags(uid);
      if (!mounted) return;

      _ss(() {
        _accountType = (row?['account_type'] ?? 'user').toString().trim();
        if (_accountType.isEmpty) {
          _accountType = 'user';
        }
        _verified = row?['verified'] == true;
        _accountRoleLoaded = true;
        _orgNavResolved = true;
        _orgNavIsOwner = orgFlags.isOwner;
        _orgMembershipPermissions = orgFlags.permissions;

        // إخفاء تبويب السلة: لا نبقى على شاشة السلة
        if (!_showBottomNavCart && _tabIndex == 3) {
          _tabIndex = 0;
        }
      });

      _ensureSubTabControllers();
      await AccountRoleCache.save(
        AccountRoleSnapshot(
          userId: uid,
          accountType: _accountType,
          verified: _verified,
          orgNavResolved: _orgNavResolved,
          orgNavIsOwner: _orgNavIsOwner,
          orgPermissions: _orgMembershipPermissions,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      try {
        final fb = await _sb
            .from('users_profiles')
            .select('account_type, verification_status')
            .eq('user_id', _uid)
            .maybeSingle();
        if (!mounted) return;
        if (fb != null) {
          final vs = (fb['verification_status'] ?? '').toString().toLowerCase();
          final orgFlags = await _fetchOrgMembershipNavFlags(_uid);
          if (!mounted) return;
          _ss(() {
            _accountType = (fb['account_type'] ?? 'user').toString().trim();
            if (_accountType.isEmpty) _accountType = 'user';
            _verified =
                vs == 'verified' || vs == 'approved' || vs == 'complete';
            _accountRoleLoaded = true;
            _orgNavResolved = true;
            _orgNavIsOwner = orgFlags.isOwner;
            _orgMembershipPermissions = orgFlags.permissions;
            if (!_showBottomNavCart && _tabIndex == 3) {
              _tabIndex = 0;
            }
          });
          _ensureSubTabControllers();
          await AccountRoleCache.save(
            AccountRoleSnapshot(
              userId: _uid,
              accountType: _accountType,
              verified: _verified,
              orgNavResolved: _orgNavResolved,
              orgNavIsOwner: _orgNavIsOwner,
              orgPermissions: _orgMembershipPermissions,
            ),
          );
          return;
        }
      } catch (_) {}

      final orgFlags = await _fetchOrgMembershipNavFlags(_uid);
      if (!mounted) return;
      _ss(() {
        _accountType = 'user';
        _verified = false;
        _accountRoleLoaded = true;
        _orgNavResolved = true;
        _orgNavIsOwner = orgFlags.isOwner;
        _orgMembershipPermissions = orgFlags.permissions;
        if (!_showBottomNavCart && _tabIndex == 3) {
          _tabIndex = 0;
        }
      });

      _ensureSubTabControllers();
      await AccountRoleCache.save(
        AccountRoleSnapshot(
          userId: _uid,
          accountType: _accountType,
          verified: _verified,
          orgNavResolved: _orgNavResolved,
          orgNavIsOwner: _orgNavIsOwner,
          orgPermissions: _orgMembershipPermissions,
        ),
      );
    }
  }

  // =========================================================
  // Tab controllers
  // =========================================================
  void _ensureSubTabControllers() {
    if (!mounted) return;

    final bool shouldUseMarketerTabs = _isMarketerRole;
    final bool shouldUseOwnerTabs = !_isMarketerRole;

    if (shouldUseOwnerTabs) {
      if (_marketerTabsCtrl != null) {
        _marketerTabsCtrl!.dispose();
        _marketerTabsCtrl = null;
      }

      if (_ownerTabsCtrl == null || _ownerTabsCtrl!.length != 7) {
        final int preserved = _ownerTabsCtrl?.index ?? 0;
        _ownerTabsCtrl?.dispose();
        final newIdx = preserved.clamp(0, 6);
        _ownerTabsCtrl = TabController(
          length: 7,
          vsync: this,
          initialIndex: newIdx,
        );
      } else {
        final idx = _ownerTabsCtrl!.index.clamp(0, 6);
        if (_ownerTabsCtrl!.index != idx) {
          _ownerTabsCtrl!.index = idx;
        }
      }
      return;
    }

    if (shouldUseMarketerTabs) {
      if (_ownerTabsCtrl != null) {
        _ownerTabsCtrl!.dispose();
        _ownerTabsCtrl = null;
      }

      if (_marketerTabsCtrl == null || _marketerTabsCtrl!.length != 6) {
        final int preservedIndex = _marketerTabsCtrl?.index ?? 0;
        _marketerTabsCtrl?.dispose();
        _marketerTabsCtrl = TabController(
          length: 6,
          vsync: this,
          initialIndex: preservedIndex.clamp(0, 5),
        );
      } else {
        final idx = _marketerTabsCtrl!.index.clamp(0, 5);
        if (_marketerTabsCtrl!.index != idx) {
          _marketerTabsCtrl!.index = idx;
        }
      }
    }
  }

  Map<String, dynamic> _mergedJsonPayloadForRow(Map<String, dynamic> row) {
    final payload = <String, dynamic>{};
    void mergeDyn(dynamic v) {
      final decoded = _decodeLooseJsonMap(v);
      if (decoded.isNotEmpty) payload.addAll(decoded);
    }

    mergeDyn(row['payload_json']);
    mergeDyn(row['payload']);
    return payload;
  }

  Map<String, dynamic> _decodeLooseJsonMap(dynamic value) {
    dynamic cur = value;
    for (var i = 0; i < 3; i++) {
      if (cur is Map) {
        return Map<String, dynamic>.from(cur);
      }
      if (cur is String && cur.trim().isNotEmpty) {
        try {
          cur = jsonDecode(cur);
          continue;
        } catch (_) {
          return <String, dynamic>{};
        }
      }
      break;
    }
    return <String, dynamic>{};
  }

  /// يملأ حقول المعاينة من `payload` عند غياب صف `properties` المرتبط.
  void _applyPayloadFallbacksToOwnerRequestRow(Map<String, dynamic> row) {
    final payload = _mergedJsonPayloadForRow(row);

    String pick(String k) => (row[k] ?? '').toString().trim();

    final fallbackTitle = _payloadString(payload, const [
      'title',
      'listing_title',
      'property_title',
    ]);
    if (pick('request_title').isEmpty &&
        pick('title').isEmpty &&
        fallbackTitle.isNotEmpty) {
      row['request_title'] = fallbackTitle;
    }

    final urls = ((row['preview_image_urls'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      final fromPayload = _payloadImagePaths(payload)
          .map((p) => p.startsWith('http')
              ? p
              : _sb.storage.from('property-images').getPublicUrl(p))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (fromPayload.isNotEmpty) {
        row['preview_image_urls'] = fromPayload;
      }
    }

    num? asNum(dynamic v) {
      if (v is num) return v;
      return num.tryParse('${v ?? ''}');
    }

    final previewPrice = asNum(row['preview_price']);
    if (previewPrice == null || previewPrice == 0) {
      final colPrice = asNum(row['price']);
      final reqPrice = asNum(row['request_price']);
      final fromPay = _payloadNum(payload, const ['price', 'offer_price']);
      num? best = (colPrice != null && colPrice != 0) ? colPrice : null;
      if (best == null && reqPrice != null && reqPrice != 0) {
        best = reqPrice;
      }
      if (best == null && fromPay != null && fromPay != 0) {
        best = fromPay;
      }
      if (best != null) {
        row['preview_price'] = best;
      }
    }

    final previewArea = asNum(row['preview_area']);
    if (previewArea == null || previewArea == 0) {
      final pArea = _payloadNum(payload, const ['area', 'sqm', 'area_sqm']);
      if (pArea != null && pArea != 0) {
        row['preview_area'] = pArea;
      }
    }

    if (pick('preview_city').isEmpty) {
      final c = _payloadString(payload, const ['city', 'location_city']);
      if (c.isNotEmpty) row['preview_city'] = c;
    }

    if (pick('preview_location').isEmpty) {
      final loc = _payloadString(payload, const [
        'location',
        'address_line',
        'district',
        'neighborhood',
        'region',
      ]);
      if (loc.isNotEmpty) row['preview_location'] = loc;
    }

    final desc = pick('preview_description');
    final desc2 = pick('request_description');
    final desc3 = pick('description');
    if (desc.isEmpty && desc2.isEmpty && desc3.isEmpty) {
      final fd = _payloadString(payload, const ['description', 'details']);
      if (fd.isNotEmpty) row['preview_description'] = fd;
    }

    if (pick('preview_type').isEmpty) {
      final t = _payloadString(payload, const [
        'type',
        'property_type',
        'listing_type',
      ]);
      if (t.isNotEmpty) row['preview_type'] = t;
    }

    if (pick('request_owner_name').isEmpty &&
        pick('preview_owner_name').isEmpty) {
      final on = _payloadString(payload, const [
        'owner_full_name',
        'owner_name',
        'owner_display_name',
        'full_name',
        'advertiser_name',
        'contact_name',
      ]);
      if (on.isNotEmpty) {
        row['request_owner_name'] = on;
        row['preview_owner_name'] = on;
      }
    }
  }

  // =========================================================
  // Owner buckets
  // =========================================================
  Future<void> _loadOwnerRequestsBuckets({bool force = false}) async {
    if (_isGuest || _isMarketerRole) return;

    _ensureSubTabControllers();

    _ss(() {
      _loadingRequests = true;
      _errorRequests = null;

      if (force) {
        _ownerListingRequests = <Map<String, dynamic>>[];
      }
    });

    try {
      final uid = _uid;

      final data = await _net<List<Map<String, dynamic>>>(() async {
        final result = await _sb
            .from('listing_requests')
            .select(SupabaseSchemaSelects.listingRequestsLookup)
            .eq('owner_id', uid)
            .order(
              'created_at',
              ascending: false,
            );

        return (result as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }, tag: 'OWNER_REQS');

      final rows = data ?? <Map<String, dynamic>>[];
      final reqIds = _extractSafeIds(rows, key: 'id');
      final previewPidByReq = <String, String>{};
      for (final raw in rows) {
        final rid = (raw['id'] ?? '').toString().trim();
        final pp = (raw['preview_property_id'] ?? '').toString().trim();
        if (rid.isNotEmpty && pp.isNotEmpty) previewPidByReq[rid] = pp;
      }
      final previewMap = await _fetchPreviewPropertiesByRequestIds(
        reqIds,
        previewPropertyIdByRequestId:
            previewPidByReq.isEmpty ? null : previewPidByReq,
      );

      final merged = <Map<String, dynamic>>[];

      for (final raw in rows) {
        final requestId = (raw['id'] ?? '').toString().trim();
        if (requestId.isEmpty) continue;

        final row = <String, dynamic>{
          ...raw,
          ...?previewMap[requestId],
          'request_id': requestId,
          'request_workflow_stage': (raw['workflow_stage'] ?? '').toString(),
          'request_title': (raw['title'] ?? '').toString(),
          'request_city': (raw['city'] ?? '').toString(),
          'request_description': (raw['description'] ?? '').toString(),
          'request_owner_id': (raw['owner_id'] ?? '').toString(),
          'request_owner_name': '',
          'request_owner_phone': '',
        };

        _applyPayloadFallbacksToOwnerRequestRow(row);
        merged.add(row);
      }

      // نفس منطق المسوّقين: جلب صف العقار المعاين بالكامل عند نقص الصور/السعر/النوع.
      final reqMapForBackfill = <String, Map<String, dynamic>>{};
      for (final r in merged) {
        final id = (r['request_id'] ?? r['id'] ?? '').toString().trim();
        if (id.isNotEmpty) reqMapForBackfill[id] = Map<String, dynamic>.from(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        merged,
        reqMapForBackfill,
      );
      await _backfillOwnerRequestCoverImagesFromDb(merged);
      await _cacheOwnerRequestPreviewProperties(merged);

      if (!mounted) return;

      _ss(() {
        _ownerListingRequests = merged;
      });
    } catch (e) {
      if (!mounted) return;
      _ss(() {
        _errorRequests = e.toString();
      });
    } finally {
      if (!mounted) return;
      _ss(() {
        _loadingRequests = false;
      });
    }
  }

  Future<void> _cacheOwnerRequestPreviewProperties(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows
        .map((r) => (r['preview_property_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty && !_propertyCache.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final fetched = await Future.wait(ids.map(_fetchPropertyById));
    if (!mounted) return;
    _ss(() {
      for (final property in fetched) {
        if (property == null) continue;
        _propertyCache[property.id] = property;
        _myPropertyById[property.id] = property;
      }
    });
  }

  // =========================================================
  // Request ids helpers
  // =========================================================
  /// `listing_request_invites` يستخدم غالباً `listing_request_id` وليس `request_id`.
  List<String> _extractRequestIdsFromRows(List<Map<String, dynamic>> rows) {
    final out = <String>{};
    for (final e in rows) {
      for (final key in const ['request_id', 'listing_request_id']) {
        final id = (e[key] ?? '').toString().trim();
        if (id.isNotEmpty) out.add(id);
      }
    }
    return out.toList();
  }

  List<String> _extractSafeIds(
    List<Map<String, dynamic>> rows, {
    required String key,
  }) {
    return rows
        .map((e) => (e[key] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value == null) return <Map<String, dynamic>>[];
    if (value is Map) {
      return [Map<String, dynamic>.from(value)];
    }
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  String _payloadString(Map<String, dynamic> payload, List<String> keys) {
    for (final k in keys) {
      final s = (payload[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  num? _payloadNum(Map<String, dynamic> payload, List<String> keys) {
    for (final k in keys) {
      final v = payload[k];
      if (v is num) return v;
      final n = num.tryParse((v ?? '').toString().trim());
      if (n != null) return n;
    }
    return null;
  }

  Future<void> _backfillOwnerRequestCoverImagesFromDb(
    List<Map<String, dynamic>> merged,
  ) async {
    String toPub(String path) => path.startsWith('http')
        ? path
        : _sb.storage.from('property-images').getPublicUrl(path);

    void applyFromMeta(
      Map<String, dynamic> r,
      String propId,
      Map<String, dynamic>? meta,
      Map<String, String> firstPathByProp,
    ) {
      if (meta == null || !_previewImageUrlsEmpty(r)) return;
      final path = firstPathByProp[propId];
      if (path != null && path.isNotEmpty) {
        r['preview_image_urls'] = [toPub(path)];
        return;
      }
      final iu = (meta['image_url'] ?? '').toString().trim();
      if (iu.isNotEmpty) {
        r['preview_image_urls'] = [toPub(iu)];
        return;
      }
      final arr = meta['images'];
      if (arr is List) {
        final outs = <String>[];
        for (final e in arr) {
          final pth = e.toString().trim();
          if (pth.isEmpty) continue;
          outs.add(toPub(pth));
        }
        if (outs.isNotEmpty) {
          r['preview_image_urls'] = outs;
          return;
        }
      }
      final prim = (meta['primary_image'] ?? meta['primaryImage'] ?? '')
          .toString()
          .trim();
      if (prim.isNotEmpty) {
        r['preview_image_urls'] = [toPub(prim)];
      }
    }

    // المرور 1: ربط عبر request_id / listing_request_id (وليس id صف العرض)
    final needIds = <String>[];
    for (final r in merged) {
      if (!_previewImageUrlsEmpty(r)) continue;
      final rid = _listingRequestIdForImageBackfill(r);
      if (rid.isNotEmpty) needIds.add(rid);
    }
    if (needIds.isNotEmpty) {
      try {
        final props = await _net<List<Map<String, dynamic>>>(() async {
          final data = await _sb
              .from('properties')
              .select('id, request_id, image_url, images')
              .inFilter('request_id', needIds)
              .order('created_at', ascending: false);
          return (data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }, tag: 'OWNER_REQ_IMG_PROPS');

        final requestToPropId = <String, String>{};
        final propMetaById = <String, Map<String, dynamic>>{};
        for (final p in props ?? const <Map<String, dynamic>>[]) {
          final rid = (p['request_id'] ?? '').toString().trim();
          final id = (p['id'] ?? '').toString().trim();
          if (rid.isEmpty || id.isEmpty) continue;
          requestToPropId.putIfAbsent(rid, () => id);
          propMetaById[id] = p;
        }

        if (requestToPropId.isNotEmpty) {
          final propIds = requestToPropId.values.toSet().toList();
          final imgRows = await _net<List<Map<String, dynamic>>>(() async {
            final data = await _sb
                .from('property_images')
                .select('property_id, path, file_name, sort_order')
                .inFilter('property_id', propIds)
                .order('sort_order', ascending: true);
            return (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }, tag: 'OWNER_REQ_IMG_ROWS');

          final firstPathByProp = <String, String>{};
          for (final im in imgRows ?? const <Map<String, dynamic>>[]) {
            final pid = (im['property_id'] ?? '').toString().trim();
            final path =
                (im['path'] ?? im['file_name'] ?? '').toString().trim();
            if (pid.isEmpty || path.isEmpty) continue;
            firstPathByProp.putIfAbsent(pid, () => path);
          }

          for (final r in merged) {
            if (!_previewImageUrlsEmpty(r)) continue;
            final rid = _listingRequestIdForImageBackfill(r);
            final propId = requestToPropId[rid];
            if (propId == null) continue;
            applyFromMeta(r, propId, propMetaById[propId], firstPathByProp);
          }
        }
      } catch (_) {}
    }

    // المرور 2: صفوف العروض/الدعوات حيث id ≠ request_id لكن preview_property_id معروف
    final needPropIds = <String>{};
    for (final r in merged) {
      if (!_previewImageUrlsEmpty(r)) continue;
      final pid = (r['preview_property_id'] ?? '').toString().trim();
      if (pid.isNotEmpty) needPropIds.add(pid);
    }
    if (needPropIds.isEmpty) return;

    try {
      final props2 = await _net<List<Map<String, dynamic>>>(() async {
        final data = await _sb
            .from('properties')
            .select('id, request_id, image_url, images')
            .inFilter('id', needPropIds.toList());
        return (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }, tag: 'REQ_IMG_BY_PROP_ID');

      final propMetaById2 = <String, Map<String, dynamic>>{};
      for (final p in props2 ?? const <Map<String, dynamic>>[]) {
        final id = (p['id'] ?? '').toString().trim();
        if (id.isNotEmpty) propMetaById2[id] = p;
      }
      if (propMetaById2.isEmpty) return;

      final imgRows2 = await _net<List<Map<String, dynamic>>>(() async {
        final data = await _sb
            .from('property_images')
            .select('property_id, path, file_name, sort_order')
            .inFilter('property_id', propMetaById2.keys.toList())
            .order('sort_order', ascending: true);
        return (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }, tag: 'REQ_IMG_ROWS_BY_PROP');

      final firstPathByProp2 = <String, String>{};
      for (final im in imgRows2 ?? const <Map<String, dynamic>>[]) {
        final pid = (im['property_id'] ?? '').toString().trim();
        final path = (im['path'] ?? im['file_name'] ?? '').toString().trim();
        if (pid.isEmpty || path.isEmpty) continue;
        firstPathByProp2.putIfAbsent(pid, () => path);
      }

      for (final r in merged) {
        if (!_previewImageUrlsEmpty(r)) continue;
        final pid = (r['preview_property_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        applyFromMeta(r, pid, propMetaById2[pid], firstPathByProp2);
      }
    } catch (_) {}
  }

  String _coverPrimaryFromPayload(Map<String, dynamic> payload) {
    final g = payload['listing_guidance'];
    if (g is Map) {
      final v = (g['cover_primary'] ?? 'image').toString().toLowerCase();
      return v == 'video' ? 'video' : 'image';
    }
    return 'image';
  }

  String _previewCoverPrimaryFromPropertyRow(Map<String, dynamic> row) {
    dynamic g = row['listing_guidance'];
    if (g is String && g.trim().startsWith('{')) {
      try {
        final d = jsonDecode(g);
        if (d is Map) g = d;
      } catch (_) {}
    }
    if (g is Map) {
      final v = (g['cover_primary'] ?? 'image').toString().toLowerCase();
      return v == 'video' ? 'video' : 'image';
    }
    return 'image';
  }

  String _mergeCoverPrimary(dynamic a, dynamic b) {
    for (final x in [a, b]) {
      final t = (x ?? '').toString().trim().toLowerCase();
      if (t == 'video' || t == 'image') return t;
    }
    return 'image';
  }

  List<String> _payloadImagePaths(Map<String, dynamic> payload) {
    for (final k in const [
      'request_image_paths',
      'image_paths',
      'image_urls',
      'images',
      'photos',
      'gallery',
      'property_images',
      'cover_image',
      'main_image',
      'image',
      'thumbnail',
      'listing_image',
      'photo',
      'photo_url',
      'hero_image',
      'primary_image',
      'primaryImage',
    ]) {
      final raw = payload[k];
      if (raw is List) {
        final out = raw
            .map((e) {
              if (e is Map) {
                for (final kk in const ['path', 'url', 'image', 'image_url']) {
                  final v = (e[kk] ?? '').toString().trim();
                  if (v.isNotEmpty) return v;
                }
              }
              return e.toString().trim();
            })
            .where((e) => e.isNotEmpty)
            .toList();
        if (out.isNotEmpty) return out;
      } else if (raw is Map) {
        final p = _previewImagePathFromMap(Map<String, dynamic>.from(raw));
        if (p != null && p.isNotEmpty) return [p];
      } else if (raw is String && raw.trim().isNotEmpty) {
        final s = raw.trim();
        if (s.startsWith('[') && s.endsWith(']')) {
          try {
            final parsed = jsonDecode(s);
            if (parsed is List) {
              final out = parsed
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (out.isNotEmpty) return out;
            }
          } catch (_) {}
        } else {
          return [s];
        }
      }
    }
    return const <String>[];
  }

  String? _previewImagePathFromMap(Map<String, dynamic> e) {
    for (final k in const [
      'path',
      'file_name',
      'url',
      'file_path',
      'storage_path',
    ]) {
      final s = e[k]?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  // =========================================================
  // Request lookup map
  // =========================================================
  Future<Map<String, Map<String, dynamic>>> _fetchListingRequestsMap(
    List<String> requestIds,
  ) async {
    final ids = requestIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return <String, Map<String, dynamic>>{};

    final data = await _net<List<Map<String, dynamic>>>(() async {
      const minimalSelect = '''
id,
owner_id,
title,
city,
description,
status,
workflow_stage,
created_at,
updated_at,
preview_property_id
''';
      dynamic result;
      try {
        result = await _sb
            .from('listing_requests')
            .select(SupabaseSchemaSelects.listingRequestsLookup)
            .inFilter('id', ids);
      } catch (_) {
        result = await _sb
            .from('listing_requests')
            .select(minimalSelect)
            .inFilter('id', ids);
      }

      return (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }, tag: 'REQ_LOOKUP');

    final out = <String, Map<String, dynamic>>{};

    for (final r in (data ?? <Map<String, dynamic>>[])) {
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      Map<String, dynamic> payload = <String, dynamic>{};
      void mergeDecoded(dynamic v) {
        if (v is Map) {
          payload = {...payload, ...Map<String, dynamic>.from(v)};
          return;
        }
        if (v is String && v.trim().isNotEmpty) {
          try {
            final d = jsonDecode(v);
            if (d is Map) {
              payload = {...payload, ...Map<String, dynamic>.from(d)};
            }
          } catch (_) {}
        }
      }

      mergeDecoded(r['payload_json']);
      mergeDecoded(r['payload']);

      final fallbackTitle = _payloadString(payload, const [
        'title',
        'listing_title',
        'property_title',
      ]);
      final fallbackCity =
          _payloadString(payload, const ['city', 'location_city']);
      final fallbackLocation = _payloadString(payload, const [
        'location',
        'address_line',
        'district',
      ]);
      final fallbackDescription = _payloadString(payload, const [
        'description',
        'details',
      ]);
      final fallbackPrice =
          _payloadNum(payload, const ['price', 'offer_price']);
      final fallbackArea =
          _payloadNum(payload, const ['area', 'sqm', 'area_sqm']);
      final fallbackImages = _payloadImagePaths(payload)
          .map((p) => p.startsWith('http')
              ? p
              : _sb.storage.from('property-images').getPublicUrl(p))
          .toList();

      num? colNum(dynamic v) {
        if (v is num) return v;
        return num.tryParse('${v ?? ''}'.trim());
      }

      final dbPrice = colNum(r['price']);
      final dbPreviewPrice = colNum(r['preview_price']);
      final dbRequestPrice = colNum(r['request_price']);
      num? resolvedPrice;
      for (final cand in [
        dbPrice,
        dbPreviewPrice,
        dbRequestPrice,
        fallbackPrice
      ]) {
        if (cand != null && cand != 0) {
          resolvedPrice = cand;
          break;
        }
      }
      final resolvedPriceForRow = resolvedPrice ?? fallbackPrice ?? 0;
      final dbArea = colNum(r['area']);
      final resolvedArea =
          (dbArea != null && dbArea != 0) ? dbArea : fallbackArea;

      final ownerFromPayload = _payloadString(payload, const [
        'owner_full_name',
        'owner_name',
        'owner_display_name',
        'full_name',
        'advertiser_name',
        'contact_name',
      ]);

      out[id] = <String, dynamic>{
        ...r,
        'request_id': id,
        'request_workflow_stage': (r['workflow_stage'] ?? '').toString(),
        'request_owner_id': (r['owner_id'] ?? '').toString(),
        'request_title': ((r['title'] ?? '').toString().trim().isNotEmpty
                ? r['title']
                : fallbackTitle)
            .toString(),
        'request_city': ((r['city'] ?? '').toString().trim().isNotEmpty
                ? r['city']
                : fallbackCity)
            .toString(),
        'request_location': fallbackLocation,
        'request_description':
            ((r['description'] ?? '').toString().trim().isNotEmpty
                    ? r['description']
                    : fallbackDescription)
                .toString(),
        'request_price': resolvedPriceForRow,
        'request_area': resolvedArea,
        'request_image_urls': fallbackImages,
        'request_property_type': _payloadString(payload, const [
          'type',
          'property_type',
          'listing_type',
        ]),
        'request_purpose': _payloadString(payload, const [
          'purpose',
          'listing_purpose',
        ]),
        'request_status': (r['status'] ?? '').toString(),
        'request_owner_name': ownerFromPayload,
        'request_owner_phone': _payloadString(payload, const [
          'owner_phone',
          'contact_phone',
          'phone',
        ]),
        'request_video_path':
            _payloadString(payload, ['request_video_path', 'video_url']),
        'request_cover_primary': _coverPrimaryFromPayload(payload),
      };
    }

    return out;
  }

  // =========================================================
  // Preview properties by request ids
  // =========================================================

  /// يبني خريطة المعاينة لطلب تسويق من صف property (+ property_images المضمّنة).
  Map<String, dynamic>? _buildPreviewMapEntryForRequest(
    String requestId,
    Map<String, dynamic> row,
  ) {
    if (requestId.isEmpty) return null;

    final imagesRows = _asMapList(row['property_images'])
      ..sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sbOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sbOrder);
      });

    final images = imagesRows
        .map(_previewImagePathFromMap)
        .whereType<String>()
        .map((p) => p.startsWith('http')
            ? p
            : _sb.storage.from('property-images').getPublicUrl(p))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (images.isEmpty) {
      final rawCover = (row['image_url'] ?? '').toString().trim();
      if (rawCover.isNotEmpty) {
        images.add(
          rawCover.startsWith('http')
              ? rawCover
              : _sb.storage.from('property-images').getPublicUrl(rawCover),
        );
      }
    }
    if (images.isEmpty && row['images'] is List) {
      for (final e in row['images'] as List) {
        final p = e.toString().trim();
        if (p.isEmpty) continue;
        images.add(
          p.startsWith('http')
              ? p
              : _sb.storage.from('property-images').getPublicUrl(p),
        );
      }
    }
    if (images.isEmpty) {
      final primary =
          (row['primary_image'] ?? row['primaryImage'] ?? '').toString().trim();
      if (primary.isNotEmpty) {
        images.add(
          primary.startsWith('http')
              ? primary
              : _sb.storage.from('property-images').getPublicUrl(primary),
        );
      }
    }

    final propUsername = (row['username'] ?? '').toString().trim();
    final ownerNamed = (row['owner_display_name'] ?? row['owner_name'] ?? '')
        .toString()
        .trim();
    final previewOwnerName = ownerNamed.isNotEmpty ? ownerNamed : propUsername;

    return <String, dynamic>{
      'preview_property_id': (row['id'] ?? '').toString(),
      'preview_title': (row['title'] ?? '').toString(),
      'preview_city': (row['city'] ?? '').toString(),
      'preview_location': (row['location'] ?? '').toString(),
      'preview_address_line': (row['address_line'] ?? '').toString(),
      'preview_description': (row['description'] ?? '').toString(),
      'preview_type': (row['type'] ?? '').toString(),
      'preview_status': (row['status'] ?? '').toString(),
      'preview_workflow_stage': (row['workflow_stage'] ?? '').toString(),
      'preview_price': row['price'],
      'preview_area': row['area'],
      'preview_currency': (row['currency'] ?? 'SAR').toString(),
      'preview_is_auction': row['is_auction'],
      'preview_purpose': (row['purpose'] ?? '').toString(),
      'preview_current_bid': row['current_bid'],
      'preview_contact_phone': (row['contact_phone'] ?? '').toString(),
      'preview_owner_name': previewOwnerName,
      'preview_owner_phone': '',
      'preview_published_by_marketer_id':
          (row['published_by_marketer_id'] ?? '').toString(),
      'preview_bedrooms': row['bedrooms'],
      'preview_bathrooms': row['bathrooms'],
      'preview_parking_spots': row['parking_spots'],
      'preview_furnished': row['furnished'],
      'preview_year_built': row['year_built'],
      'preview_floor': row['floor'],
      'preview_total_floors': row['total_floors'],
      'preview_created_at': row['created_at'],
      'preview_published_at': row['published_at'],
      'preview_marketing_license_snapshot': row['marketing_license_snapshot'],
      'preview_views': row['views'],
      'preview_image_urls': images,
      'preview_video_url': (row['video_url'] ?? '').toString().trim(),
      'preview_cover_primary': _previewCoverPrimaryFromPropertyRow(row),
    };
  }

  Future<Map<String, Map<String, dynamic>>> _fetchPreviewPropertiesByRequestIds(
    List<String> requestIds, {
    Map<String, String>? previewPropertyIdByRequestId,
  }) async {
    final ids = requestIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return <String, Map<String, dynamic>>{};

    final result = await _net<List<Map<String, dynamic>>>(() async {
      final data = await _sb
          .from('properties')
          .select(SupabaseSchemaSelects.propertiesPreviewByRequestId)
          .inFilter('request_id', ids)
          .order(
            'created_at',
            ascending: false,
          );

      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }, tag: 'REQ_PREVIEW_PROPS');

    final out = <String, Map<String, dynamic>>{};

    for (final row in (result ?? <Map<String, dynamic>>[])) {
      final requestId = (row['request_id'] ?? '').toString().trim();
      if (requestId.isEmpty) continue;
      if (out.containsKey(requestId)) continue;
      final entry = _buildPreviewMapEntryForRequest(
        requestId,
        Map<String, dynamic>.from(row),
      );
      if (entry != null) out[requestId] = entry;
    }

    final byPreviewId = previewPropertyIdByRequestId;
    if (byPreviewId != null && byPreviewId.isNotEmpty) {
      final pending = <String, String>{};
      for (final rid in ids) {
        if (out.containsKey(rid)) continue;
        final pid = byPreviewId[rid]?.trim();
        if (pid != null && pid.isNotEmpty) pending[rid] = pid;
      }
      if (pending.isNotEmpty) {
        final uniquePids = pending.values.toSet().toList();
        final result2 = await _net<List<Map<String, dynamic>>>(() async {
          final data = await _sb
              .from('properties')
              .select(SupabaseSchemaSelects.propertiesPreviewByRequestId)
              .inFilter('id', uniquePids);
          return (data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }, tag: 'REQ_PREVIEW_BY_PREVIEW_PID');

        final byId = <String, Map<String, dynamic>>{};
        for (final r in result2 ?? <Map<String, dynamic>>[]) {
          final id = (r['id'] ?? '').toString().trim();
          if (id.isNotEmpty) byId[id] = r;
        }
        for (final e in pending.entries) {
          final rid = e.key;
          final pid = e.value;
          if (out.containsKey(rid)) continue;
          final pro = byId[pid];
          if (pro == null) continue;
          final entry = _buildPreviewMapEntryForRequest(
            rid,
            Map<String, dynamic>.from(pro),
          );
          if (entry != null) out[rid] = entry;
        }
      }
    }

    return out;
  }

  // =========================================================
  // Merge request + preview info
  // =========================================================
  String _mergeNonEmptyStr(dynamic a, dynamic b, [dynamic c, dynamic d]) {
    for (final x in [a, b, c, d]) {
      final t = (x ?? '').toString().trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  List<dynamic> _mergeImageUrlLists(dynamic previewUrls, dynamic reqUrls) {
    List<String> norm(dynamic list) {
      if (list is! List) return const [];
      return list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final p = norm(previewUrls);
    if (p.isNotEmpty) return p;
    return norm(reqUrls);
  }

  double _mergeNum(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  dynamic _mergePricePreferPositive(dynamic previewP, dynamic reqP) {
    if (_mergeNum(previewP) > 0) return previewP;
    return reqP;
  }

  dynamic _mergeAreaPreferPositive(dynamic previewA, dynamic reqA) {
    if (_mergeNum(previewA) > 0) return previewA;
    return reqA;
  }

  /// دمج payload الطلب مع أي حقول في صف الدعوة/العرض دون مسح بيانات الطلب.
  Map<String, dynamic> _mergeRequestPayloadMaps(
    dynamic reqPayloadJson,
    dynamic reqPayload,
    dynamic invitePayloadJson,
    dynamic invitePayload,
  ) {
    final out = <String, dynamic>{};
    void mergeDyn(dynamic v) {
      final decoded = _decodeLooseJsonMap(v);
      if (decoded.isNotEmpty) out.addAll(decoded);
    }

    mergeDyn(reqPayloadJson);
    mergeDyn(reqPayload);
    mergeDyn(invitePayloadJson);
    mergeDyn(invitePayload);
    return out;
  }

  Map<String, dynamic> _mergeRequestInfo({
    required Map<String, dynamic> row,
    required Map<String, Map<String, dynamic>> reqMap,
    required Map<String, Map<String, dynamic>> previewMap,
  }) {
    final requestId = (row['request_id'] ?? row['listing_request_id'] ?? '')
        .toString()
        .trim();

    final req = reqMap[requestId] ?? const <String, dynamic>{};
    final preview = previewMap[requestId] ?? const <String, dynamic>{};

    // لا تسمح لحالة listing_requests أن تستبدل status الدعوة/العرض/العقد (كان يعطّل زر تقديم العرض).
    final reqNoStatus = Map<String, dynamic>.from(req);
    if (reqNoStatus.containsKey('status')) {
      reqNoStatus['listing_request_status'] =
          reqNoStatus.remove('status') ?? '';
    }

    final rowWithoutPayload = Map<String, dynamic>.from(row);
    rowWithoutPayload.remove('payload_json');
    rowWithoutPayload.remove('payload');

    final mergedPayload = _mergeRequestPayloadMaps(
      req['payload_json'],
      req['payload'],
      row['payload_json'],
      row['payload'],
    );

    final mergedImages = _mergeImageUrlLists(
        preview['preview_image_urls'], req['request_image_urls']);

    return <String, dynamic>{
      ...reqNoStatus,
      ...preview,
      ...rowWithoutPayload,
      if (mergedPayload.isNotEmpty) 'payload_json': mergedPayload,
      'preview_title': _mergeNonEmptyStr(
        preview['preview_title'],
        req['request_title'],
        req['title'],
      ),
      'preview_city': _mergeNonEmptyStr(
        preview['preview_city'],
        req['request_city'],
        req['city'],
      ),
      'preview_location': _mergeNonEmptyStr(
        preview['preview_location'],
        preview['preview_address_line'],
        req['request_location'],
      ),
      'preview_description': _mergeNonEmptyStr(
        preview['preview_description'],
        req['request_description'],
        req['description'],
      ),
      'preview_price': _mergePricePreferPositive(
        preview['preview_price'],
        req['request_price'],
      ),
      'preview_area': _mergeAreaPreferPositive(
        preview['preview_area'],
        req['request_area'],
      ),
      'preview_type': _mergeNonEmptyStr(
        preview['preview_type'],
        req['request_property_type'],
      ),
      'preview_purpose': _mergeNonEmptyStr(
        preview['preview_purpose'],
        req['request_purpose'],
      ),
      'preview_created_at': preview['preview_created_at'] ?? req['created_at'],
      'preview_image_urls': mergedImages,
      'preview_video_url': _mergeNonEmptyStr(
        preview['preview_video_url'],
        req['request_video_path'],
      ),
      'preview_cover_primary': _mergeCoverPrimary(
        preview['preview_cover_primary'],
        req['request_cover_primary'],
      ),
      'request_workflow_stage':
          (req['request_workflow_stage'] ?? req['workflow_stage'] ?? '')
              .toString(),
      // تثبيت بيانات الطلب فوق صف العرض/الدعوة/العقد
      'request_id': requestId,
      'listing_request_status':
          (req['listing_request_status'] ?? req['request_status'] ?? '')
              .toString(),
      'request_owner_name': _mergeNonEmptyStr(
        req['request_owner_name'],
        preview['preview_owner_name'],
        row['request_owner_name'],
      ),
      'preview_owner_name': _mergeNonEmptyStr(
        req['request_owner_name'],
        preview['preview_owner_name'],
      ),
    };
  }

  /// عندما يكون الدمج من listing_offers لا يحمل صور/سعر العقار، نملأ من properties.preview_property_id (نفس منطق SQL للمالك).
  Future<void> _backfillMergedRowsFromPreviewPropertyTable(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, dynamic>> reqMap,
  ) async {
    if (rows.isEmpty) return;

    final needPid = <String>{};
    for (final r in rows) {
      final rid = _listingRequestIdForImageBackfill(r);
      if (rid.isEmpty) continue;
      final req = reqMap[rid];
      final pid = (req?['preview_property_id'] ?? '').toString().trim();
      if (pid.isEmpty) continue;

      final urls = ((r['preview_image_urls'] as List?) ?? const []).isEmpty;
      final title = (r['preview_title'] ?? '').toString().trim().isEmpty;
      final priceEmpty = _mergeNum(r['preview_price']) <= 0;
      final areaEmpty = _mergeNum(r['preview_area']) <= 0;
      final typeEmpty = (r['preview_type'] ?? '').toString().trim().isEmpty;
      final ownerEmpty =
          (r['request_owner_name'] ?? r['preview_owner_name'] ?? '')
              .toString()
              .trim()
              .isEmpty;

      if (urls || title || priceEmpty || areaEmpty || typeEmpty || ownerEmpty) {
        needPid.add(pid);
      }
    }
    if (needPid.isEmpty) return;

    try {
      final data = await _net<List<Map<String, dynamic>>>(() async {
        final raw = await _sb
            .from('properties')
            .select(SupabaseSchemaSelects.propertiesPreviewByRequestId)
            .inFilter('id', needPid.toList());
        return (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }, tag: 'MK_BACKFILL_PROP');

      final byPid = <String, Map<String, dynamic>>{};
      for (final p in data ?? const <Map<String, dynamic>>[]) {
        final id = (p['id'] ?? '').toString().trim();
        if (id.isNotEmpty) byPid[id] = p;
      }
      if (byPid.isEmpty) return;

      final ownerIds = <String>{};
      for (final p in byPid.values) {
        final oid = (p['owner_id'] ?? '').toString().trim();
        if (oid.isNotEmpty) ownerIds.add(oid);
      }
      final profMap = ownerIds.isEmpty
          ? <String, Map<String, dynamic>>{}
          : await _fetchProfilesByUserIds(ownerIds.toList());

      for (final r in rows) {
        final rid = _listingRequestIdForImageBackfill(r);
        if (rid.isEmpty) continue;
        final req = reqMap[rid];
        final pid = (req?['preview_property_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        final pro = byPid[pid];
        if (pro == null) continue;

        final entry = _buildPreviewMapEntryForRequest(
          rid,
          Map<String, dynamic>.from(pro),
        );
        if (entry == null) continue;

        void takeIfEmpty(String key, dynamic ev) {
          if (key == 'preview_image_urls') {
            final rEmpty = ((r[key] as List?) ?? const <dynamic>[]).isEmpty;
            final eList = (ev as List?) ?? const <dynamic>[];
            if (rEmpty && eList.isNotEmpty) r[key] = ev;
            return;
          }
          if (key == 'preview_price' || key == 'preview_area') {
            if (_mergeNum(r[key]) <= 0 && _mergeNum(ev) > 0) r[key] = ev;
            return;
          }
          final rs = (r[key] ?? '').toString().trim();
          final es = (ev ?? '').toString().trim();
          if (rs.isEmpty && es.isNotEmpty) r[key] = ev;
        }

        for (final e in entry.entries) {
          takeIfEmpty(e.key, e.value);
        }

        final oid = (pro['owner_id'] ?? '').toString().trim();
        if (oid.isNotEmpty) {
          final nm = _displayNameFromProfile(profMap[oid]);
          if (nm.isNotEmpty) {
            if ((r['request_owner_name'] ?? '').toString().trim().isEmpty) {
              r['request_owner_name'] = nm;
            }
            if ((r['preview_owner_name'] ?? '').toString().trim().isEmpty) {
              r['preview_owner_name'] = nm;
            }
          }
        }
      }
    } catch (_) {}
  }

  // =========================================================
  // Marketer buckets
  // =========================================================
  Future<void> _loadMarketerBuckets({bool force = false}) async {
    if (_isGuest || !_isMarketerRole) return;

    _ensureSubTabControllers();

    _ss(() {
      _loadingMarketing = true;
      _errorMarketing = null;

      if (force) {
        _mkInvites = <Map<String, dynamic>>[];
        _mkOffers = <Map<String, dynamic>>[];
        _mkContracts = <Map<String, dynamic>>[];
        _mkPermits = <Map<String, dynamic>>[];
        _mkPublished = <Map<String, dynamic>>[];
      }
    });

    try {
      final uid = _uid;

      final invitesRaw = (await _net<List<Map<String, dynamic>>>(() async {
            final data = await _sb
                .from('listing_request_invites')
                .select()
                .eq('marketer_id', uid)
                .order('created_at', ascending: false);

            return (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }, tag: 'MK_INVITES')) ??
          <Map<String, dynamic>>[];

      final offersRaw = (await _net<List<Map<String, dynamic>>>(() async {
            final data = await _sb
                .from('listing_offers')
                .select()
                .eq('marketer_id', uid)
                .order('created_at', ascending: false);

            return (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }, tag: 'MK_OFFERS')) ??
          <Map<String, dynamic>>[];

      final contractsRaw = (await _net<List<Map<String, dynamic>>>(() async {
            final data = await _sb
                .from('listing_contracts')
                .select()
                .eq('marketer_id', uid)
                .order('created_at', ascending: false);

            return (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }, tag: 'MK_CONTRACTS')) ??
          <Map<String, dynamic>>[];

      List<Map<String, dynamic>> permitsRaw = <Map<String, dynamic>>[];
      try {
        permitsRaw = (await _net<List<Map<String, dynamic>>>(() async {
              final data = await _sb
                  .from('listing_permits')
                  .select()
                  .eq('marketer_id', uid)
                  .order('created_at', ascending: false);

              return (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }, tag: 'MK_PERMITS')) ??
            <Map<String, dynamic>>[];
      } catch (e) {
        if (kDebugMode) {
          print('[DBG][MK_PERMITS] ERR $e');
        }
        permitsRaw = <Map<String, dynamic>>[];
      }

      if (kDebugMode) {
        print('[DBG][MK_INVITES] ${invitesRaw.length}');
        print('[DBG][MK_OFFERS] ${offersRaw.length}');
        print('[DBG][MK_CONTRACTS] ${contractsRaw.length}');
        print('[DBG][MK_PERMITS] ${permitsRaw.length}');
      }

      final requestIds = <String>{
        ..._extractRequestIdsFromRows(invitesRaw),
        ..._extractRequestIdsFromRows(offersRaw),
        ..._extractRequestIdsFromRows(contractsRaw),
        ..._extractRequestIdsFromRows(permitsRaw),
      }.toList();

      // فشل جلب listing_requests (مثلاً 500 من RLS) لا يعطّل كل التبويبات؛ نكمل بدمج الدعوة/العرض فقط.
      Map<String, Map<String, dynamic>> reqMap =
          <String, Map<String, dynamic>>{};
      try {
        reqMap = await _fetchListingRequestsMap(requestIds);
      } catch (e) {
        if (kDebugMode) {
          print('[DBG][REQ_LOOKUP] ERR (continuing with empty req map) $e');
        }
      }

      final ownerIdsForNames = reqMap.values
          .map(
            (r) => (r['request_owner_id'] ?? r['owner_id'] ?? '')
                .toString()
                .trim(),
          )
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (ownerIdsForNames.isNotEmpty) {
        final profMap = await _fetchProfilesByUserIds(ownerIdsForNames);
        for (final r in reqMap.values) {
          final oid =
              (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
          if (oid.isEmpty) continue;
          final prof = profMap[oid];
          final nm = _displayNameFromProfile(prof);
          if (nm.isNotEmpty) {
            r['request_owner_name'] = nm;
          }
          final ph = _phoneFromProfile(prof);
          if (ph.isNotEmpty) {
            r['request_owner_phone'] = ph;
          }
          final av = (prof?['avatar_url'] ?? '').toString().trim();
          if (av.isNotEmpty) {
            r['request_owner_avatar_url'] = av;
          }
        }
      }

      final previewPidByReq = <String, String>{};
      for (final id in reqMap.keys) {
        final r = reqMap[id]!;
        final pp = (r['preview_property_id'] ?? '').toString().trim();
        if (pp.isNotEmpty) previewPidByReq[id] = pp;
      }
      final previewMap = await _fetchPreviewPropertiesByRequestIds(
        reqMap.keys.toList(),
        previewPropertyIdByRequestId:
            previewPidByReq.isEmpty ? null : previewPidByReq,
      );

      final permitsFiltered = permitsRaw.where((r) {
        final requestId = (r['request_id'] ?? '').toString().trim();
        if (requestId.isEmpty) return false;

        final req = reqMap[requestId] ?? const <String, dynamic>{};
        final selectedMarketerId =
            (req['selected_marketer_id'] ?? '').toString().trim();

        return selectedMarketerId == uid ||
            (r['marketer_id'] ?? '').toString().trim() == uid;
      }).toList();

      final publishedRows = reqMap.values.where((r) {
        final requestId = (r['id'] ?? '').toString().trim();
        if (requestId.isEmpty) return false;

        final preview = previewMap[requestId];
        if (preview == null) return false;

        final previewPropertyId =
            (preview['preview_property_id'] ?? '').toString().trim();
        if (previewPropertyId.isEmpty) return false;

        final previewWorkflowStage = (preview['preview_workflow_stage'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (previewWorkflowStage != 'published') return false;

        final publishedBy = (preview['preview_published_by_marketer_id'] ?? '')
            .toString()
            .trim();
        if (publishedBy != uid) return false;

        // مضاهاة إضافية: بعد النشر يجب أن تكون مرحلة الطلب published.
        final reqWorkflowStage =
            (r['workflow_stage'] ?? r['request_workflow_stage'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (reqWorkflowStage != 'published') return false;

        return true;
      }).map((r) {
        final requestId = (r['id'] ?? '').toString().trim();
        final preview = previewMap[requestId];

        return <String, dynamic>{
          ...r,
          'id': requestId,
          'request_id': requestId,
          // UI تستخدم status لرسوم الحالة؛ نجعلها منسجمة مع property.
          'status': (preview?['preview_status'] ?? 'published').toString(),
        };
      }).toList();

      final enrichedInvites = invitesRaw.map((inv) {
        final gate = (inv['status'] ?? '').toString().trim();
        final merged = _mergeRequestInfo(
          row: Map<String, dynamic>.from(inv),
          reqMap: reqMap,
          previewMap: previewMap,
        );
        // حالة الدعوة من الجدول — لا تعتمد على status بعد الدمج (قد يتلوث من المعاينة).
        merged['invite_gate_status'] = gate;
        merged['_hubKind'] = 'invite';
        merged['_ui_type'] = 'invite';
        return merged;
      }).toList();

      final invitesDeduped = _dedupeMarketerInvites(enrichedInvites, reqMap);

      for (final r in invitesDeduped) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        invitesDeduped,
        reqMap,
      );

      final enrichedOffers = offersRaw
          .map((r) => _mergeRequestInfo(
                row: Map<String, dynamic>.from(r),
                reqMap: reqMap,
                previewMap: previewMap,
              ))
          .toList();

      for (final r in enrichedOffers) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        enrichedOffers,
        reqMap,
      );

      final offeredPairs = <String>{};
      for (final o in enrichedOffers) {
        if (!_marketerOfferBlocksInviteRound(o, reqMap, uid)) continue;
        final reqId = (o['request_id'] ?? o['listing_request_id'] ?? '')
            .toString()
            .trim();
        if (reqId.isEmpty) continue;
        final roundNo = (o['round_no'] as num?)?.toInt() ??
            (reqMap[reqId]?['marketing_round'] as num?)?.toInt() ??
            1;
        offeredPairs.add('$reqId#$roundNo');
      }
      final invitesVisible = invitesDeduped.where((inv) {
        final reqId = (inv['request_id'] ?? inv['listing_request_id'] ?? '')
            .toString()
            .trim();
        if (reqId.isEmpty) return true;
        final st = ((inv['invite_gate_status'] ?? inv['status']) ?? '')
            .toString()
            .toLowerCase()
            .trim();
        if (st == 'offered' || st == 'accepted' || st == 'withdrawn') {
          return false;
        }
        final roundNo = (inv['round_no'] as num?)?.toInt() ??
            (reqMap[reqId]?['marketing_round'] as num?)?.toInt() ??
            1;
        return !offeredPairs.contains('$reqId#$roundNo');
      }).toList();

      final enrichedContracts = contractsRaw
          .map((r) => _mergeRequestInfo(
                row: Map<String, dynamic>.from(r),
                reqMap: reqMap,
                previewMap: previewMap,
              ))
          .toList();

      for (final r in enrichedContracts) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        enrichedContracts,
        reqMap,
      );

      final enrichedPermits = permitsFiltered
          .map((r) => _mergeRequestInfo(
                row: Map<String, dynamic>.from(r),
                reqMap: reqMap,
                previewMap: previewMap,
              ))
          .toList();

      for (final r in enrichedPermits) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      final contractPdfByRequestId = <String, String>{};
      for (final c in contractsRaw) {
        final rid = (c['request_id'] ?? '').toString().trim();
        final url = (c['contract_pdf_url'] ?? '').toString().trim();
        if (rid.isNotEmpty && url.isNotEmpty) {
          contractPdfByRequestId[rid] = url;
        }
      }
      for (final r in enrichedPermits) {
        final rid = (r['request_id'] ?? '').toString().trim();
        final u = contractPdfByRequestId[rid];
        if (u != null && u.isNotEmpty) {
          r['contract_pdf_url'] = u;
        }
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        enrichedPermits,
        reqMap,
      );

      final enrichedPublished = publishedRows
          .map((r) => _mergeRequestInfo(
                row: Map<String, dynamic>.from(r),
                reqMap: reqMap,
                previewMap: previewMap,
              ))
          .toList();

      for (final r in enrichedPublished) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        enrichedPublished,
        reqMap,
      );

      final offersVisible = enrichedOffers
          .where((o) => !_marketerOfferExcludedFromOffersList(o, reqMap, uid))
          .toList();

      await _backfillOwnerRequestCoverImagesFromDb(invitesDeduped);
      await _backfillOwnerRequestCoverImagesFromDb(offersVisible);
      await _backfillOwnerRequestCoverImagesFromDb(enrichedContracts);
      await _backfillOwnerRequestCoverImagesFromDb(enrichedPermits);
      await _backfillOwnerRequestCoverImagesFromDb(enrichedPublished);

      if (!mounted) return;

      _ss(() {
        _mkInvites = invitesVisible;
        _mkOffers = offersVisible;
        _mkContracts = enrichedContracts;
        _mkPermits = enrichedPermits;
        _mkPublished = enrichedPublished;
      });
    } catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        print('[DBG][MARKETING_LOAD] ERR $e');
      }

      _ss(() {
        _errorMarketing = e.toString();
      });
    } finally {
      if (!mounted) return;
      _ss(() {
        _loadingMarketing = false;
      });
    }
  }
}
