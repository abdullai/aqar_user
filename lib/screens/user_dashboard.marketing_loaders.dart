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

/// كل عروض الجولة الحالية «معلّقة» وانتهت [expires_at] — حتى لو بقي status `submitted` قبل تشغيل cron.
Map<String, bool> _ownerOffersAllExpiredByDeadlineMap({
  required List<Map<String, dynamic>> offerRows,
  required Map<String, Map<String, dynamic>> requestRowsById,
}) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final o in offerRows) {
    final rid = (o['request_id'] ?? '').toString().trim();
    if (rid.isEmpty) continue;
    grouped.putIfAbsent(rid, () => []).add(o);
  }
  final out = <String, bool>{};
  final now = DateTime.now().toUtc();
  for (final e in grouped.entries) {
    final req = requestRowsById[e.key];
    final round = (req?['marketing_round'] as num?)?.toInt() ?? 1;
    final pending = e.value.where((o) {
      final rn = (o['round_no'] as num?)?.toInt() ?? 1;
      if (rn != round) return false;
      final st = (o['status'] ?? '').toString().toLowerCase().trim();
      return const {'submitted', 'pending', ''}.contains(st);
    }).toList();
    if (pending.isEmpty) {
      out[e.key] = false;
      continue;
    }
    final allPast = pending.every((o) {
      final st = (o['status'] ?? '').toString().toLowerCase().trim();
      if (const {
        'expired',
        'offer_expired',
        'deadline_passed',
        'timed_out',
        'no_action',
        'inactive_72h',
      }.contains(st)) {
        return true;
      }
      final exp =
          DateTime.tryParse((o['expires_at'] ?? '').toString())?.toUtc();
      if (exp != null) {
        return !exp.isAfter(now);
      }
      final created =
          DateTime.tryParse((o['created_at'] ?? '').toString())?.toUtc();
      if (created == null) return false;
      return now.isAfter(created.add(const Duration(hours: 72)));
    });
    out[e.key] = allPast;
  }
  return out;
}

/// طلب في `waiting_marketers` وله عروض سابقة لكن لا عرض نشط في الجولة الحالية
/// (منتهٍ/مرفوض/جولة قديمة) — يحتاج إعادة طرح من المالك أو تقديماً جديداً.
Map<String, bool> _ownerOffersNeedRelistMap({
  required List<Map<String, dynamic>> offerRows,
  required Map<String, Map<String, dynamic>> requestRowsById,
}) {
  final out = <String, bool>{};
  for (final entry in requestRowsById.entries) {
    final rid = entry.key;
    final req = entry.value;
    final stage =
        (req['workflow_stage'] ?? '').toString().toLowerCase().trim();
    if (stage != 'waiting_marketers') {
      out[rid] = false;
      continue;
    }
    final round = (req['marketing_round'] as num?)?.toInt() ?? 1;
    final forReq = offerRows
        .where((o) => (o['request_id'] ?? '').toString().trim() == rid)
        .toList();
    if (forReq.isEmpty) {
      out[rid] = false;
      continue;
    }
    final hasLiveInRound = forReq.any((o) {
      final rn = (o['round_no'] as num?)?.toInt() ?? 1;
      if (rn != round) return false;
      final st = (o['status'] ?? '').toString().toLowerCase().trim();
      return const {'submitted', 'pending', ''}.contains(st);
    });
    out[rid] = !hasLiveInRound;
  }
  return out;
}

void _applyOfferDeadlineExpiryFlags(
  Iterable<Map<String, dynamic>> rows,
  Map<String, bool> expiredByRequestId,
) {
  for (final r in rows) {
    final rid =
        (r['request_id'] ?? r['listing_request_id'] ?? '').toString().trim();
    if (rid.isEmpty) continue;
    r['_owner_offers_all_expired_by_deadline'] =
        expiredByRequestId[rid] ?? false;
  }
}

/// بعد إعادة طرح الطلب لجولة أعلى: يظهر للمسوّق شارة أنه قدّم عرضاً في جولة سابقة.
void _annotateMarketerInvitesPriorRoundOfferFlag(
  List<Map<String, dynamic>> invites,
  List<Map<String, dynamic>> allOffersForRequests,
  Map<String, Map<String, dynamic>> reqMap,
  String marketerUid,
) {
  if (invites.isEmpty) return;
  final uid = marketerUid.trim();
  if (uid.isEmpty) return;
  for (final inv in invites) {
    final reqId =
        (inv['request_id'] ?? inv['listing_request_id'] ?? '').toString().trim();
    if (reqId.isEmpty) {
      inv['_hub_prior_round_marketer_offer'] = false;
      continue;
    }
    final req = reqMap[reqId];
    final curRound = (req?['marketing_round'] as num?)?.toInt() ?? 1;
    if (curRound <= 1) {
      inv['_hub_prior_round_marketer_offer'] = false;
      continue;
    }
    final prior = allOffersForRequests.any((o) {
      final rid = (o['request_id'] ?? '').toString().trim();
      if (rid != reqId) return false;
      if ((o['marketer_id'] ?? '').toString().trim() != uid) return false;
      final rn = (o['round_no'] as num?)?.toInt() ?? 1;
      if (rn >= curRound) return false;
      final st = (o['status'] ?? '').toString().toLowerCase().trim();
      if (st == 'withdrawn' || st == 'cancelled') return false;
      return true;
    });
    inv['_hub_prior_round_marketer_offer'] = prior;
  }
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
  // v8: العرض الخاسر بعد اختيار مسوّق آخر — يَختفي من قائمة هذا المسوّق.
  final lostAt = (o['lost_at'] ?? '').toString().trim();
  final status = (o['status'] ?? '').toString().toLowerCase().trim();
  if (lostAt.isNotEmpty || status == 'lost') return true;

  // cancelled/withdrawn/rejected تبقى في المصدر لتظهر في «مفسوخ/ملغى»؛
  // تبويب عروضي يستبعدها عبر فلتر التبويب.

  final reqId =
      (o['request_id'] ?? o['listing_request_id'] ?? '').toString().trim();
  if (reqId.isNotEmpty) {
    final req = reqMap[reqId];
    final selected = (req?['selected_marketer_id'] ?? '').toString().trim();
    if (selected.isNotEmpty && selected != marketerUid) {
      // إن كان العرض ملغى/مرفوضاً نُبقيه للمفسوخ؛ وإلا نخفيه كخاسر.
      if (!const {
        'owner_rejected',
        'rejected',
        'declined',
        'withdrawn',
        'cancelled',
      }.contains(status)) {
        return true;
      }
    }

    final stage =
        (req?['workflow_stage'] ?? '').toString().toLowerCase().trim();
  // بعد انتهاء مهلة المالك: أبقِ عرض هذا المسوّق ليظهر في «بدون إجراء 72».
    if (const {'owner_action_required', 'inactive_72h', 'inactive72h'}
        .contains(stage)) {
      final offerMid = (o['marketer_id'] ?? '').toString().trim();
      if (offerMid == marketerUid) return false;
      final prev =
          (req?['prev_selected_marketer_id'] ?? '').toString().trim();
      if (prev == marketerUid) return false;
      final os = (o['status'] ?? '').toString().toLowerCase().trim();
      if (const {'owner_accepted', 'selected', 'approved'}
          .contains(os)) {
        return prev.isNotEmpty && prev != marketerUid;
      }
      return true;
    }
  }

  return false;
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
      if (oid == null || oid.isEmpty) {
        await OrgPermissionManager.clearUser(uid);
        return (isOwner: false, permissions: null);
      }
      isOwner = ctx?['is_owner'] == true;
      final p = ctx?['permissions'];
      if (p is Map) {
        permissions = Map<String, dynamic>.from(
          p.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      await OrgPermissionManager.cacheForUser(
        uid,
        permissions,
        isOwner: isOwner,
      );
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
        _subscriptionMenuBadge = 0;
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
          final vs = (fb['verification_status'] ?? '').toString();
          data = {
            'account_type': (fb['account_type'] ?? 'user').toString().trim(),
            'verified': isProfileVerificationComplete(vs),
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
      unawaited(_refreshOrgJoinRequestBadge());
      unawaited(_refreshSubscriptionMenuBadge());
      _ensureOrgJoinBadgePolling();
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
          final vs = (fb['verification_status'] ?? '').toString();
          final orgFlags = await _fetchOrgMembershipNavFlags(_uid);
          if (!mounted) return;
          _ss(() {
            _accountType = (fb['account_type'] ?? 'user').toString().trim();
            if (_accountType.isEmpty) _accountType = 'user';
            _verified = isProfileVerificationComplete(vs);
            _accountRoleLoaded = true;
            _orgNavResolved = true;
            _orgNavIsOwner = orgFlags.isOwner;
            _orgMembershipPermissions = orgFlags.permissions;
            if (!_showBottomNavCart && _tabIndex == 3) {
              _tabIndex = 0;
            }
          });
          _ensureSubTabControllers();
          unawaited(_refreshOrgJoinRequestBadge());
          unawaited(_refreshSubscriptionMenuBadge());
          _ensureOrgJoinBadgePolling();
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
      unawaited(_refreshOrgJoinRequestBadge());
      unawaited(_refreshSubscriptionMenuBadge());
      _ensureOrgJoinBadgePolling();
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
    } finally {
      if (kIsWeb && mounted && !_accountRoleLoaded) {
        _ss(() {
          _accountRoleLoaded = true;
          _orgNavResolved = true;
        });
      }
    }
  }

  // =========================================================
  // Tab controllers
  // =========================================================
  void _disposeTabControllerLater(TabController? ctrl) {
    if (ctrl == null) return;
    // لا تُتلف أثناء البناء — TabBar/AnimatedBuilder ما زالا مربوطين بالمرجع.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ctrl.dispose();
      } catch (_) {}
    });
  }

  void _ensureSubTabControllers() {
    if (!mounted) return;

    // استرجع من SharedPreferences آخر تبويب فرعي زاره المستخدم — مرة واحدة فقط.
    if (!_subTabIndicesPrefsRestored) {
      _subTabIndicesPrefsRestored = true;
      unawaited(_restoreSubTabIndicesFromPrefs());
    }

    final bool shouldUseMarketerTabs = _usesMarketerMyPageHub;
    // دائماً جهّز تبويبات المالك: المسوّق قد يملك طلبات طرحها للسوق.
    final bool shouldUseOwnerTabs = true;

    if (shouldUseOwnerTabs) {
      // ويب: لا تتلف كنترولر المسوّق — IndexedStack قد يُبقي شجرة قديمة لحظة.
      // يُتلف في dispose() فقط.

      // الطول الجديد للمالك = 7 (دمج تبويبي «التعاقد» و«التصريح 72 ساعة»).
      const int kOwnerTabsLen = 7;
      if (_ownerTabsCtrl == null ||
          _ownerTabsCtrl!.length != kOwnerTabsLen) {
        final int preserved =
            _ownerTabsCtrl?.index ?? _lastOwnerSubTabIndex;
        final int? oldLen = _ownerTabsCtrl?.length;
        final oldOwner = _ownerTabsCtrl;
        // لا تُصفّر الحقل قبل التبديل — IndexedStack/AnimatedBuilder قد يقرأ null → Null check.
        int mappedPreserved = preserved;
        if (oldLen == 9) {
          if (preserved == 7) {
            mappedPreserved = 6;
          } else if (preserved > 7) {
            mappedPreserved = preserved - 2;
          } else if (preserved >= 3) {
            mappedPreserved = preserved - 1;
          }
        } else if (oldLen == 8) {
          if (preserved >= 3) {
            mappedPreserved = preserved - 1;
          }
        }
        mappedPreserved = mappedPreserved.clamp(0, kOwnerTabsLen - 1);
        final next = TabController(
          length: kOwnerTabsLen,
          vsync: this,
          initialIndex: mappedPreserved,
        );
        _ownerTabsCtrl = next;
        _attachSubTabIndexPersistence(next, isMarketer: false);
        _lastOwnerSubTabIndex = mappedPreserved;
        if (oldOwner != null && !identical(oldOwner, next)) {
          _disposeTabControllerLater(oldOwner);
        }
      } else {
        final idx = _ownerTabsCtrl!.index.clamp(0, kOwnerTabsLen - 1);
        if (_ownerTabsCtrl!.index != idx) {
          _ownerTabsCtrl!.index = idx;
        }
      }
      if (!shouldUseMarketerTabs) return;
    }

    if (shouldUseMarketerTabs) {
      // ويب: أبقِ كنترولر المالك حياً — التبديل owner↔marketer لا يتلف أثناء البناء.

      // الطول = 7 (سوق، عروض، تعاقد، تصريح 72، منشور، بدون إجراء 72، مفسوخ).
      const int kMarketerTabsLen = 7;
      if (_marketerTabsCtrl == null ||
          _marketerTabsCtrl!.length != kMarketerTabsLen) {
        final int preservedIndex =
            _marketerTabsCtrl?.index ?? _lastMarketerSubTabIndex;
        final int? oldLen = _marketerTabsCtrl?.length;
        final oldMarketer = _marketerTabsCtrl;
        // تبديل ذري: لا null وسط البناء (كان يسبب Null check متكرر على الويب).
        int mappedPreserved = preservedIndex;
        // ترقية من 5 تبويبات (دمج تصريح+منشور) → 7.
        if (oldLen == 5) {
          if (preservedIndex >= 3) {
            mappedPreserved = preservedIndex + 2;
          }
        } else if (oldLen == 6) {
          if (preservedIndex >= 3) {
            mappedPreserved = preservedIndex + 1;
          }
        }
        mappedPreserved = mappedPreserved.clamp(0, kMarketerTabsLen - 1);
        final next = TabController(
          length: kMarketerTabsLen,
          vsync: this,
          initialIndex: mappedPreserved,
        );
        _marketerTabsCtrl = next;
        _attachSubTabIndexPersistence(next, isMarketer: true);
        _lastMarketerSubTabIndex = mappedPreserved;
        if (oldMarketer != null && !identical(oldMarketer, next)) {
          _disposeTabControllerLater(oldMarketer);
        }
      } else {
        final idx = _marketerTabsCtrl!.index.clamp(0, kMarketerTabsLen - 1);
        if (_marketerTabsCtrl!.index != idx) {
          _marketerTabsCtrl!.index = idx;
        }
        _lastMarketerSubTabIndex = idx;
      }
    }

    // شريط كمسوّق/كمعلن: كنترولر ثابت الطول (2) — يُنشأ مرة ولا يُصفَّر وسط البناء.
    if (shouldUseMarketerTabs) {
      _ensureMarketerPublisherRoleTabsCtrl();
    }
  }

  void _ensureMarketerPublisherRoleTabsCtrl() {
    if (!mounted) return;
    final want = _marketerPublisherHubMode.clamp(0, 1);
    if (_marketerPublisherRoleTabsCtrl != null) {
      final c = _marketerPublisherRoleTabsCtrl!;
      if (c.index != want && !c.indexIsChanging) {
        c.index = want;
      }
      return;
    }
    final next = TabController(
      length: 2,
      vsync: this,
      initialIndex: want,
    );
    next.addListener(() {
      final c = _marketerPublisherRoleTabsCtrl;
      if (c == null || c.indexIsChanging) return;
      if (_marketerPublisherHubMode == c.index) return;
      if (!mounted) return;
      setState(() => _marketerPublisherHubMode = c.index);
      if (c.index == 1) {
        unawaited(_loadOwnerRequestsBuckets(force: false, silent: true));
      }
    });
    _marketerPublisherRoleTabsCtrl = next;
  }

  /// مزامنة وضع كمسوّق/كمعلن مع شريط التبويب (للروابط العميقة وتحديثات الدلاء).
  void _setMarketerPublisherHubMode(int mode, {bool animate = false}) {
    final m = mode.clamp(0, 1);
    _ensureMarketerPublisherRoleTabsCtrl();
    if (_marketerPublisherHubMode != m) {
      _marketerPublisherHubMode = m;
    }
    final c = _marketerPublisherRoleTabsCtrl;
    if (c != null && c.index != m) {
      if (animate) {
        c.animateTo(m);
      } else {
        c.index = m;
      }
    }
  }

  /// عند فتح صفحتي: ارجع لأول تبويب فرعي (يمين في العربية).
  void _focusMyPageFirstSubTab() {
    _lastOwnerSubTabIndex = 0;
    _lastMarketerSubTabIndex = 0;
    try {
      final o = _ownerTabsCtrl;
      if (o != null && o.length > 0 && o.index != 0) {
        o.index = 0;
      }
    } catch (_) {}
    try {
      final m = _marketerTabsCtrl;
      if (m != null && m.length > 0 && m.index != 0) {
        m.index = 0;
      }
    } catch (_) {}
    unawaited(_persistSubTabIndex(isMarketer: false, index: 0));
    unawaited(_persistSubTabIndex(isMarketer: true, index: 0));
  }

  /// Listener موحّد على [TabController] لحفظ آخر تبويب فرعي في الذاكرة + التخزين الدائم.
  void _attachSubTabIndexPersistence(
    TabController controller, {
    required bool isMarketer,
  }) {
    controller.addListener(() {
      // أثناء التبديل المتحرّك يُطلق listener عدة مرات؛ احفظ القيمة النهائية فقط.
      if (controller.indexIsChanging) return;
      final idx = controller.index;
      if (isMarketer) {
        if (_lastMarketerSubTabIndex == idx) return;
        _lastMarketerSubTabIndex = idx;
      } else {
        if (_lastOwnerSubTabIndex == idx) return;
        _lastOwnerSubTabIndex = idx;
      }
      unawaited(_persistSubTabIndex(isMarketer: isMarketer, index: idx));
      // إعادة بناء الواجهة بحيث تنعكس قرارات اعتمدت على التبويب الفرعي الحالي
      // (مثل كشف/تمويه رقم جوّال المالك للمسوّق داخل تبويب «تصاريح 72 ساعة»).
      if (mounted) setState(() {});
    });
  }

  Future<void> _restoreSubTabIndicesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getInt(MarketingStateMixin._kPrefOwnerSubTabIndex);
      final marketer = prefs.getInt(MarketingStateMixin._kPrefMarketerSubTabIndex);
      if (!mounted) return;
      if (owner != null) {
        _lastOwnerSubTabIndex = owner.clamp(0, 8);
        final c = _ownerTabsCtrl;
        if (c != null && c.length == 9) {
          final clamped = owner.clamp(0, 8);
          if (c.index != clamped) {
            try {
              c.index = clamped;
            } catch (_) {}
          }
        }
      }
      if (marketer != null) {
        _lastMarketerSubTabIndex = marketer.clamp(0, 6);
        final c = _marketerTabsCtrl;
        if (c != null && c.length == 7) {
          final clamped = marketer.clamp(0, 6);
          if (c.index != clamped) {
            try {
              c.index = clamped;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _persistSubTabIndex({
    required bool isMarketer,
    required int index,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        isMarketer
            ? MarketingStateMixin._kPrefMarketerSubTabIndex
            : MarketingStateMixin._kPrefOwnerSubTabIndex,
        index,
      );
    } catch (_) {}
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

  /// إعلان/طلب بدون رخصة REGA نشره المسوّق نفسه — لا يظهر له في «السوق العقاري».
  bool _isMarketerOwnNoLicenseMarketRow(
    Map<String, dynamic> row,
    String uid,
  ) {
    if (uid.isEmpty) return false;
    final pub =
        (row['preview_published_by_marketer_id'] ?? '').toString().trim();
    final owner =
        (row['owner_id'] ?? row['request_owner_id'] ?? '').toString().trim();
    if (pub != uid && owner != uid) return false;
    if (row['market_without_rega_license'] == true ||
        row['no_rega_ad_license'] == true ||
        row['no_license_market_consent'] == true) {
      return true;
    }
    final payload = _mergedJsonPayloadForRow(row);
    return payload['market_without_rega_license'] == true ||
        payload['no_rega_ad_license'] == true ||
        payload['no_license_market_consent'] == true;
  }

  /// صف مؤهل لتبويب «السوق العقاري» فقط: بانتظار مسوّقين وبدون مسوّق مختار.
  bool _isMarketerOpenMarketEligibleRow(
    Map<String, dynamic> row, {
    String? uid,
  }) {
    final id = (uid ?? _uid).trim();
    final stage = (row['workflow_stage'] ??
            row['request_workflow_stage'] ??
            row['preview_workflow_stage'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    if (stage != 'waiting_marketers') return false;
    final selected = (row['selected_marketer_id'] ??
            row['request_selected_marketer_id'] ??
            '')
        .toString()
        .trim();
    if (selected.isNotEmpty) return false;
    if (id.isNotEmpty && _isMarketerOwnNoLicenseMarketRow(row, id)) {
      return false;
    }
    final owner = (row['owner_id'] ?? row['request_owner_id'] ?? '')
        .toString()
        .trim();
    if (id.isNotEmpty && owner == id) return false;
    final prevSelected =
        (row['prev_selected_marketer_id'] ?? '').toString().trim();
    final allowRetry = row['allow_previous_marketers_retry'] == true ||
        row['allow_previous_marketers_retry'] == 1 ||
        (row['allow_previous_marketers_retry'] is String &&
            const {'true', 't', '1', 'yes'}.contains(
              (row['allow_previous_marketers_retry'] as String).toLowerCase(),
            ));
    if (id.isNotEmpty && prevSelected == id && !allowRetry) return false;
    return true;
  }

  /// المعلن وافق على إظهار جواله من بطاقة السوق قبل اختيار مسوّق.
  bool _listingRevealsOwnerPhoneFromMarket(Map<String, dynamic> row) {
    bool truthy(dynamic v) =>
        v == true ||
        v == 1 ||
        (v is String &&
            const {'true', 't', '1', 'yes'}.contains(v.toLowerCase()));
    for (final k in const [
      'show_owner_phone_on_market',
      'reveal_phone_from_market',
      'contact_visible_in_market',
      'show_phone_in_market',
    ]) {
      if (truthy(row[k])) return true;
    }
    final payload = _mergedJsonPayloadForRow(row);
    for (final k in const [
      'show_owner_phone_on_market',
      'reveal_phone_from_market',
      'contact_visible_in_market',
      'show_phone_in_market',
    ]) {
      if (truthy(payload[k])) return true;
    }
    return false;
  }

  void _stripOwnerPhoneUnlessMarketReveal(Map<String, dynamic> row) {
    if (_listingRevealsOwnerPhoneFromMarket(row)) return;
    for (final k in const [
      'request_owner_phone',
      'preview_owner_phone',
      'owner_phone',
      'contact_phone',
      'phone',
      'mobile',
      'owner_mobile',
    ]) {
      row[k] = '';
    }
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

    for (final flag in const [
      'market_without_rega_license',
      'no_rega_ad_license',
      'no_license_market_consent',
    ]) {
      if (payload[flag] == true) row[flag] = true;
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
  Future<void> _loadOwnerRequestsBuckets({
    bool force = false,
    bool silent = false,
  }) async {
    // المسوّق/المكتب قد يكون أيضاً مالك طلبات طرحها للسوق — نحمّل دلاء المالك دائماً لغير الضيوف.
    if (_isGuest) return;

    _ensureSubTabControllers();

    // مع force: لا تُعد رسم الكاش القديم — كان يُبقي البطاقة في تبويب قديم بعد الموافقة/الإعادة.
    var hadOwnerCache = false;
    if (!force) {
      try {
        final uid = _sb.auth.currentUser?.id ?? '';
        final cached = MarketingBucketsCache.instance.readOwner(uid);
        if (cached != null) {
          hadOwnerCache = true;
          _ss(() {
            _ownerListingRequests = cached.rows;
            _loadingOwnerRequests = false;
          });
        }
      } catch (_) {}
    } else {
      MarketingBucketsCache.instance.invalidateOwner(
        _sb.auth.currentUser?.id ?? '',
      );
    }

    _ss(() {
      if (!silent) {
        _loadingOwnerRequests =
            !hadOwnerCache && _ownerListingRequests.isEmpty;
        // لا تمسح الصفوف عند force — حدّث في الخلفية.
      }
    });

    try {
      try {
        await MarketingFlowService(_sb).syncExpiredContractCreationWindows();
      } catch (_) {}

      final uid = _uid;

      final data = await _net<List<Map<String, dynamic>>>(() async {
        // ويب: حدّ أعلى يمنع عاصفة البطاقات بعد الدخول (كل صلاحيات المالك الفرد).
        var q = _sb
            .from('listing_requests')
            .select(SupabaseSchemaSelects.listingRequestsLookup)
            .eq('owner_id', uid)
            .order('created_at', ascending: false);
        if (kIsWeb) {
          q = q.limit(60);
        }
        final result = await q;

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

      final ownerReqIdsForPdf = merged
          .map((e) => (e['request_id'] ?? e['id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (ownerReqIdsForPdf.isNotEmpty) {
        try {
          final cp = await _net<dynamic>(
            () async => _sb
                .from('listing_contracts')
                .select('request_id,contract_pdf_url')
                .inFilter('request_id', ownerReqIdsForPdf),
            tag: 'OWNER_REQ_CONTRACT_PDF',
          );
          final pdfByReq = <String, String>{};
          for (final e in _asMapList(cp)) {
            final rid = (e['request_id'] ?? '').toString().trim();
            final u = (e['contract_pdf_url'] ?? '').toString().trim();
            if (rid.isNotEmpty && u.isNotEmpty) {
              pdfByReq[rid] = u;
            }
          }
          for (final r in merged) {
            final rid = (r['request_id'] ?? r['id'] ?? '').toString().trim();
            final u = pdfByReq[rid];
            if (u != null && u.isNotEmpty) {
              r['contract_pdf_url'] = u;
            }
          }
        } catch (_) {}
      }

      // تجميع عروض listing_offers النشطة + وجود محادثة (عقار/مباشر) مع مسوّق قدّم عرضاً — لبطاقة «بانتظار المسوقين».
      final reqIdsForAgg = merged
          .map((e) => (e['request_id'] ?? e['id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final pendingByReq = <String, int>{for (final id in reqIdsForAgg) id: 0};
      final marketerIdsByReq = <String, Set<String>>{};
      final reqWithPropChat = <String>{};
      final directChatReq = <String>{};
      var offerDeadlineExpiredByRequest = <String, bool>{};
      var needRelistByReq = <String, bool>{};
      if (reqIdsForAgg.isNotEmpty) {
        final pendingPreviewByReq = <String, List<Map<String, dynamic>>>{};
        try {
          final offRaw = await _net<dynamic>(() async {
            return await _sb
                .from('listing_offers')
                .select(
                    'id,request_id,marketer_id,status,expires_at,round_no,offer_amount,price')
                .inFilter('request_id', reqIdsForAgg);
          }, tag: 'OWNER_OFFER_AGG');
          final offerAggRows = _asMapList(offRaw);
          final nowUtc = DateTime.now().toUtc();
          final priorRejectedByKey = <String, int>{};
          for (final e in offerAggRows) {
            final ridK = (e['request_id'] ?? '').toString().trim();
            final midK = (e['marketer_id'] ?? '').toString().trim();
            if (ridK.isEmpty || midK.isEmpty) continue;
            final stK =
                (e['status'] ?? '').toString().toLowerCase().trim();
            if (!const {'owner_rejected', 'rejected', 'declined'}
                .contains(stK)) {
              continue;
            }
            final key = '$ridK|$midK';
            priorRejectedByKey[key] = (priorRejectedByKey[key] ?? 0) + 1;
          }
          bool isRepeatPendingOffer(Map<String, dynamic> e) {
            final ridK = (e['request_id'] ?? '').toString().trim();
            final midK = (e['marketer_id'] ?? '').toString().trim();
            if (ridK.isEmpty || midK.isEmpty) return false;
            final roundNo = (e['round_no'] as num?)?.toInt() ?? 1;
            if (roundNo > 1) return true;
            return (priorRejectedByKey['$ridK|$midK'] ?? 0) > 0;
          }
          final reqRowById = <String, Map<String, dynamic>>{};
          for (final mr in merged) {
            final id = (mr['request_id'] ?? mr['id'] ?? '').toString().trim();
            if (id.isNotEmpty) reqRowById[id] = mr;
          }
          offerDeadlineExpiredByRequest = _ownerOffersAllExpiredByDeadlineMap(
            offerRows: offerAggRows,
            requestRowsById: reqRowById,
          );
          needRelistByReq = _ownerOffersNeedRelistMap(
            offerRows: offerAggRows,
            requestRowsById: reqRowById,
          );
          for (final e in offerAggRows) {
            final rid = (e['request_id'] ?? '').toString().trim();
            final st = (e['status'] ?? '').toString().toLowerCase().trim();
            if (!const {'submitted', 'pending', ''}.contains(st)) continue;
            final exp =
                DateTime.tryParse((e['expires_at'] ?? '').toString())?.toUtc();
            if (exp != null && !exp.isAfter(nowUtc)) {
              continue;
            }
            pendingByReq[rid] = (pendingByReq[rid] ?? 0) + 1;
            final mid = (e['marketer_id'] ?? '').toString().trim();
            if (mid.isNotEmpty) {
              marketerIdsByReq.putIfAbsent(rid, () => <String>{}).add(mid);
            }
            final oid = (e['id'] ?? '').toString().trim();
            if (oid.isNotEmpty) {
              pendingPreviewByReq.putIfAbsent(rid, () => []).add(
                    Map<String, dynamic>.from({
                      'id': oid,
                      'marketer_id': mid,
                      'offer_price': e['offer_amount'] ?? e['price'],
                      'is_repeat_offer': isRepeatPendingOffer(e),
                    }),
                  );
            }
          }
        } catch (_) {}

        final previewIds = merged
            .map((e) => (e['preview_property_id'] ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        if (previewIds.isNotEmpty) {
          try {
            final convRows = await _net<dynamic>(() async {
              return await _sb
                  .from('conversations')
                  .select('property_id')
                  .eq('kind', 'property')
                  .inFilter('property_id', previewIds)
                  .or('user_id.eq.$uid,counterparty_id.eq.$uid');
            }, tag: 'OWNER_CONV_PROP');
            final pidsHit = <String>{};
            for (final e in _asMapList(convRows)) {
              final pid = (e['property_id'] ?? '').toString().trim();
              if (pid.isNotEmpty) pidsHit.add(pid);
            }
            for (final r in merged) {
              final rid = (r['request_id'] ?? r['id'] ?? '').toString().trim();
              final pp = (r['preview_property_id'] ?? '').toString().trim();
              if (rid.isNotEmpty && pp.isNotEmpty && pidsHit.contains(pp)) {
                reqWithPropChat.add(rid);
              }
            }
          } catch (_) {}
        }

        final allM = marketerIdsByReq.values.expand((s) => s).toSet().toList();
        final peersWithDm = <String>{};
        if (allM.isNotEmpty) {
          try {
            final a = await _net<dynamic>(() async {
              return await _sb
                  .from('conversations')
                  .select('counterparty_id')
                  .eq('kind', 'direct')
                  .eq('user_id', uid)
                  .inFilter('counterparty_id', allM);
            }, tag: 'OWNER_DM_A');
            for (final e in _asMapList(a)) {
              final c = (e['counterparty_id'] ?? '').toString().trim();
              if (c.isNotEmpty) peersWithDm.add(c);
            }
            final b = await _net<dynamic>(() async {
              return await _sb
                  .from('conversations')
                  .select('user_id')
                  .eq('kind', 'direct')
                  .eq('counterparty_id', uid)
                  .inFilter('user_id', allM);
            }, tag: 'OWNER_DM_B');
            for (final e in _asMapList(b)) {
              final c = (e['user_id'] ?? '').toString().trim();
              if (c.isNotEmpty) peersWithDm.add(c);
            }
          } catch (_) {}
        }
        for (final e in marketerIdsByReq.entries) {
          for (final mid in e.value) {
            if (peersWithDm.contains(mid)) {
              directChatReq.add(e.key);
              break;
            }
          }
        }

        for (final r in merged) {
          final rid = (r['request_id'] ?? r['id'] ?? '').toString().trim();
          if (rid.isEmpty) continue;
          r['_owner_pending_offers_count'] = pendingByReq[rid] ?? 0;
          r['_owner_offers_all_expired_by_deadline'] =
              offerDeadlineExpiredByRequest[rid] ?? false;
          r['_owner_offers_need_relist'] = needRelistByReq[rid] ?? false;
          r['_owner_has_marketer_chat'] = reqWithPropChat.contains(rid) ||
              directChatReq.contains(rid);
          r['_owner_pending_offers_preview'] =
              List<Map<String, dynamic>>.from(
                  pendingPreviewByReq[rid] ?? const <Map<String, dynamic>>[]);
          r['_owner_has_repeat_pending_offer'] =
              (pendingPreviewByReq[rid] ?? const <Map<String, dynamic>>[])
                  .any((o) => o['is_repeat_offer'] == true);
        }
      }

      if (!mounted) return;

      _ss(() {
        _ownerListingRequests = merged;
      });

      unawaited(_refreshExhaustedOpportunityIds(
        merged.map((r) => (r['request_id'] ?? r['id'] ?? '').toString()),
      ));

      // v8 (perf): احفظ في الكاش الذاكرة لجلسة التطبيق الحالية.
      try {
        MarketingBucketsCache.instance.saveOwner(uid: uid, rows: merged);
      } catch (_) {}
    } catch (_) {
      // الخطأ يحفظ القائمة كما هي (لا نعرض رسالة بصرية حاليًا)؛ نحرص فقط على
      // رفع علم التحميل في `finally` كي لا تبقى التبويبات على «جارٍ التحميل…».
    } finally {
      if (!silent) {
        _loadingOwnerRequests = false;
      }
      if (mounted) _ss(() {});
    }
  }

  Future<void> _backfillOwnerDisplayNamesOnMarketerRows({
    required Map<String, Map<String, dynamic>> reqMap,
    required Map<String, Map<String, dynamic>> previewMap,
    required List<Map<String, dynamic>> invitesRaw,
    required List<Map<String, dynamic>> offersRaw,
    required List<Map<String, dynamic>> contractsRaw,
  }) async {
    final ownerIds = <String>{};
    for (final r in reqMap.values) {
      final oid =
          (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
      if (oid.isNotEmpty) ownerIds.add(oid);
    }
    for (final p in previewMap.values) {
      final oid = (p['owner_id'] ?? '').toString().trim();
      if (oid.isNotEmpty) ownerIds.add(oid);
    }
    for (final row in [...invitesRaw, ...offersRaw, ...contractsRaw]) {
      final oid = (row['owner_id'] ?? '').toString().trim();
      if (oid.isNotEmpty) ownerIds.add(oid);
    }
    if (ownerIds.isEmpty) return;

    final profMap = await _fetchProfilesByUserIds(ownerIds.toList());
    void applyName(String oid, Map<String, dynamic> target) {
      if (oid.isEmpty) return;
      final nm = _displayNameFromProfile(profMap[oid]);
      if (nm.isEmpty) return;
      if ((target['request_owner_name'] ?? '').toString().trim().isEmpty) {
        target['request_owner_name'] = nm;
      }
      if ((target['preview_owner_name'] ?? '').toString().trim().isEmpty) {
        target['preview_owner_name'] = nm;
      }
      if ((target['request_owner_full_name'] ?? '').toString().trim().isEmpty) {
        target['request_owner_full_name'] = nm;
      }
      if ((target['owner_full_name'] ?? '').toString().trim().isEmpty) {
        target['owner_full_name'] = nm;
      }
    }

    for (final r in reqMap.values) {
      final oid =
          (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
      applyName(oid, r);
    }
    for (final p in previewMap.values) {
      final oid = (p['owner_id'] ?? '').toString().trim();
      applyName(oid, p);
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
listing_request_public_code,
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
      'preview_listing_public_code':
          (row['listing_public_code'] ?? '').toString().trim(),
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
  String _mergeNonEmptyStr(dynamic a, dynamic b, [dynamic c, dynamic d, dynamic e]) {
    for (final x in [a, b, c, d, e]) {
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
        req['request_owner_full_name'],
        preview['preview_owner_name'],
        preview['preview_owner_full_name'],
        row['request_owner_name'],
      ),
      'preview_owner_name': _mergeNonEmptyStr(
        req['request_owner_name'],
        req['request_owner_full_name'],
        preview['preview_owner_name'],
        preview['preview_owner_full_name'],
      ),
      'request_owner_full_name': _mergeNonEmptyStr(
        req['request_owner_full_name'],
        req['request_owner_name'],
        preview['preview_owner_full_name'],
        preview['preview_owner_name'],
      ),
      'request_owner_id': _mergeNonEmptyStr(
        req['owner_id'],
        req['request_owner_id'],
        row['owner_id'],
        row['request_owner_id'],
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
  Future<void> _loadMarketerBuckets({
    bool force = false,
    bool silent = false,
  }) async {
    if (_isGuest || !_usesMarketerMyPageHub) return;

    _ensureSubTabControllers();

    // مع force: لا تُعد رسم الكاش القديم (يمنع بقاء البطاقة في تبويب خاطئ).
    var hadCache = false;
    if (!force) {
      try {
        final uid = _sb.auth.currentUser?.id ?? '';
        final cached = MarketingBucketsCache.instance.readMarketer(uid);
        if (cached != null) {
          hadCache = true;
          _ss(() {
            _mkInvites = cached.invites;
            _mkOffers = cached.offers;
            _mkContracts = cached.contracts;
            _mkPermits = cached.permits;
            _mkPublished = cached.published;
            _loadingMarketing = false;
          });
        }
      } catch (_) {}
    } else {
      MarketingBucketsCache.instance.invalidateMarketer(
        _sb.auth.currentUser?.id ?? '',
      );
    }

    try {
      _marketerHiddenMarketRequestIds =
          await MarketerMarketVisibilityPrefs.hiddenRequestIds(_uid);
    } catch (_) {
      _marketerHiddenMarketRequestIds = {};
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getStringList('mk_dismissed_cancelled_v1_$_uid') ?? const [];
      _marketerDismissedCancelledIds = raw.toSet();
    } catch (_) {
      _marketerDismissedCancelledIds = {};
    }

    final hasLocalBuckets = hadCache ||
        _mkInvites.isNotEmpty ||
        _mkOffers.isNotEmpty ||
        _mkContracts.isNotEmpty ||
        _mkPermits.isNotEmpty ||
        _mkPublished.isNotEmpty;

    _ss(() {
      if (!silent) {
        // لا تمسح القوائم عند force — حدّث في الخلفية (stale-while-revalidate).
        _loadingMarketing = !hasLocalBuckets;
        _errorMarketing = null;
      }
    });

    try {
      unawaited((() async {
        try {
          await MarketingFlowService(_sb).syncExpiredContractCreationWindows();
        } catch (_) {}
      })());

      final uid = _uid;

      Future<List<Map<String, dynamic>>> loadPermitsSafe() async {
        try {
          return (await _net<List<Map<String, dynamic>>>(() async {
                final data = await _sb
                    .from('listing_permits')
                    .select()
                    .eq('marketer_id', uid)
                    .order('created_at', ascending: false)
                    .limit(kIsWeb ? 40 : 120);

                return (data as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              }, tag: 'MK_PERMITS')) ??
              <Map<String, dynamic>>[];
        } catch (e) {
          if (kDebugMode) {
            print('[DBG][MK_PERMITS] ERR $e');
          }
          return <Map<String, dynamic>>[];
        }
      }

      final mkParallel = await Future.wait<List<Map<String, dynamic>>>([
        () async {
          return (await _net<List<Map<String, dynamic>>>(() async {
                final data = await _sb
                    .from('listing_request_invites')
                    .select()
                    .eq('marketer_id', uid)
                    .order('created_at', ascending: false)
                    .limit(kIsWeb ? 50 : 150);

                return (data as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              }, tag: 'MK_INVITES')) ??
              <Map<String, dynamic>>[];
        }(),
        () async {
          return (await _net<List<Map<String, dynamic>>>(() async {
                final data = await _sb
                    .from('listing_offers')
                    .select()
                    .eq('marketer_id', uid)
                    .order('created_at', ascending: false)
                    .limit(kIsWeb ? 50 : 150);

                return (data as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              }, tag: 'MK_OFFERS')) ??
              <Map<String, dynamic>>[];
        }(),
        () async {
          return (await _net<List<Map<String, dynamic>>>(() async {
                final data = await _sb
                    .from('listing_contracts')
                    .select()
                    .eq('marketer_id', uid)
                    .order('created_at', ascending: false)
                    .limit(kIsWeb ? 40 : 120);

                return (data as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              }, tag: 'MK_CONTRACTS')) ??
              <Map<String, dynamic>>[];
        }(),
        loadPermitsSafe(),
      ]);

      final invitesRaw = mkParallel[0];
      final offersRaw = mkParallel[1];
      final contractsRaw = mkParallel[2];
      final permitsRaw = mkParallel[3];

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
          if (ph.isNotEmpty && _listingRevealsOwnerPhoneFromMarket(r)) {
            r['request_owner_phone'] = ph;
          } else {
            _stripOwnerPhoneUnlessMarketReveal(r);
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

      await _backfillOwnerDisplayNamesOnMarketerRows(
        reqMap: reqMap,
        previewMap: previewMap,
        invitesRaw: invitesRaw,
        offersRaw: offersRaw,
        contractsRaw: contractsRaw,
      );

      var offerDeadlineExpiredByRequest = <String, bool>{};
      var allOffersForRequestIds = <Map<String, dynamic>>[];
      if (requestIds.isNotEmpty) {
        try {
          final allOff = await _net<dynamic>(() async {
            return await _sb
                .from('listing_offers')
                .select('request_id,marketer_id,status,expires_at,round_no')
                .inFilter('request_id', requestIds);
          }, tag: 'MK_ALL_OFFERS_FOR_DEADLINE');
          allOffersForRequestIds = _asMapList(allOff);
          offerDeadlineExpiredByRequest = _ownerOffersAllExpiredByDeadlineMap(
            offerRows: allOffersForRequestIds,
            requestRowsById: reqMap,
          );
        } catch (_) {}
      }

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

      _annotateMarketerInvitesPriorRoundOfferFlag(
        invitesDeduped,
        allOffersForRequestIds,
        reqMap,
        uid,
      );

      for (final r in invitesDeduped) {
        _applyPayloadFallbacksToOwnerRequestRow(r);
      }
      await _backfillMergedRowsFromPreviewPropertyTable(
        invitesDeduped,
        reqMap,
      );
      _applyOfferDeadlineExpiryFlags(
        invitesDeduped,
        offerDeadlineExpiredByRequest,
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

      // لازم لـ [_filterMarketerRowsForTab] تبويب «عروضي» (1) — بدونها تُستبعد كل العروض.
      for (final r in enrichedOffers) {
        r['_hubKind'] = 'offer';
        r['_ui_type'] = 'offer';
      }
      _applyOfferDeadlineExpiryFlags(
        enrichedOffers,
        offerDeadlineExpiredByRequest,
      );
      for (final o in enrichedOffers) {
        final inactive =
            ListingWorkflowUnified.marketerOfferAwaitingOwnerPastDeadline(o) ||
                ListingWorkflowUnified.fromMarketerMergedRow(o) ==
                    ListingWorkflowStage.inactive72h;
        o['_hub_inactive_72h'] = inactive;
      }

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
        if (_marketerHiddenMarketRequestIds.contains(reqId)) return false;
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

      // ويب: ارسم دعوات/عروض فوراً قبل جلب سوق waiting_marketers (غالباً الأبطأ).
      if (kIsWeb && mounted) {
        final offersEarly = enrichedOffers
            .where((o) => !_marketerOfferExcludedFromOffersList(o, reqMap, uid))
            .toList();
        final invitesEarly = invitesVisible
            .where((r) => _isMarketerOpenMarketEligibleRow(r, uid: uid))
            .map((r) {
          final copy = Map<String, dynamic>.from(r);
          _stripOwnerPhoneUnlessMarketReveal(copy);
          return copy;
        }).toList();
        _ss(() {
          _mkInvites = invitesEarly;
          _mkOffers = offersEarly;
          _loadingMarketing = false;
        });
        try {
          MarketingBucketsCache.instance.saveMarketer(
            uid: uid,
            invites: invitesEarly,
            offers: offersEarly,
            contracts: List<Map<String, dynamic>>.from(_mkContracts),
            permits: List<Map<String, dynamic>>.from(_mkPermits),
            published: List<Map<String, dynamic>>.from(_mkPublished),
          );
        } catch (_) {}
        // أعد التنفس للواجهة قبل إكمال الإثراء الثقيل.
        await Future<void>.delayed(Duration.zero);
      }

      // سوق مفتوح: طلبات waiting_marketers لغير صاحب الطلب (مسوّق/مكتب/مؤسسة/شركة).
      // يعتمد على RLS الموسّع (دعوة/عرض أو سوق مفتوح) — يعمل على الويب والجوال.
      List<Map<String, dynamic>> openMarketRequestsRaw =
          const <Map<String, dynamic>>[];
      try {
        openMarketRequestsRaw =
            (await _net<List<Map<String, dynamic>>>(() async {
                  final data = await _sb
                      .from('listing_requests')
                      .select(SupabaseSchemaSelects.listingRequestsLookup)
                      .eq('workflow_stage', 'waiting_marketers')
                      .neq('owner_id', uid)
                      .order('created_at', ascending: false)
                      .limit(200);
                  return (data as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList();
                }, tag: 'MK_OPEN_MARKET_REQS')) ??
                <Map<String, dynamic>>[];
      } catch (e) {
        if (kDebugMode) {
          print('[DBG][MK_OPEN_MARKET_REQS] ERR $e');
        }
        openMarketRequestsRaw = const <Map<String, dynamic>>[];
      }

      // الدعوات المعروضة في الجولة الحالية فقط — حتى لا تَحجب دعوة جولة قديمة
      // ظهور الطلب في «السوق العقاري» بعد رفع marketing_round.
      final existingInviteReqIds = <String>{};
      for (final inv in invitesVisible) {
        final reqId = (inv['request_id'] ?? inv['listing_request_id'] ?? '')
            .toString()
            .trim();
        if (reqId.isEmpty) continue;
        final invRound = (inv['round_no'] as num?)?.toInt() ??
            (reqMap[reqId]?['marketing_round'] as num?)?.toInt() ??
            1;
        final curRound =
            (reqMap[reqId]?['marketing_round'] as num?)?.toInt() ?? 1;
        if (invRound != curRound) continue;
        existingInviteReqIds.add(reqId);
      }

      final openMarketRequestsFiltered = <Map<String, dynamic>>[];
      for (final req in openMarketRequestsRaw) {
        final rid = (req['id'] ?? '').toString().trim();
        if (rid.isEmpty) continue;
        if (_marketerHiddenMarketRequestIds.contains(rid)) continue;
        if (existingInviteReqIds.contains(rid)) continue;
        final selectedMarketerId =
            (req['selected_marketer_id'] ?? '').toString().trim();
        if (selectedMarketerId.isNotEmpty) continue;
        final ownerId = (req['owner_id'] ?? '').toString().trim();
        if (ownerId == uid) continue;
        if (_isMarketerOwnNoLicenseMarketRow(req, uid)) continue;
        // مسوّق سابق مُستثنى عند إعادة السوق بدون منحه فرصة.
        final prevSelected =
            (req['prev_selected_marketer_id'] ?? '').toString().trim();
        final allowRetry = req['allow_previous_marketers_retry'] == true ||
            req['allow_previous_marketers_retry'] == 1 ||
            (req['allow_previous_marketers_retry'] is String &&
                const {'true', 't', '1', 'yes'}.contains(
                  (req['allow_previous_marketers_retry'] as String)
                      .toLowerCase(),
                ));
        if (prevSelected == uid && !allowRetry) continue;
        final roundNo = (req['marketing_round'] as num?)?.toInt() ?? 1;
        if (offeredPairs.contains('$rid#$roundNo')) continue;

        // استبعاد الطلبات التي قدّم المسوّق عرضاً عليها سابقاً مهما كانت حالة العرض،
        // إلا لو كان مسموحاً بإعادة المحاولة (allow_previous_marketers_retry = true).
        if (!allowRetry) {
          final hasLiveOfferThisRound = enrichedOffers.any((o) {
            final oReq = (o['request_id'] ?? o['listing_request_id'] ?? '')
                .toString()
                .trim();
            if (oReq != rid) return false;
            final rn = (o['round_no'] as num?)?.toInt() ?? 1;
            if (rn != roundNo) return false;
            final st = (o['status'] ?? '').toString().toLowerCase().trim();
            return const {'submitted', 'pending', ''}.contains(st);
          });
          if (hasLiveOfferThisRound) continue;
        }

        openMarketRequestsFiltered.add(req);
      }

      if (openMarketRequestsFiltered.isNotEmpty) {
        for (final req in openMarketRequestsFiltered) {
          final rid = (req['id'] ?? '').toString().trim();
          if (rid.isEmpty) continue;
          // لا تكتب فوق صفوف موجودة سابقاً في reqMap.
          reqMap.putIfAbsent(rid, () => Map<String, dynamic>.from(req));
        }

        final openOwnerIds = openMarketRequestsFiltered
            .map((r) => (r['owner_id'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (openOwnerIds.isNotEmpty) {
          try {
            final openProfMap = await _fetchProfilesByUserIds(openOwnerIds);
            for (final r in reqMap.values) {
              final oid =
                  (r['request_owner_id'] ?? r['owner_id'] ?? '')
                      .toString()
                      .trim();
              if (oid.isEmpty) continue;
              if ((r['request_owner_name']?.toString().trim().isNotEmpty ??
                      false) &&
                  (r['request_owner_phone']?.toString().trim().isNotEmpty ??
                      false)) {
                continue;
              }
              final prof = openProfMap[oid];
              final nm = _displayNameFromProfile(prof);
              if (nm.isNotEmpty &&
                  (r['request_owner_name']?.toString().trim().isEmpty ??
                      true)) {
                r['request_owner_name'] = nm;
              }
              final ph = _phoneFromProfile(prof);
              if (_listingRevealsOwnerPhoneFromMarket(r) &&
                  ph.isNotEmpty &&
                  (r['request_owner_phone']?.toString().trim().isEmpty ??
                      true)) {
                r['request_owner_phone'] = ph;
              }
              final av = (prof?['avatar_url'] ?? '').toString().trim();
              if (av.isNotEmpty &&
                  (r['request_owner_avatar_url']
                          ?.toString()
                          .trim()
                          .isEmpty ??
                      true)) {
                r['request_owner_avatar_url'] = av;
              }
            }
          } catch (_) {}
        }

        final openPreviewPidByReq = <String, String>{};
        for (final req in openMarketRequestsFiltered) {
          final rid = (req['id'] ?? '').toString().trim();
          final pp = (req['preview_property_id'] ?? '').toString().trim();
          if (rid.isNotEmpty && pp.isNotEmpty) {
            openPreviewPidByReq[rid] = pp;
          }
        }
        try {
          final openPm = await _fetchPreviewPropertiesByRequestIds(
            openMarketRequestsFiltered
                .map((r) => (r['id'] ?? '').toString().trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            previewPropertyIdByRequestId:
                openPreviewPidByReq.isEmpty ? null : openPreviewPidByReq,
          );
          for (final e in openPm.entries) {
            previewMap.putIfAbsent(e.key, () => e.value);
          }
        } catch (_) {}

        final syntheticInvites = <Map<String, dynamic>>[];
        for (final req in openMarketRequestsFiltered) {
          final rid = (req['id'] ?? '').toString().trim();
          if (rid.isEmpty) continue;
          final synthetic = <String, dynamic>{
            'id': 'open_market_${rid}_$uid',
            'request_id': rid,
            'listing_request_id': rid,
            'marketer_id': uid,
            'invite_gate_status': 'waiting',
            'status': 'waiting',
            'round_no': (req['marketing_round'] as num?)?.toInt() ?? 1,
            'created_at': req['created_at'],
            '_open_market_synthetic': true,
          };
          final merged = _mergeRequestInfo(
            row: synthetic,
            reqMap: reqMap,
            previewMap: previewMap,
          );
          merged['_hubKind'] = 'invite';
          merged['_ui_type'] = 'invite';
          merged['invite_gate_status'] = 'waiting';
          merged['_open_market_synthetic'] = true;
          syntheticInvites.add(merged);
        }

        if (syntheticInvites.isNotEmpty) {
          for (final r in syntheticInvites) {
            _applyPayloadFallbacksToOwnerRequestRow(r);
            _stripOwnerPhoneUnlessMarketReveal(r);
          }
          await _backfillMergedRowsFromPreviewPropertyTable(
            syntheticInvites,
            reqMap,
          );
          await _backfillOwnerRequestCoverImagesFromDb(syntheticInvites);
          invitesVisible.addAll(syntheticInvites);
        }
      }

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

      await Future.wait([
        _backfillOwnerRequestCoverImagesFromDb(invitesDeduped),
        _backfillOwnerRequestCoverImagesFromDb(offersVisible),
        _backfillOwnerRequestCoverImagesFromDb(enrichedContracts),
        _backfillOwnerRequestCoverImagesFromDb(enrichedPermits),
        _backfillOwnerRequestCoverImagesFromDb(enrichedPublished),
      ]);

      if (!mounted) return;

      final invitesForMarketer = invitesVisible
          .where((r) => _isMarketerOpenMarketEligibleRow(r, uid: uid))
          .map((r) {
        final copy = Map<String, dynamic>.from(r);
        _stripOwnerPhoneUnlessMarketReveal(copy);
        return copy;
      }).toList();

      _ss(() {
        _mkInvites = invitesForMarketer;
        _mkOffers = offersVisible;
        _mkContracts = enrichedContracts;
        _mkPermits = enrichedPermits;
        _mkPublished = enrichedPublished;
      });

      unawaited(_refreshExhaustedOpportunityIds([
        ...offersVisible.map((r) => _marketingRequestIdFromRow(r)),
        ...enrichedContracts.map((r) => _marketingRequestIdFromRow(r)),
        ...enrichedPermits.map((r) => _marketingRequestIdFromRow(r)),
      ]));

      // v8 (perf): احفظ النسخة الناجحة في الكاش الذاكرة للجلسة الحالية.
      try {
        MarketingBucketsCache.instance.saveMarketer(
          uid: uid,
          invites: invitesForMarketer,
          offers: offersVisible,
          contracts: enrichedContracts,
          permits: enrichedPermits,
          published: enrichedPublished,
        );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;

      if (kDebugMode) {
        print('[DBG][MARKETING_LOAD] ERR $e');
      }

      _ss(() {
        _errorMarketing = e.toString();
      });
    } finally {
      if (mounted) {
        _ss(() {
          if (!silent) {
            _loadingMarketing = false;
          }
        });
      }
    }
  }
}
