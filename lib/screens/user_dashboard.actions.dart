part of 'user_dashboard.dart';

extension _UserDashboardStateActions on _UserDashboardState {
  // =========================
  // Navigation / actions
  // =========================

  /// يفتح فوق جذر اللوحة فقط (يُبقي AppBar + الشريط السفلي ظاهرين).
  /// ويب وجوال: نفس [Navigator] الداخلي — لا rootNavigator (كان يخفي التبويبات).
  Future<T?> _pushBody<T extends Object?>(Route<T> route) async {
    if (mounted && !_bottomNavSlideVisible) {
      setState(() => _bottomNavSlideVisible = true);
    }
    final nestedTitle = _nestedTitleForRouteSettings(route.settings);
    _nestedTitleStack.add(nestedTitle);
    if (mounted) {
      setState(() => _nestedShellTitle = nestedTitle);
    }
    final nav = _dashboardBodyNavKey.currentState;
    if (nav == null) {
      // احتياط نادر قبل جاهزية المفتاح.
      try {
        return await Navigator.of(context).push<T>(route);
      } finally {
        if (_nestedTitleStack.isNotEmpty) _nestedTitleStack.removeLast();
        if (mounted) {
          setState(() {
            _nestedShellTitle =
                _nestedTitleStack.isEmpty ? null : _nestedTitleStack.last;
          });
          unawaited(_maybeConsumeDashboardTourReplayFromPrefs());
        }
      }
    }
    try {
      return await nav.push<T>(route);
    } finally {
      if (_nestedTitleStack.isNotEmpty) _nestedTitleStack.removeLast();
      if (mounted) {
        setState(() {
          _nestedShellTitle =
              _nestedTitleStack.isEmpty ? null : _nestedTitleStack.last;
        });
        unawaited(_maybeConsumeDashboardTourReplayFromPrefs());
      }
    }
  }

  /// نماذج زر + — دائماً داخل جسم اللوحة (مثل مايو) حتى تبقى التبويبات ظاهرة.
  /// لا تستخدم rootNavigator: كان يغطي الشريط السفلي ويفشل أحياناً بعد إغلاق الورقة.
  Future<T?> _pushPlusForm<T extends Object?>(Route<T> route) async {
    return _pushBody<T>(route);
  }

  /// بعد إغلاق إدارتي: حدّث الشارات فقط — لا [_reloadAll] الثقيل.
  Future<void> _lightRefreshAfterDesk() async {
    if (!mounted) return;
    unawaited(_loadAccountRole());
    unawaited(_loadNotifications());
    if (kIsWeb) {
      unawaited(_ensureMyAdsHubDataLoaded(force: false));
    }
  }

  /// إغلاق مسارات اللوحة مع اعتراض النماذج غير المحفوظة.
  Future<bool> _popBodyRoutesWithFormGuard() async {
    final nav = _dashboardBodyNavKey.currentState;
    if (nav == null || !nav.canPop()) return true;
    final ok = await ActiveFormGuard.instance.confirmLeaveIfNeeded(
      context,
      isAr: _isArabic,
      popFormRoute: () async {
        if (nav.canPop()) nav.pop();
      },
    );
    if (!ok || !mounted) return false;
    nav.popUntil((r) => r.isFirst);
    return true;
  }

  void _readArgsInBuildOnce(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final l = args['lang'];
      if (l is String && l.isNotEmpty && l != widget.lang) {
        // TODO: تحديث اللغة
      }
    }
  }

  /// تنقل جذري إلى شاشة الدخول بعد تسهيل إغلاق القائمة المنبثقة وتجنّب [context]
  /// التالف بعد [signOut] (خصوصاً على الويب).
  Future<void> _navigateRootToLoginAfterLogout() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);

    final keyNav = UserSessionCoordinationService.navigatorKey?.currentState;
    if (keyNav != null) {
      keyNav.pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      return;
    }

    // إن أُزيل [UserDashboard] من الشجرة قبل التنقل (مثلاً بعد signOut على الويب).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UserSessionCoordinationService.navigatorKey?.currentState
          ?.pushNamedAndRemoveUntil('/login', (route) => false);
    });
  }

  /// بعد مغادرة الداشبورد: مسح تفضيلات/دخول سريع (لا يُنفَّذ على المسار الحرج للويب).
  Future<void> _logoutDeferredLocalCleanup() async {
    try {
      await FastLoginService.clearAll().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConfig.prefGuestModeKey);
      await prefs.remove(AppConfig.prefEntryModeKey);
      await prefs.remove(AppConfig.prefGuestLegacyIsGuestKey);
      await prefs.remove(AppConfig.prefGuestLegacyGuestKey);
      await prefs.remove(AppConfig.prefDashboardAdvancedSearchDraftKey);
    } catch (_) {}
    unawaited(
      resetStoredAppearanceForNextSignIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      ),
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _ss(() => _loggingOut = true);
    AuthSignedOutNavigationGuard.enter();

    final uidForCleanup = _uid;

    try {
      if (_isGuest) {
        if (!mounted) return;
        await AppExitNavigation.leaveGuestToEntryChoice(context);
        return;
      }

      InAppNotificationHub.setSessionUsername(null);
      InAppNotificationHub.setSessionUserId(null);
      InAppNotificationHub.dismiss();

      _propertyCache.clear();
      _profileCache.clear();
      _favoriteIds.clear();
      _clearMarketingStateOnLogout();
      SubscriptionService.invalidateSubscriptionCache();

      if (!mounted) return;
      await SafeSignOutService.signOutAndNavigateToLogin(
        context,
        uidForCleanup: uidForCleanup,
        logoutReason: 'user_logout',
      );

      unawaited(_logoutDeferredLocalCleanup());
    } catch (e) {
      if (mounted) {
        _showNotification(
          widget.isAr ? 'خطأ' : 'Error',
          widget.isAr ? 'تعذر تسجيل الخروج: $e' : 'Logout failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) _ss(() => _loggingOut = false);
      AuthSignedOutNavigationGuard.scheduleLeave();
    }
  }

  /// تبويب «إدارتي»: لوحة المنشأة/المسوّق/المعلن الفردي (منفصلة عن زر +).
  Future<void> _openMyDeskNav() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    // افتح إدارتي فوراً — حمّل الدور/التسخين في الخلفية دون انتظار.
    if (!_accountRoleLoaded || !_orgNavResolved) {
      unawaited(_loadAccountRole());
    }
    unawaited(_prefetchMyDeskWarm());

    const deskShellBack = true;

    // مسوّق/مكتب/مؤسسة/شركة/وكالة: لوحة إدارتي الكاملة (أعضاء، فريق، اشتراك، دردشة، …).
    if (AppRoleHelper.isMarketingRole(
            AppRoleHelper.fromAccountType(_accountType)) ||
        AppRoleHelper.isOrgEntity(_accountType)) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/desk/organization'),
          builder: (_) => MyOrganizationScreen(
            lang: widget.lang,
            suppressImpliedLeading: deskShellBack,
            embedAppBar: true,
          ),
        ),
      );
      if (!mounted) return;
      await _lightRefreshAfterDesk();
      return;
    }

    if (AppRoleHelper.isOwnerIndividual(_accountType)) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/desk/owner'),
          builder: (_) => OwnerIndividualDeskPage(
            lang: widget.lang,
            userId: _uid,
            accountType: _accountType,
            suppressImpliedLeading: deskShellBack,
            embedAppBar: true,
          ),
        ),
      );
      if (!mounted) return;
      await _lightRefreshAfterDesk();
      return;
    }

    if (_orgNavIsOwner ||
        AppRoleHelper.orgPermissionsOpenDeskShell(_orgMembershipPermissions)) {
      final ctx = await OrgTeamService(_sb).myOrgContext();
      final oid = ctx?['org_id']?.toString();
      if (oid != null && oid.isNotEmpty) {
        await _pushBody<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/desk/organization'),
            builder: (_) => MyOrganizationScreen(
              lang: widget.lang,
              suppressImpliedLeading: deskShellBack,
              embedAppBar: true,
            ),
          ),
        );
        if (!mounted) return;
        await _lightRefreshAfterDesk();
        return;
      }
    }

    if (mounted) {
      _showNotification(
        widget.isAr ? 'تعذر فتح إدارتي' : 'Could not open desk',
        widget.isAr
            ? 'تحقق من ربط حسابك بالمؤسسة ثم أعد المحاولة.'
            : 'Check your organization link and try again.',
        isError: true,
      );
      _ss(() => _tabIndex = 1);
    }
  }

  /// مسوّق / عضو فريق بصلاحية إضافة: بوابة ترخيص الإعلان + فال ثم [AddPropertyPage].
  bool _needsRegaGateBeforeAddProperty() {
    if (_isMarketingAccountType) return true;
    if (AppRoleHelper.orgPermissionsAllowMiddleNav(_orgMembershipPermissions) &&
        !_orgNavIsOwner &&
        !AppRoleHelper.orgPermissionsOpenDeskShell(_orgMembershipPermissions)) {
      return true;
    }
    return false;
  }

  void _openMarketRequestDetail(
    MarketPropertyRequestRow row, {
    bool autoOpenSubmitOffer = false,
  }) {
    AppHaptics.light();
    unawaited(() async {
      String? oid;
      if (_isMarketingAccountType) {
        oid = await _marketingSubscriptionOrganizationId();
      }
      if (!mounted) return;
      await showMarketRequestHomeSheet(
        context: context,
        row: row,
        isAr: widget.isAr,
        sb: _sb,
        currentUserId: _uid,
        autoOpenSubmitOffer: autoOpenSubmitOffer,
        onDidChange: () {
          unawaited(Future.wait([
            _loadMarketHomeRequests(force: true),
            _loadMyMarketRequestOfferTracking(),
          ]));
        },
        onGuestRequiresAuth: _isGuest ? _showLoginDialog : null,
        onGuestPayOfferUnlock:
            _isGuest ? () => _guestPayUnlockFlow('offer', targetTab: 2) : null,
        onSubscriptionRequiredForOffer: _isGuest
            ? null
            : () => _openSubscriptionsHubForMarketOffer(row.id),
        accountType: _accountType,
        organizationId: oid,
      );
    }());
  }

  /// Paywall → اشتراكات ومدفوعات. يُرجع true إذا عاد المستخدم بصلاحية تقديم عرض.
  Future<bool> _openSubscriptionsHubForMarketOffer(String marketRequestId) async {
    final isMarketing = _isMarketingAccountType;
    await _pushSubscriptionsHubForPaidActionResume(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.submitOffer,
        requestId: marketRequestId,
      ),
      initialIndex: 0,
      marketOfferPlansOnly: isMarketing,
    );
    SubscriptionService.invalidateSubscriptionCache();
    final oid = await _marketingSubscriptionOrganizationId();
    final allow = await IndividualMarketOfferService(_sb).currentAllowance(
      accountType: _accountType,
      organizationId: oid,
    );
    return allow.canSubmitNow;
  }

  /// يفتح خريطة الاستكشاف بإعلانات «صفحتي» فقط (لا تظهر فيها الطلبات
  /// بناءً على المتطلب). تُمرَّر الإعلانات الجاهزة مع عنوان سياق يوضّح
  /// التبويب الذي فُتحت منه الخريطة (مثلاً: «تبويب السوق»، «إعلاناتي»).
  /// يُجَلب من قاعدة البيانات إعلانات منشورة بإحداثيات لإكمال أيّ نقص محتمل.
  Future<void> _openMyPageListingsMap({
    required List<Property> contextProperties,
    required String contextTitle,
  }) async {
    AppHaptics.light();
    var properties = contextProperties
        .where((p) => _hasValidMapCoordinates(p.latitude, p.longitude))
        .toList(growable: false);

    if (!mounted) return;

    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/dashboard/my-page-map'),
        builder: (_) => PropertyMapDiscoveryPage(
          isAr: widget.isAr,
          embedAppBar: true,
          listingsOnly: true,
          contextTitle: contextTitle,
          properties: properties,
          requests: const <MarketPropertyRequestRow>[],
          onOpenProperty: (p) {
            _dashboardBodyNavKey.currentState?.pop();
            unawaited(_openDetails(p));
          },
        ),
      ),
    );
  }

  /// خريطة ذكية من الشريط العلوي:
  ///   • خارج «صفحتي» → خريطة الاكتشاف العامة (إعلانات + طلبات).
  ///   • داخل «صفحتي» → خريطة التبويب الحالي (إعلانات التبويب فقط).
  Future<void> _openSmartAppBarMap() async {
    if (_tabIndex == 1 && !_isGuest) {
      await _openMyPageMapForCurrentSubTab();
      return;
    }
    await _openMapDiscovery();
  }

  Future<void> _openMyPageMapForCurrentSubTab() async {
    _ensureSubTabControllers();
    final ar = widget.isAr;

    if (_isMarketingAccountType) {
      final ctrl = _marketerTabsCtrl;
      if (ctrl == null) {
        await _openMyPageListingsMap(
          contextProperties: _propertiesOwnedOrPublishedByMe(),
          contextTitle: ar ? 'صفحتي' : 'My page',
        );
        return;
      }
      final idx = ctrl.index;
      final ctx = idx == 0
          ? (ar ? 'تبويب السوق' : 'Market tab')
          : idx == 1
              ? (ar ? 'عروضي' : 'My offers')
              : idx == 2
                  ? (ar ? 'تم الموافقة' : 'Approved')
                  : (ar ? 'إعلاناتي' : 'My listings');
      await _openMyPageListingsMap(
        contextProperties: _marketerListingsForCurrentTab(idx),
        contextTitle: ctx,
      );
      return;
    }

    final ctrl = _ownerTabsCtrl;
    final myItems = sortedMineForHub();
    if (ctrl == null) {
      await _openMyPageListingsMap(
        contextProperties: myItems,
        contextTitle: ar ? 'صفحتي' : 'My page',
      );
      return;
    }

    final idx = ctrl.index;
    final ctx = idx == 0
        ? (ar ? 'بانتظار عروض المسوقين' : 'Awaiting marketer offers')
        : idx == 1
            ? (ar ? 'العروض المقدمة' : 'Submitted offers')
            : idx == 2
                ? (ar ? 'بانتظار التصريح' : 'Awaiting permit')
                : idx == 3
                    ? (ar ? 'لم يتخذ إجراء 72 ساعة' : 'No action (72h)')
                    : idx == 4
                        ? (ar ? 'مفسوخ / ملغى' : 'Cancelled / terminated')
                        : idx == 5
                            ? (ar ? 'العقارات المحجوزة' : 'Reserved properties')
                                : (ar ? 'صفقات مكتملة' : 'Completed deals');
    final props = idx == 1
        ? <Property>[]
        : _filterOwnerHubTab(
            myItems,
            _ownerSubTabPropertyBucket(idx),
          );
    await _openMyPageListingsMap(
      contextProperties:
          props.isEmpty ? _propertiesOwnedOrPublishedByMe() : props,
      contextTitle: ctx,
    );
  }

  /// خريطة ذكية للبحث المتقدم — نفس منطق الشريط العلوي.
  Future<void> _openSmartAdvancedSearchMap() async {
    await _openSmartAppBarMap();
  }

  Future<void> _openMapDiscovery() async {
    AppHaptics.light();
    var properties = _all
        .where((p) => _hasValidMapCoordinates(p.latitude, p.longitude))
        .where(propertyEligibleForPublicMap)
        .toList(growable: false);
    var requests = _marketHomeRequests
        .where((r) => _hasValidMapCoordinates(r.latitude, r.longitude))
        .where(marketRequestEligibleForPublicMap)
        .toList(growable: false);

    try {
      final extra = await Future.wait([
        _loadPublishedPropertiesWithCoordinatesForMap(),
        _loadMarketRequestsWithCoordinatesForMap(),
      ]);
      properties = _mergePropertyListsForMap(
        properties,
        extra[0] as List<Property>,
      ).where(propertyEligibleForPublicMap).toList(growable: false);
      requests = _mergeMarketRequestListsForMap(
        requests,
        extra[1] as List<MarketPropertyRequestRow>,
      ).where(marketRequestEligibleForPublicMap).toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP_OPEN] widen fetch: $e');
      }
    }

    if (!mounted) return;

    await _pushBody<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/dashboard/property-map'),
        builder: (_) => PropertyMapDiscoveryPage(
          isAr: widget.isAr,
          embedAppBar: true,
          initialKind: switch (_homeFeedKind) {
            HomeFeedKind.listings => MapDiscoveryKind.listings,
            HomeFeedKind.requests => MapDiscoveryKind.requests,
            HomeFeedKind.all => MapDiscoveryKind.all,
          },
          properties: properties,
          requests: requests,
          requestCoverImageUrl: (r) =>
              ListingMediaUrls.marketRequestCoverNetworkUrl(r, _sb),
          onOpenProperty: (p) {
            _dashboardBodyNavKey.currentState?.pop();
            unawaited(_openDetails(p));
          },
          onOpenRequest: (r) {
            _dashboardBodyNavKey.currentState?.pop();
            _openMarketRequestDetail(r);
          },
        ),
      ),
    );
  }

  /// يفتح تفاصيل طلب السوق من الرئيسية أو من السلة حتى إن لم يعد الطلب في خليط الرئيسية.
  Future<void> _openMarketRequestDetailById(
    String requestId, {
    bool autoOpenSubmitOffer = false,
  }) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return;
    for (final e in _marketHomeRequests) {
      if (e.id == rid) {
        _openMarketRequestDetail(e, autoOpenSubmitOffer: autoOpenSubmitOffer);
        return;
      }
    }
    try {
      final map = await MarketingFlowService(_sb)
          .marketPropertyRequestSnapshotById(rid);
      if (!mounted) return;
      if (map == null) {
        _toast(
          widget.isAr
              ? 'تعذّر تحميل تفاصيل الطلب. تحقق من الاتصال أو الصلاحيات.'
              : 'Could not load this request. Check connection or permissions.',
          isError: true,
        );
        return;
      }
      _openMarketRequestDetail(
        MarketPropertyRequestRow.fromMap(map),
        autoOpenSubmitOffer: autoOpenSubmitOffer,
      );
    } catch (_) {
      if (!mounted) return;
      _toast(
        widget.isAr ? 'تعذّر فتح الطلب.' : 'Could not open the request.',
        isError: true,
      );
    }
  }

  Future<void> _openCreateMarketRequestOnly() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    final res = await _pushBody<Object?>(
      MaterialPageRoute<Object?>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/dashboard/market-request-new'),
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: _uid,
          lang: widget.lang,
          embedAppBar: true,
        ),
      ),
    );
    if (!mounted) return;
    if (res == 'home' || res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 0);
    } else if (res == 'another') {
      await _reloadAll();
      if (!mounted) return;
      unawaited(_openCreateMarketRequestOnly());
    }
  }

  Future<void> _editMarketRequest(MarketPropertyRequestRow request) async {
    if (_isGuest || _uid.isEmpty || request.requesterId != _uid) {
      _showLoginDialog();
      return;
    }
    final res = await _pushBody<Object?>(
      MaterialPageRoute<Object?>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/dashboard/market-request-edit'),
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: _uid,
          lang: widget.lang,
          initialRequest: request,
          embedAppBar: true,
        ),
      ),
    );
    if (!mounted) return;
    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 2);
    }
  }

  Future<void> _guestPayUnlockFlow(String unlockKind,
      {required int targetTab}) async {
    if (!mounted) return;
    final paid = await runGuestOneTimePaymentFlow(
      context: context,
      isAr: widget.isAr,
      unlockKind: unlockKind,
    );
    if (!paid || !mounted) return;
    try {
      final session = context.read<AppSession>();
      final up = await GuestSessionBridge.tryEstablishBrowsingUser(
        sb: _sb,
        appSession: session,
      );
      if (!mounted) return;
      if (up) {
        await GuestUnlockService.clear();
        unawaited(_reloadAll());
        if (mounted) {
          _ss(() => _tabIndex = targetTab);
          _toast(
            widget.isAr
                ? 'تم التفعيل. يمكنك المتابعة من التبويب المفتوح.'
                : 'Unlocked. Continue from the opened tab.',
          );
        }
      } else {
        await GuestUnlockService.clear();
        _toast(
          widget.isAr
              ? 'فعّل تسجيل الدخول المجهول في Auth بلوحة Supabase أو أنشئ حساباً.'
              : 'Enable anonymous sign-in in Supabase Auth, or create an account.',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _toast(
        widget.isAr ? 'تعذّر إكمال التفعيل.' : 'Could not complete activation.',
        isError: true,
      );
    }
  }

  Future<void> _guestOpenCenterPlusFlow() async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.domain_add_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  widget.isAr ? 'إعلان عقاري' : 'Property listing',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  widget.isAr
                      ? 'نشر عقار للبيع أو الإيجار.'
                      : 'Publish a property for sale or rent.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'listing'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(
                    Icons.travel_explore_rounded,
                    color: cs.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  widget.isAr ? 'طلب عقاري' : 'Property request',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  widget.isAr
                      ? 'أبحث عن عقار للشراء أو الإيجار.'
                      : 'Looking to buy or rent.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'request'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    final forListing = choice == 'listing';
    final gate = await showGuestCreateContentGateSheet(
      context: context,
      isAr: widget.isAr,
      forListing: forListing,
    );
    if (!mounted) return;
    if (gate == GuestCreateContentGateResult.login) {
      await Navigator.of(context).pushNamed('/login');
      return;
    }
    if (gate == GuestCreateContentGateResult.register) {
      await Navigator.of(context).pushNamed('/register');
      return;
    }
    if (gate == GuestCreateContentGateResult.payOnce) {
      final kind = forListing ? 'listing' : 'request';
      final tab = forListing ? 1 : 2;
      await _guestPayUnlockFlow(kind, targetTab: tab);
      if (!mounted) return;
      if (!_isGuest) {
        await _openCenterPlus();
      }
    }
  }

  Future<void> _runAddPropertyListingFlow() async {
    if (_needsRegaGateBeforeAddProperty()) {
      final res = await _pushPlusForm<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => MarketingListingEntryPage(
            userId: _uid,
            lang: widget.lang,
            accountType: _accountType,
            embedAppBar: true,
          ),
        ),
      );

      if (!mounted) return;

      if (res == true) {
        await _reloadAll();
        if (mounted) _ss(() => _tabIndex = 0);
      }
      return;
    }

    final res = await _pushPlusForm<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => addp.AddPropertyPage(
          userId: _uid,
          lang: widget.lang,
          embedAppBar: true,
        ),
      ),
    );

    if (!mounted) return;

    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 0);
    }
  }

  /// زر + العائم: إعلان عقاري أو طلب عقاري (بدون دمج الشاشتين).
  Future<void> _openCenterPlus() async {
    if (_isGuest) {
      await _guestOpenCenterPlusFlow();
      return;
    }

    if (_accountRoleLoaded &&
        _orgNavResolved &&
        !_canPlusSheetAddProperty &&
        !_canPlusSheetAddRequest) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'لا تملك صلاحية إضافة عقار أو طلب عقاري. راجع مدير المنشأة.'
            : 'You do not have permission to add a listing or request. Ask your organization owner.',
        isError: false,
      );
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_canPlusSheetAddProperty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(
                      Icons.domain_add_rounded,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    widget.isAr ? 'إعلان عقاري' : 'Property listing',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    widget.isAr
                        ? 'نشر عقار للبيع أو الإيجار (مالك أو مسوّق معتمد وفق صلاحياتك).'
                        : 'Publish a property for sale or rent (owner or permitted marketer).',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(ctx, 'listing'),
                ),
              if (_canPlusSheetAddRequest)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Icon(
                      Icons.travel_explore_rounded,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    widget.isAr ? 'طلب عقاري' : 'Property request',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    widget.isAr
                        ? 'أبحث عن عقار للشراء أو الإيجار — يظهر طلبك في الرئيسية للمهتمين.'
                        : 'Looking to buy or rent — your request appears on the home feed.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(ctx, 'request'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    // بعد إغلاق الورقة: إطاران قصيران حتى لا يُبتلع مسار النموذج مع إغلاق الـ modal.
    final selected = choice;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    if (selected == 'request') {
      if (_isMarketingAccountType &&
          !await _ensureSubscriptionGate(
            SubscriptionGateAction.addMarketPropertyRequest,
          )) {
        return;
      }
      final res = await _pushPlusForm<Object?>(
        MaterialPageRoute<Object?>(
          fullscreenDialog: true,
          builder: (_) => CreateMarketPropertyRequestPage(
            userId: _uid,
            lang: widget.lang,
            embedAppBar: true,
          ),
        ),
      );
      if (!mounted) return;
      if (res == 'home' || res == true) {
        await _reloadAll();
        if (mounted) _ss(() => _tabIndex = 0);
      } else if (res == 'another') {
        await _reloadAll();
        if (!mounted) return;
        unawaited(_openCreateMarketRequestOnly());
      }
      return;
    }

    if (selected != 'listing') {
      return;
    }

    if (_isMarketerRole && AppRoleHelper.isMarketingAccountType(_accountType)) {
      if (!await _ensureSubscriptionGate(
        SubscriptionGateAction.addPropertyListing,
        resume: const MarketingSubscriptionResumeIntent(
          kind: MarketingSubscriptionResumeKind.addPropertyListing,
        ),
      )) {
        return;
      }
    }

    await _runAddPropertyListingFlow();
  }

  Future<void> _openDetails(
    Property p, {
    String? marketingRequestId,
    String? marketingInviteId,
    bool allowMarketingOffer = false,
    String? marketerHubPhase,
  }) async {
    if (!_isGuest) {
      unawaited(
        MarketingFlowService(_sb).markUnreadNotificationsForProperty(p.id),
      );
    }

    final String? ownerForDetails;
    if (_isGuest) {
      ownerForDetails = null;
    } else if (p.ownerId == _uid) {
      final raw = (p.ownerDisplayName ?? '').trim();
      ownerForDetails = raw.isNotEmpty ? raw : null;
    } else {
      final vis = p.visibleAdvertiserName.trim();
      ownerForDetails = vis.isNotEmpty ? vis : null;
    }

    await _pushBody<void>(
      MaterialPageRoute<void>(
        builder: (_) => details.PropertyDetailsPage(
          property: p,
          isAr: widget.isAr,
          currentUserId: _isGuest ? 'guest' : _uid,
          ownerUsername: ownerForDetails,
          marketingRequestId: marketingRequestId,
          marketingInviteId: marketingInviteId,
          embedAppBar: true,
          allowMarketingOffer: allowMarketingOffer,
          marketerHubPhase: marketerHubPhase,
          isFavorite: !_isGuest && _isFav(p.id),
          showOwnerLegalNameToViewer: _isMarketerRole &&
              !_isGuest &&
              p.effectiveWorkflowStage != ListingWorkflowStage.published,
          canManageProperty: !_isGuest && !_isMarketerRole && p.ownerId == _uid,
          homeFeedShowsHiddenOnly: _tabIndex == 0 && _homeShowHiddenOnly,
          onVisitorListingPreferenceChanged: _isGuest
              ? null
              : () {
                  if (mounted) unawaited(_reloadHiddenFeedPreferences());
                },
          onMarketerRegaAlignEdit: (!_isGuest && _isMarketerRole)
              ? _editPropertyAsMarketerRega
              : null,
          onToggleFavorite: () async {
            if (_isGuest) {
              _showLoginDialog();
              return;
            }
            await _toggleFav(p.id);
          },
          onCompleteDeal:
              _isGuest || _isMarketingAccountType ? null : _addToCart,
          onEditProperty: (prop) => _editProperty(prop),
          onRequestDelete: (prop) => _requestDeleteProperty(prop),
        ),
      ),
    );
  }

  // =========================
  // Property actions
  // =========================

  Future<Property?> _fetchPropertyById(String propertyId) async {
    final data = await _sb
        .from('properties')
        .select(SupabaseSchemaSelects.propertiesListing)
        .eq('id', propertyId)
        .maybeSingle();

    if (data == null) return null;
    return Property.fromJson(Map<String, dynamic>.from(data));
  }

  void _applyUpdatedPropertyToCollections(Property updated) {
    _ss(() {
      final i1 = _all.indexWhere((p) => p.id == updated.id);
      if (i1 != -1) _all[i1] = updated;

      final i2 = _mine.indexWhere((p) => p.id == updated.id);
      if (i2 != -1) _mine[i2] = updated;

      final i3 = _favoritesList.indexWhere((p) => p.id == updated.id);
      if (i3 != -1) _favoritesList[i3] = updated;

      _propertyCache[updated.id] = updated;
      _myPropertyById[updated.id] = updated;
    });
  }

  Future<Property?> _editPropertyAsMarketerRega(Property property) async {
    if (_isGuest) {
      _showLoginDialog();
      return null;
    }
    if (!ListingEditPermissions.marketerMayAlignWithRega(property, _uid)) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'التعديل متاح بعد إصدار التصريح وقبل النشر، وللمسوّق المرتبط بالإعلان فقط.'
            : 'Editing is only allowed after the permit is issued, before publish, for the assigned marketer.',
        isError: true,
      );
      return null;
    }

    final result = await _pushBody<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => EditPropertyPage(
          property: property,
          userId: _uid,
          lang: widget.lang,
          marketerRegaAlignmentMode: true,
          embedAppBar: true,
        ),
      ),
    );

    if (!mounted) return null;

    if (result is Property) {
      _applyUpdatedPropertyToCollections(result);
      _showNotification(
        widget.isAr ? 'تم التحديث' : 'Updated',
        widget.isAr
            ? 'تم حفظ مطابقة بيانات الهيئة.'
            : 'REGA alignment changes saved.',
      );
      return result;
    }
    return null;
  }

  Future<Property?> _editProperty(Property property) async {
    if (_isGuest) {
      _showLoginDialog();
      return null;
    }

    if (_isMarketerRole) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'استخدم «مطابقة بيانات الهيئة» من تفاصيل الإعلان بعد التصريح.'
            : 'Use REGA alignment from listing details after the permit is issued.',
        isError: true,
      );
      return null;
    }

    if (!ListingEditPermissions.ownerMayEditListingBody(property)) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'لا يمكن تعديل الإعلان بعد مرحلة التصاريح أو بعد نشره.'
            : 'This listing cannot be edited after the permit stage or once published.',
        isError: true,
      );
      return null;
    }

    if (property.ownerId != _uid) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'لا تملك صلاحية تعديل هذا الإعلان.'
            : 'You are not allowed to edit this listing.',
        isError: true,
      );
      return null;
    }

    final result = await _pushBody<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => EditPropertyPage(
          property: property,
          userId: _uid,
          lang: widget.lang,
          embedAppBar: true,
        ),
      ),
    );

    if (!mounted) return null;

    if (result is Property) {
      _applyUpdatedPropertyToCollections(result);

      _showNotification(
        widget.isAr ? 'تم التحديث' : 'Updated',
        widget.isAr
            ? 'تم تحديث الإعلان بنجاح.'
            : 'Listing updated successfully.',
      );

      unawaited(
        ComplianceAuditService.instance.log('listing.edit', {
          'property_id': result.id,
        }),
      );

      return result;
    }

    return null;
  }

  Future<bool> _requestDeleteProperty(Property property) async {
    if (_isGuest) {
      _showLoginDialog();
      return false;
    }

    if (_isMarketerRole) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'حساب المسوق لا يطلب حذف الإعلانات.'
            : 'Marketer accounts cannot request listing deletion.',
        isError: true,
      );
      return false;
    }

    if (property.ownerId != _uid) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'لا تملك صلاحية طلب حذف هذا الإعلان.'
            : 'You are not allowed to request deletion for this listing.',
        isError: true,
      );
      return false;
    }

    final reason = await _askDeleteReason();
    if (reason == null) return false;
    if (!mounted) return false;

    final confirmHard = await showAppConfirmDialog(
      context: context,
      title: widget.isAr ? 'تأكيد الحذف النهائي' : 'Confirm permanent delete',
      message: widget.isAr
          ? 'سيتم حذف الإعلان نهائياً مع الصور والبيانات المرتبطة (حسب إعدادات الخادم). لا يمكن التراجع.'
          : 'The listing and related data will be permanently removed (per server rules). This cannot be undone.',
      cancelLabel: widget.isAr ? 'إلغاء' : 'No',
      confirmLabel: widget.isAr ? 'حذف نهائي' : 'Yes, delete',
      isDanger: true,
    );
    if (!confirmHard) return false;

    _ss(() => _loadingMine = true);

    try {
      await _sb.rpc(
        'request_property_delete',
        params: {
          'p_property_id': property.id,
          'p_reason': reason,
        },
      );

      await _reloadAll();

      if (!mounted) return false;

      _showNotification(
        widget.isAr ? 'تم الحذف' : 'Deleted',
        widget.isAr
            ? 'تم حذف الإعلان والمرفقات المرتبطة وفق سياسة النظام.'
            : 'The listing and linked attachments were removed per system policy.',
      );
      AppHaptics.light();

      unawaited(
        ComplianceAuditService.instance.log('listing.delete', {
          'property_id': property.id,
        }),
      );

      return true;
    } on PostgrestException catch (e) {
      final msg = e.message.toUpperCase();

      if (mounted) {
        if (msg.contains('ALREADY_REQUESTED')) {
          _showNotification(
            widget.isAr ? 'طلب موجود' : 'Request already exists',
            widget.isAr
                ? 'يوجد طلب حذف قائم لهذا الإعلان بانتظار مراجعة الإدارة.'
                : 'A deletion request for this listing is already pending admin review.',
            isError: true,
          );
        } else {
          _showNotification(
            widget.isAr ? 'فشل الطلب' : 'Request failed',
            widget.isAr
                ? 'تعذر إرسال طلب الحذف: ${e.message}'
                : 'Failed to send deletion request: ${e.message}',
            isError: true,
          );
        }
      }

      debugPrint('requestDeleteProperty PostgrestException: $e');
      return false;
    } catch (e) {
      if (mounted) {
        _showNotification(
          widget.isAr ? 'فشل الطلب' : 'Request failed',
          widget.isAr
              ? 'تعذر إرسال طلب الحذف: $e'
              : 'Failed to send deletion request: $e',
          isError: true,
        );
      }

      debugPrint('requestDeleteProperty error: $e');
      return false;
    } finally {
      if (mounted) _ss(() => _loadingMine = false);
    }
  }

  Future<String?> _askDeleteReason() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        bool submitting = false;

        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(
              widget.isAr ? 'طلب حذف الإعلان' : 'Request listing deletion',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isAr
                      ? 'اكتب سبب الحذف. سيتم إرسال الطلب للإدارة ولن يُحذف الإعلان إلا بعد الموافقة.'
                      : 'Enter the reason for deletion. The request will be sent to admin and the listing will not be deleted until approved.',
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: controller,
                  enabled: !submitting,
                  maxLines: 4,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: widget.isAr
                        ? 'مثال: تم بيع العقار / الإعلان مكرر / أريد إيقافه'
                        : 'Example: Property sold / duplicate listing / want to stop it',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(context, null),
                child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
              ),
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () {
                        final reason = controller.text.trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                widget.isAr
                                    ? 'سبب الحذف مطلوب'
                                    : 'Deletion reason is required',
                              ),
                            ),
                          );
                          return;
                        }
                        if (reason.length < 5) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                widget.isAr
                                    ? 'اكتب سببًا أوضح للحذف'
                                    : 'Please enter a clearer deletion reason',
                              ),
                            ),
                          );
                          return;
                        }
                        setLocal(() => submitting = true);
                        Navigator.pop(context, reason);
                      },
                child: Text(widget.isAr ? 'إرسال الطلب' : 'Send request'),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();
    return result;
  }

  // =========================
  // Reservation actions
  // =========================

  bool _isReservedByAnyone(String propertyId) {
    final pc = _propertyCache[propertyId];
    if (pc != null &&
        pc.effectiveWorkflowStage == ListingWorkflowStage.reserved) {
      return true;
    }
    final r = _activeReservationByPropertyId[propertyId];
    if (r == null) return false;
    if (!_isStillValidReservationRow(r)) return false;
    final st = (r['status'] ?? '').toString();
    // DB constraint: pending/paid/expired/cancelled فقط.
    // نعتبر "محجوز" فقط عندما يكون الحجز فعّالاً (pending/paid) ولم تنتهِ مهلة expires_at.
    return st == 'pending' || st == 'paid';
  }

  DateTime? _reservedUntil(String propertyId) {
    final pc = _propertyCache[propertyId];
    final fromProp = pc?.reservationExpiresAt;
    if (fromProp != null) return fromProp;
    final r = _activeReservationByPropertyId[propertyId];
    if (r == null) return null;
    return _tryParseDt(r['expires_at']);
  }

  String? _reservedByName(String propertyId) {
    final r = _activeReservationByPropertyId[propertyId];
    if (r == null) return null;
    final s = (r['reserved_by_name'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  int _activeReservationHoldCount(String propertyId) {
    final r = _activeReservationByPropertyId[propertyId];
    if (r == null) return 0;
    if (!_isStillValidReservationRow(r)) return 0;
    final c = r['_active_reservation_count'];
    if (c is int) return c;
    return int.tryParse('$c') ?? 1;
  }

  Future<void> _shareListingFromCard(Property p) async {
    try {
      final uri = AppListingLinks.listingWebUri(
        p.id,
        lang: widget.isAr ? 'ar' : 'en',
      );
      final title = p.title.trim().isNotEmpty
          ? p.title.trim()
          : (widget.isAr ? 'إعلان عقار' : 'Property listing');
      final img = PropertyListingDisplay.propertySharePreviewUrl(p, _sb);
      await shareListingRich(
        text: '$title\n${uri.toString()}',
        imageHttpUrl: img,
        subject: widget.isAr ? 'إعلان — $title' : 'Listing — $title',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copyListingPublicLink(Property p) async {
    final uri = AppListingLinks.listingWebUri(
      p.id,
      lang: widget.isAr ? 'ar' : 'en',
    );
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isAr ? 'تم نسخ رابط الإعلان' : 'Listing link copied',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyMarketRequestPublicLink(MarketPropertyRequestRow r) async {
    final uri = AppListingLinks.marketRequestWebUri(
      r.id,
      lang: widget.isAr ? 'ar' : 'en',
    );
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isAr ? 'تم نسخ رابط الطلب' : 'Request link copied',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareMarketRequestFromCard(MarketPropertyRequestRow r) async {
    try {
      final uri = AppListingLinks.marketRequestWebUri(
        r.id,
        lang: widget.isAr ? 'ar' : 'en',
      );
      final title = r.title.trim().isNotEmpty
          ? r.title.trim()
          : (widget.isAr ? 'طلب عقاري' : 'Property request');
      final img =
          PropertyListingDisplay.marketRequestSharePreviewUrl(r, _sb);
      await shareListingRich(
        text: '$title\n${uri.toString()}',
        imageHttpUrl: img,
        subject: widget.isAr ? 'طلب — $title' : 'Request — $title',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addToCart(Property p) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    if (_isMarketingAccountType) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not Allowed',
        widget.isAr
            ? 'حساب التسويق لا يمكنه استخدام «صفقاتي».'
            : 'Marketing accounts cannot use the cart.',
        isError: true,
      );
      return;
    }

    if (p.ownerId == _uid) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not Allowed',
        widget.isAr
            ? 'لا يمكنك حجز إعلانك'
            : 'You cannot reserve your own listing',
        isError: true,
      );
      return;
    }

    if (!await _ensureSubscriptionGate(
      SubscriptionGateAction.completeMarketDeal,
    )) {
      return;
    }

    final offerDraft = await _showListingOfferDialog(p);
    if (offerDraft == null || !mounted) return;

    try {
      final double basePrice = offerDraft.offerPrice ??
          (p.isAuction ? (p.currentBid ?? p.price) : p.price);

      final ok = await ReservationsService.createReservation(
        userId: _uid,
        propertyId: p.id,
        basePrice: basePrice,
      );

      if (!ok) {
        if (!mounted) return;
        _showNotification(
          widget.isAr
              ? 'لا يمكن حجز هذا العقار'
              : 'Cannot reserve this property',
          widget.isAr
              ? 'هذا العقار غير متاح للحجز الآن'
              : 'This property is not available for reservation now',
          isError: true,
        );
        return;
      }

      await _syncListingOfferMessageToChat(
        property: p,
        message: offerDraft.message,
      );

      _propertyCache.clear();
      _profileCache.clear();

      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);

      if (!mounted) return;

      _showNotification(
        widget.isAr ? 'تمت إضافة الإعلان إلى صفقاتك' : 'Added to My deals',
        widget.isAr
            ? 'يمكنك متابعة إتمام الصفقة من تبويب «صفقاتي» (72 ساعة).'
            : 'Continue the deal from the My deals tab (72 hours).',
      );

      _ss(() {
        if (_showBottomNavCart) _tabIndex = 3;
      });
    } catch (_) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'لا يمكن حجز هذا العقار' : 'Cannot reserve this property',
        widget.isAr
            ? 'هذا العقار غير متاح للحجز الآن'
            : 'This property is not available for reservation now',
        isError: true,
      );
    }
  }

  Future<void> _completeDealFromMarketRequestHome(
    MarketPropertyRequestRow row,
  ) async {
    final isInstant = row.isInstantPaid;

    if (_isGuest) {
      if (isInstant) {
        final choice = await showGuestInstantDealAuthSheet(
          context: context,
          isAr: widget.isAr,
        );
        if (!mounted) return;
        if (choice == GuestAuthRequiredResult.login) {
          _showLoginDialog();
        } else if (choice == GuestAuthRequiredResult.register) {
          await Navigator.of(context, rootNavigator: true).pushNamed('/register');
        }
      } else {
        _showLoginDialog();
      }
      return;
    }

    if (_isMarketingAccountType) {
      _showNotification(
        widget.isAr ? 'غير مسموح' : 'Not allowed',
        widget.isAr
            ? 'حساب التسويق لا يمكنه استخدام «صفقاتي».'
            : 'Marketing accounts cannot use My deals.',
        isError: true,
      );
      return;
    }

    if (row.requesterId == _uid) {
      _openMarketRequestDetail(row);
      return;
    }

    final draft = await _showMarketRequestCompleteDealDialog(row);
    if (draft == null || !mounted) return;

    if (!isInstant &&
        _isMarketingAccountType &&
        !await _ensureSubscriptionGate(
          SubscriptionGateAction.completeMarketDeal,
          resume: MarketingSubscriptionResumeIntent(
            kind: MarketingSubscriptionResumeKind.submitOffer,
            requestId: row.id,
          ),
        )) {
      return;
    }

    String? oid;
    if (_isMarketingAccountType) {
      oid = await _marketingSubscriptionOrganizationId();
    }

    if (!isInstant && _isMarketingAccountType) {
      var allow = _subscriptionGate.marketOfferAllowance ??
          await IndividualMarketOfferService(_sb).currentAllowance(
            accountType: _accountType,
            organizationId: oid,
          );
      if (!mounted) return;
      if (!allow.canSubmitNow) {
        final goPay = await showMarketOfferPaywallDialog(
          context: context,
          isAr: widget.isAr,
          allowance: allow,
        );
        if (!mounted || !goPay) return;
        final didSubscribe = await _openSubscriptionsHubForMarketOffer(row.id);
        if (!mounted || !didSubscribe) return;
        allow = await IndividualMarketOfferService(_sb).currentAllowance(
          accountType: _accountType,
          organizationId: oid,
        );
        if (!mounted) return;
        if (!allow.canSubmitNow) {
          _showNotification(
            widget.isAr ? allow.shortStatusAr() : allow.shortStatusEn(),
            '',
            isError: true,
          );
          return;
        }
      }

      final usageRes =
          await IndividualMarketOfferService(_sb).recordUsageOnSuccess(row.id);
      if (!mounted) return;
      if (usageRes['ok'] != true) {
        final err = '${usageRes['error'] ?? ''}';
        _showNotification(
          widget.isAr
              ? individualOfferShortReasonAr(err)
              : 'Quota: $err',
          '',
          isError: true,
        );
        return;
      }
    }

    try {
      final added = await MarketRequestOffersService(_sb).submitOffer(
        marketRequestId: row.id,
        offerMessage: draft.message,
        priceOffer: draft.price,
      );
      if (!mounted) return;

      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMarketHomeRequests(force: true),
        _loadMyMarketRequestOfferTracking(),
      ]);

      if (!mounted) return;

      _showNotification(
        widget.isAr ? 'تمت إضافة الطلب إلى صفقاتك' : 'Added to My deals',
        added
            ? (widget.isAr
                ? 'تابع إتمام الصفقة من تبويب «صفقاتي».'
                : 'Continue the deal from the My deals tab.')
            : (widget.isAr
                ? 'الطلب موجود بالفعل في «صفقاتي».'
                : 'This request is already in My deals.'),
      );

      _ss(() {
        if (_showBottomNavCart) _tabIndex = 3;
      });
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر إتمام الصفقة' : 'Could not complete deal',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<({String message, double? price})?> _showMarketRequestCompleteDealDialog(
    MarketPropertyRequestRow row,
  ) async {
    final msgCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final budgetMax = row.budgetMax;
    if (budgetMax != null && budgetMax > 0) {
      priceCtrl.text = budgetMax.toStringAsFixed(
        budgetMax.truncateToDouble() == budgetMax ? 0 : 2,
      );
    }

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) {
          return AlertDialog(
            title: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isAr
                        ? 'سيُضاف الطلب إلى «صفقاتي» ويمكنك متابعة إتمام الصفقة مع صاحب الطلب.'
                        : 'The request will be added to My deals so you can complete the deal with the requester.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 12),
                  AqarTextField(
                    controller: msgCtrl,
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? 'رسالتك (اختياري)'
                          : 'Your message (optional)',
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 10),
                  AqarTextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: latinDecimalNumberFormatters(),
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? 'سعر مقترح (${AppMoney.saudiRiyalSignUnicode})'
                          : 'Suggested price (SAR)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
              ),
            ],
          );
        },
      );
      if (ok != true) return null;
      final parsed = double.tryParse(
        normalizeWesternDigits(priceCtrl.text.trim()).replaceAll(',', ''),
      );
      return (
        message: msgCtrl.text.trim(),
        price: (parsed == null || parsed <= 0) ? null : parsed,
      );
    } finally {
      msgCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  Future<({String message, double? offerPrice})?> _showListingOfferDialog(
    Property p,
  ) async {
    final msgCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final currentPrice = p.isAuction ? (p.currentBid ?? p.price) : p.price;
    if (currentPrice > 0) {
      priceCtrl.text = currentPrice.toStringAsFixed(
        currentPrice.truncateToDouble() == currentPrice ? 0 : 2,
      );
    }

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) {
          return AlertDialog(
            title: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isAr
                        ? 'سيُضاف الإعلان إلى «صفقاتي» لمدة 72 ساعة، وتُرسل رسالتك للمسوق العقاري المسؤول عن الإعلان.'
                        : 'The listing will be added to My deals for 72 hours, and your message will be sent to the listing marketer.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (p.isAuction) ...[
                    Text(
                      widget.isAr
                          ? 'آخر مزايدة (${AppMoney.saudiRiyalSignUnicode})'
                          : 'Latest bid (SAR)',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        currentPrice > 0
                            ? AppMoney.formatWithCurrencyCode(
                                currentPrice,
                                isAr: widget.isAr,
                              )
                            : (widget.isAr ? 'لا توجد مزايدة بعد' : 'No bid yet'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AqarTextField(
                    controller: msgCtrl,
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? (p.isAuction
                              ? 'رسالتك للمسوق (اختياري)'
                              : 'رسالتك للمسوق')
                          : (p.isAuction
                              ? 'Message to marketer (optional)'
                              : 'Message to marketer'),
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
              ),
            ],
          );
        },
      );

      if (ok != true) return null;
      final parsedOfferPrice = p.isAuction
          ? NumberHelper.toDouble(priceCtrl.text.trim())
          : null;
      return (
        message: msgCtrl.text.trim(),
        offerPrice: (parsedOfferPrice == null || parsedOfferPrice <= 0)
            ? null
            : parsedOfferPrice,
      );
    } finally {
      msgCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  Future<void> _syncListingOfferMessageToChat({
    required Property property,
    required String message,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final receiverId =
        (property.publishedByMarketerId ?? property.selectedMarketerId ?? '')
            .trim();
    if (receiverId.isEmpty || receiverId == _uid) return;
    try {
      final cid = await ReservationsService.getOrCreatePropertyConversation(
        propertyId: property.id,
        title: property.title,
      );
      await _sb.from('messages').insert({
        'sender_id': _uid,
        'receiver_id': receiverId,
        'conversation_id': cid,
        'content': trimmed,
      });
    } catch (_) {
      // Reservation/offer stays valid even if chat delivery needs retry later.
    }
  }

  Future<void> _completeSaleFromCart(String propertyId) async {
    if (propertyId.trim().isEmpty) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: widget.isAr ? 'إتمام الشراء' : 'Complete purchase',
      message: widget.isAr
          ? 'سيتم اعتماد الشراء وتسجيل الإعلان كمباع وإزالته من الرئيسية و«صفقاتي». لاحقاً يمكن ربط هذه الخطوة بالإدارة وتوليد عقد إتمام ودفع (Apple Pay / مدى / بطاقات بنكية / فيزا). حالياً يتم الإتمام كتسجيل شراء داخلي فقط. هل تؤكد؟'
          : 'This confirms the purchase, marks the listing as sold, and removes it from the home feed and My deals. Later this can link to admin review, a sale-completion contract, and payments (Apple Pay, Mada, bank cards, Visa). For now it only records the purchase in the app. Confirm?',
      confirmLabel: widget.isAr ? 'إتمام الشراء' : 'Complete purchase',
      cancelLabel: widget.isAr ? 'إلغاء' : 'Cancel',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    try {
      await MarketingFlowService(_sb).completePropertySale(propertyId);
      _propertyCache.clear();
      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);
      if (!mounted) return;
      _ensureSubTabControllers();
      final cleared = await _popBodyRoutesWithFormGuard();
      if (!cleared || !mounted) return;
      _ss(() => _tabIndex = 1);
      if (!_isMarketerRole && _ownerTabsCtrl != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final c = _ownerTabsCtrl;
          if (c != null && c.length > 7) {
            c.animateTo(7);
          }
          _showNotification(
            widget.isAr ? 'تم إتمام الشراء' : 'Purchase completed',
            widget.isAr
                ? 'سُجّل الإعلان كمباع ولم يعد يظهر للجمهور. تجد السجل في «صفحتي» → صفقات مكتملة.'
                : 'The listing is marked sold and hidden from the public feed. Find it under My page → Completed deals.',
          );
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showNotification(
            widget.isAr ? 'تم إتمام الشراء' : 'Purchase completed',
            widget.isAr
                ? 'سُجّل الإعلان كمباع ولم يعد يظهر للجمهور.'
                : 'The listing is marked sold and hidden from the public feed.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر الإتمام' : 'Could not complete',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _relistCompletedPropertyFromCart(Property property) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: widget.isAr ? 'إعادة تسويق العقار' : 'Relist property',
      message: widget.isAr
          ? 'سيتم إنشاء رحلة تسويق جديدة باسمك كمالك/معلن جديد، ولن تعود هذه الصفقة للظهور ضمن الصفقات المنتهية بعد إعادة التسويق.'
          : 'A new marketing journey will be created under your account as the new owner/advertiser. This completed deal will no longer appear as a finished deal after relisting.',
      confirmLabel: widget.isAr ? 'إعادة التسويق' : 'Relist',
      cancelLabel: widget.isAr ? 'إلغاء' : 'Cancel',
    );
    if (!ok || !mounted) return;
    try {
      final newId = await MarketingFlowService(_sb)
          .relistCompletedPropertyAsNew(property.id);
      _propertyCache.clear();
      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تمت إعادة التسويق' : 'Relisted',
        widget.isAr
            ? 'تم إنشاء إعلان/طلب تسويق جديد للعقار باسمك.'
            : 'A new listing/marketing request was created under your account.',
      );
      if ((newId ?? '').isNotEmpty) {
        _ss(() => _tabIndex = 1);
      }
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذرت إعادة التسويق' : 'Relist failed',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _cancelReservationFromCart(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    if (id.isEmpty) return;

    try {
      await ReservationsService.cancelReservation(id);

      _propertyCache.clear();
      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);

      if (!mounted) return;

      _showNotification(
        widget.isAr ? 'عاد العقار للنشر' : 'Property published again',
        widget.isAr ? 'تم إنهاء الحجز بنجاح' : 'Reservation ended successfully',
      );
    } catch (e) {
      final msg = e.toString();
      _showNotification(
        widget.isAr ? 'فشل الإلغاء' : 'Cancel Failed',
        widget.isAr ? 'فشل الإلغاء: $msg' : 'Cancel failed: $msg',
        isError: true,
      );
    }
  }

  Future<void> _reloadHiddenFeedPreferences() async {
    if (_isGuest) {
      if (_hiddenPropertyIds.isNotEmpty ||
          _hiddenMarketRequestIds.isNotEmpty ||
          _hiddenCompletedDealPropertyIds.isNotEmpty ||
          _hiddenCartMarketOfferIds.isNotEmpty) {
        _ssHomeFeed(() {
          _hiddenPropertyIds = {};
          _hiddenMarketRequestIds = {};
          _hiddenCompletedDealPropertyIds = {};
          _hiddenCartMarketOfferIds = {};
        });
      }
      return;
    }
    final hp = await UserListingPreferencesService.hiddenPropertyIds();
    final hr = await UserListingPreferencesService.hiddenMarketRequestIds();
    final hc =
        await UserListingPreferencesService.hiddenCompletedDealPropertyIds();
    final ho =
        await UserListingPreferencesService.hiddenCartMarketOfferIds();
    if (!mounted) return;
    _ssHomeFeed(() {
      _hiddenPropertyIds = hp;
      _hiddenMarketRequestIds = hr;
      _hiddenCompletedDealPropertyIds = hc;
      _hiddenCartMarketOfferIds = ho;
    });
  }

  Future<void> _copyPlainToClipboard(
    String text,
    String okMessage, {
    bool playSound = false,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    final msg = okMessage.trim();
    _showNotification(
      msg,
      '',
      playSound: playSound,
    );
  }

  Future<void> _hideCompletedDealFromOwnerHub(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) return;
    await UserListingPreferencesService.addHiddenCompletedDealProperty(id);
    if (!mounted) return;
    _ss(() {
      _hiddenCompletedDealPropertyIds = {
        ..._hiddenCompletedDealPropertyIds,
        id,
      };
    });
    _showNotification(
      widget.isAr ? 'تم الإخفاء' : 'Hidden',
      widget.isAr
          ? 'لن يظهر هذا العقار في «صفقات مكتملة» حتى تُلغي الإخفاء من التفضيلات المحلية.'
          : 'This listing is hidden from Completed deals until you restore it locally.',
    );
  }

  Future<void> _hideCartMarketOffer(String offerId) async {
    final id = offerId.trim();
    if (id.isEmpty) return;
    await UserListingPreferencesService.addHiddenCartMarketOffer(id);
    if (!mounted) return;
    _ss(() {
      _hiddenCartMarketOfferIds = {..._hiddenCartMarketOfferIds, id};
    });
    _showNotification(
      widget.isAr ? 'تم الإخفاء' : 'Hidden',
      widget.isAr
          ? 'لن يظهر هذا العرض في «صفقاتي» على هذا الجهاز.'
          : 'This offer is hidden from My deals on this device.',
    );
  }

  /// «حذف وإرجاع للرئيسية»: يسحب عرض المستخدم على طلب سوق ويُعيد ظهور الطلب في الرئيسية.
  ///
  /// - يُؤكّد العملية للمستخدم.
  /// - يستدعي [withdraw_my_market_request_offer] لتحرير الحصة وحذف العرض.
  /// - يُزيل الطلب من قائمة الإخفاء المحلية بعد سحبتين كي يظهر من جديد فور التحديث.
  /// - يُعيد تحميل البيانات اللازمة لتنعكس النتيجة على «صفقاتي» و«الرئيسية».
  Future<void> _withdrawCartMarketOffer(
    String requestId,
    String offerId,
  ) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return;
    final ar = widget.isAr;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(ar ? 'حذف العرض وإرجاع الطلب للرئيسية' : 'Delete & restore'),
        content: Text(
          ar
              ? 'سيتم سحب عرضك من السوق العقاري، وسيعود الطلب للظهور في الرئيسية مع ملاحظة «سبق وأن قدّمت عرضاً». لا يمكن السحب لو اختارك صاحب الطلب لإتمام الصفقة، وبعد سحبتين على نفس الطلب لن يظهر لك مجدداً.'
              : 'Your offer will be withdrawn and the request will return to Home with a "previously offered" marker. Withdrawal is blocked if the requester selected you for the deal; after two withdrawals on the same request it will not show again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(ar ? 'حذف وإرجاع' : 'Delete & restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await IndividualMarketOfferService(_sb).withdrawMyOffer(rid);
    if (!mounted) return;
    final ok = res['ok'] == true;
    if (!ok) {
      final code = (res['error'] ?? '').toString();
      _showNotification(
        ar ? 'تعذّر سحب العرض' : 'Could not withdraw',
        ar
            ? individualOfferShortReasonAr(code)
            : 'Server error: $code',
      );
      return;
    }

    final isFinal = res['final'] == true;
    _ss(() {
      // إن لم تُستهلك السحبتان نُعيد ظهور الطلب في الرئيسية فوراً.
      if (!isFinal) {
        _marketRequestIdsHiddenAfterTwoWithdrawals = {
          ..._marketRequestIdsHiddenAfterTwoWithdrawals,
        }..remove(rid);
        _hiddenMarketRequestIds = {..._hiddenMarketRequestIds}..remove(rid);
      } else {
        _marketRequestIdsHiddenAfterTwoWithdrawals = {
          ..._marketRequestIdsHiddenAfterTwoWithdrawals,
          rid,
        };
      }
      // أزل العرض من قائمة الانتظار محلياً (نفس مفتاح id):
      if (offerId.trim().isNotEmpty) {
        _myPendingMarketOffersForCart = _myPendingMarketOffersForCart
            .where((m) => (m['id'] ?? '').toString().trim() != offerId.trim())
            .toList();
        // أيضاً من الأرشيف — حتى لو ظهر بحالة 'withdrawn' من إعادة التحميل.
        _myArchivedMarketOffersForCart = _myArchivedMarketOffersForCart
            .where((m) => (m['id'] ?? '').toString().trim() != offerId.trim())
            .toList();
      }
      // أيضاً أزل بناءً على request_id لأي عرض على نفس الطلب (للأمان).
      _myPendingMarketOffersForCart = _myPendingMarketOffersForCart
          .where((m) =>
              (m['market_request_id'] ?? '').toString().trim() != rid)
          .toList();
      _myArchivedMarketOffersForCart = _myArchivedMarketOffersForCart
          .where((m) =>
              (m['market_request_id'] ?? '').toString().trim() != rid)
          .toList();
      _marketRequestIdsWithMyPendingOffer = {
        ..._marketRequestIdsWithMyPendingOffer,
      }..remove(rid);
    });

    unawaited(_loadMyMarketRequestOfferTracking());
    unawaited(_loadMarketHomeRequests(force: true));

    _showNotification(
      ar ? 'تم الحذف' : 'Deleted',
      isFinal
          ? (ar
              ? 'تم سحب عرضك. لن يظهر لك هذا الطلب مرة أخرى (الحد سحبتان لكل طلب).'
              : 'Offer withdrawn. This request will no longer appear (limit: 2 withdrawals per request).')
          : (ar
              ? 'تم سحب عرضك وأُعيد الطلب إلى الرئيسية.'
              : 'Offer withdrawn and the request was restored to Home.'),
    );
  }

  Future<void> _restoreAllHiddenCompletedDeals() async {
    await UserListingPreferencesService.clearHiddenCompletedDeals();
    if (!mounted) return;
    _ss(() => _hiddenCompletedDealPropertyIds = {});
    _showNotification(
      widget.isAr ? 'تم الإظهار' : 'Restored',
      widget.isAr
          ? 'عُيدت جميع الصفقات المخفية إلى القائمة.'
          : 'All hidden completed deals are visible again.',
    );
  }

  /// مسار مختصر لإعلان جديد بعد البيع (نفس بوابة الريجا للمسوّقين عند الحاجة).
  Future<void> _openOwnerAddPropertyShortcut() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    if (_isMarketerRole) {
      _showNotification(
        widget.isAr ? 'غير متاح هنا' : 'Not here',
        widget.isAr
            ? 'استخدم «إعلان عقاري» من زر + للمسوّقين.'
            : 'Use the + menu to add a listing as a marketer.',
        isError: true,
      );
      return;
    }

    if (_needsRegaGateBeforeAddProperty()) {
      final rega = await showRegaAdLicenseGate(
        context: context,
        isAr: widget.isAr,
        sb: _sb,
      );
      if (!mounted) return;
      if (rega == null || rega.isEmpty) return;

      final res = await _pushBody<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => addp.AddPropertyPage(
            userId: _uid,
            lang: widget.lang,
            initialRegaPayload: rega,
            embedAppBar: true,
          ),
        ),
      );
      if (!mounted) return;
      if (res == true) {
        await _reloadAll();
        if (mounted) _ss(() => _tabIndex = 0);
      }
      return;
    }

    final res = await _pushBody<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => addp.AddPropertyPage(
          userId: _uid,
          lang: widget.lang,
          embedAppBar: true,
        ),
      ),
    );
    if (!mounted) return;
    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 0);
    }
  }

  Future<void> _onHomeHideProperty(Property p) async {
    if (_isGuest) return;
    await UserListingPreferencesService.addHiddenProperty(p.id);
    if (!mounted) return;
    _ss(() => _hiddenPropertyIds = {..._hiddenPropertyIds, p.id});
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastListingHiddenFromHome);
    }
  }

  Future<void> _onRestorePropertyToHome(Property p) async {
    if (_isGuest) return;
    await UserListingPreferencesService.removeHiddenProperty(p.id);
    if (!mounted) return;
    _ss(() {
      final next = {..._hiddenPropertyIds}..remove(p.id);
      _hiddenPropertyIds = next;
    });
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastListingShownOnHomeAgain);
    }
  }

  Future<void> _onWithdrawPropertyReport(Property p) async {
    if (_isGuest) return;
    await UserListingPreferencesService.withdrawPendingPropertyReport(
        _sb, p.id);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastListingReportWithdrawn);
    }
    await _reloadHiddenFeedPreferences();
  }

  Future<void> _onRestoreMarketRequest(MarketPropertyRequestRow r) async {
    if (_isGuest) return;
    await UserListingPreferencesService.removeHiddenMarketRequest(r.id);
    if (!mounted) return;
    _ss(() {
      final next = {..._hiddenMarketRequestIds}..remove(r.id);
      _hiddenMarketRequestIds = next;
    });
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastMarketRequestShownOnHomeAgain);
    }
  }

  Future<void> _onHomeReportProperty(Property p) async {
    if (_isGuest) return;
    await showPropertyListingReportSheet(
      context,
      sb: _sb,
      property: p,
      onDone: () {
        if (mounted) unawaited(_reloadHiddenFeedPreferences());
      },
    );
    if (mounted) await _reloadHiddenFeedPreferences();
  }

  Future<void> _onHomeHideMarketRequest(MarketPropertyRequestRow r) async {
    if (_isGuest) return;
    await UserListingPreferencesService.addHiddenMarketRequest(r.id);
    if (!mounted) return;
    _ss(() => _hiddenMarketRequestIds = {..._hiddenMarketRequestIds, r.id});
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastMarketRequestHiddenFromHome);
    }
  }

  Future<void> _onHomeReportMarketRequest(MarketPropertyRequestRow r) async {
    if (_isGuest) return;
    await showMarketRequestReportSheet(
      context,
      sb: _sb,
      request: r,
      onDone: () {
        if (mounted) unawaited(_reloadHiddenFeedPreferences());
      },
    );
    if (mounted) await _reloadHiddenFeedPreferences();
  }

  List<Property> _mergePropertyListsForMap(
    List<Property> primary,
    List<Property> extra,
  ) {
    final m = <String, Property>{};
    for (final p in primary) {
      m[p.id] = p;
    }
    for (final p in extra) {
      m[p.id] = p;
    }
    return m.values.toList(growable: false);
  }

  List<MarketPropertyRequestRow> _mergeMarketRequestListsForMap(
    List<MarketPropertyRequestRow> primary,
    List<MarketPropertyRequestRow> extra,
  ) {
    final m = <String, MarketPropertyRequestRow>{};
    for (final r in primary) {
      m[r.id] = r;
    }
    for (final r in extra) {
      m[r.id] = r;
    }
    return m.values.toList(growable: false);
  }

  Future<String?> _orgUnitIdForSubscriptionsMenu() async {
    if (!_orgNavIsOwner) return null;
    try {
      final o = await OrgTeamService(_sb).orgUnitForOwner();
      return o?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// منشأة الفريق لاشتراك التسويق (مكاتب/شركات/مؤسسات/وكالة)، أو اشتراك المالك عند التوفر.
  Future<String?> _marketingSubscriptionOrganizationId() async {
    if (!AppRoleHelper.isMarketingAccountType(_accountType)) return null;
    if (AppRoleHelper.isStandaloneMarketer(_accountType)) return null;
    try {
      final ctx = await OrgTeamService(_sb).myOrgContext();
      final id = '${ctx?['org_id'] ?? ''}'.trim();
      if (id.isNotEmpty) return id;
    } catch (_) {}
    if (_orgNavIsOwner) {
      return await _orgUnitIdForSubscriptionsMenu();
    }
    return null;
  }

  AppSubscriptionGate get _subscriptionGate => context.read<AppSubscriptionGate>();

  Future<void> _refreshSubscriptionGate({bool force = true}) async {
    await _subscriptionGate.refresh(force: force);
  }

  Future<void> _openSubscriptionsFromGate(
    SubscriptionGateAction action, {
    MarketingSubscriptionResumeIntent? resume,
  }) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    final intent = resume ??
        MarketingSubscriptionResumeIntent(
          kind: switch (action) {
            SubscriptionGateAction.completeMarketDeal =>
              MarketingSubscriptionResumeKind.submitOffer,
            SubscriptionGateAction.addPropertyListing =>
              MarketingSubscriptionResumeKind.addPropertyListing,
            SubscriptionGateAction.addMarketPropertyRequest =>
              MarketingSubscriptionResumeKind.postPaidUnlock,
            SubscriptionGateAction.marketingPaidWorkflow =>
              MarketingSubscriptionResumeKind.postPaidUnlock,
          },
        );
    // إتمام الصفقة للمسوّق: اعرض باقات «إضافة صفقات» فقط (لا الباقات الكاملة).
    final marketOfferOnly =
        action == SubscriptionGateAction.completeMarketDeal &&
        _isMarketingAccountType;
    await _pushSubscriptionsHubForPaidActionResume(
      intent,
      marketOfferPlansOnly: marketOfferOnly,
    );
    await _refreshSubscriptionGate(force: true);
  }

  Future<bool> _ensureSubscriptionGate(
    SubscriptionGateAction action, {
    MarketingSubscriptionResumeIntent? resume,
    bool presentDialog = true,
  }) async {
    if (_isGuest) {
      _showLoginDialog();
      return false;
    }
    await _refreshSubscriptionGate(force: false);
    if (_subscriptionGate.allows(action)) return true;
    if (!mounted || !presentDialog) return false;

    if (action == SubscriptionGateAction.completeMarketDeal) {
      final allow = _subscriptionGate.marketOfferAllowance;
      if (allow != null) {
        final goPay = await showMarketOfferPaywallDialog(
          context: context,
          isAr: widget.isAr,
          allowance: allow,
        );
        if (!mounted || !goPay) return false;
        await _openSubscriptionsFromGate(
          action,
          resume: resume,
        );
        await _refreshSubscriptionGate(force: true);
        return _subscriptionGate.allows(action);
      }
    }

    if (action == SubscriptionGateAction.marketingPaidWorkflow ||
        (action == SubscriptionGateAction.addPropertyListing &&
            _isMarketingAccountType)) {
      final oid = await _marketingSubscriptionOrganizationId();
      final row = _subscriptionGate.subscriptionRow ??
          await SubscriptionService(_sb)
              .getCurrentSubscription(organizationId: oid);
      if (!mounted) return false;
      await showMarketingSubscriptionPaywallDialog(
        context: context,
        isAr: widget.isAr,
        subscriptionRow: row,
        onSubscribe: () => unawaited(
          _openSubscriptionsFromGate(action, resume: resume),
        ),
      );
      await _refreshSubscriptionGate(force: true);
      return _subscriptionGate.allows(action);
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(
          widget.isAr
              ? _subscriptionGate.alertTitleAr(action)
              : _subscriptionGate.alertTitleEn(action),
        ),
        content: Text(
          widget.isAr
              ? _subscriptionGate.alertBodyAr(action)
              : _subscriptionGate.alertBodyEn(action),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.isAr ? 'لاحقاً' : 'Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_openSubscriptionsFromGate(action, resume: resume));
            },
            icon: const Icon(Icons.subscriptions_outlined),
            label: Text(widget.isAr ? 'الذهاب للاشتراك' : 'Go to subscription'),
          ),
        ],
      ),
    );
    await _refreshSubscriptionGate(force: true);
    return _subscriptionGate.allows(action);
  }

  /// بوابة اشتراك لكل إجراء تسويقي مدفوع/تعاقدي من لوحة «صفحتي».
  Future<bool> _ensureMarketingSubscriptionForPaidWorkflow(
    MarketingSubscriptionResumeIntent resume,
  ) async {
    if (_isGuest) return false;
    if (!_isMarketingAccountType) {
      return true;
    }
    if (_subscriptionGate.canUseMarketingPaidWorkflow) return true;
    return _ensureSubscriptionGate(
      SubscriptionGateAction.marketingPaidWorkflow,
      resume: resume,
    );
  }

  /// إشعار «اشتراك على وشك الانتهاء» — يُعرض مرة واحدة لكل جلسة عند بقاء ≤ 3 أيام.
  Future<void> _maybeShowExpiringSubscriptionPrompt() async {
    if (!mounted || _isGuest) return;
    if (_expiringPromptShown) return;
    if (!_isMarketingAccountType) return;
    try {
      final oid = await _marketingSubscriptionOrganizationId();
      final svc = SubscriptionService(_sb);
      final row = await svc.getCurrentSubscription(organizationId: oid);
      if (row == null) return;
      final end = SubscriptionService.subscriptionExclusiveEndUtc(row);
      if (end == null) return;
      final now = DateTime.now().toUtc();
      final diff = end.difference(now);
      if (diff.isNegative) return;
      if (diff > const Duration(days: 3)) return;
      if (!mounted) return;
      _expiringPromptShown = true;

      final isAr = widget.isAr;
      final endLocal = end.toLocal();
      final formatted = DateFormat(
        'EEEE d MMM yyyy — HH:mm',
        isAr ? 'ar' : 'en',
      ).format(endLocal);
      final days = diff.inDays;
      final hours = diff.inHours - days * 24;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isAr ? 'اشتراكك على وشك الانتهاء' : 'Your subscription is ending soon',
          ),
          content: Text(
            isAr
                ? 'يتبقى على انتهاء اشتراكك ${days > 0 ? '$days يوم و ' : ''}$hours ساعة.\nتاريخ ووقت الانتهاء: $formatted.\n\nجدّد الاشتراك قبل الانتهاء لتجنّب توقف ميزات النشر والتعاقد.'
                : 'Your subscription ends in ${days > 0 ? '$days days and ' : ''}$hours hours.\nEnds at: $formatted.\n\nRenew now to avoid interruption.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isAr ? 'لاحقاً' : 'Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_pushSubscriptionsHubForPaidActionResume(
                  const MarketingSubscriptionResumeIntent(
                    kind: MarketingSubscriptionResumeKind.postPaidUnlock,
                  ),
                ));
              },
              child: Text(isAr ? 'جدّد الآن' : 'Renew now'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('_maybeShowExpiringSubscriptionPrompt error: $e');
    }
  }

  Future<void> _pushSubscriptionsHubForPaidActionResume(
    MarketingSubscriptionResumeIntent intent, {
    int initialIndex = 0,
    bool marketOfferPlansOnly = false,
  }) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    final oid = await _marketingSubscriptionOrganizationId();
    if (!mounted) return;
    final popped = await _pushBody<MarketingSubscriptionResumeIntent?>(
      MaterialPageRoute<MarketingSubscriptionResumeIntent?>(
        settings: const RouteSettings(name: '/dashboard/subscriptions'),
        builder: (_) => SubscriptionsRootScreen(
          lang: widget.lang,
          accountType: _accountType,
          organizationId: oid,
          initialIndex: initialIndex,
          embedAppBar: true,
          resumeAfterPurchase: intent,
          marketOfferPlansOnly: marketOfferPlansOnly,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(_refreshSubscriptionMenuBadge());
    await _refreshSubscriptionGate(force: true);
    if (popped != null && popped.isValid) {
      await _resumeMarketingSubscriptionAfterPurchase(popped);
    }
  }

  Future<void> _resumeMarketingSubscriptionAfterPurchase(
    MarketingSubscriptionResumeIntent intent,
  ) async {
    SubscriptionService.invalidateSubscriptionCache();
    await _loadMarketerBuckets(force: true);
    if (!mounted) return;
    switch (intent.kind) {
      case MarketingSubscriptionResumeKind.submitOffer:
        final rid = intent.requestId.trim();
        if (rid.isNotEmpty && !_isMarketingAccountType) {
          await _openMarketRequestDetailById(
            rid,
            autoOpenSubmitOffer: true,
          );
        } else {
          final row = _findMarketerRowForSubscriptionResume(intent);
          if (row != null) {
            await _showMarketingOfferSheetForRow(row);
          } else if (rid.isNotEmpty) {
            await _openMarketRequestDetailById(
              rid,
              autoOpenSubmitOffer: true,
            );
          } else {
            _showNotification(
              widget.isAr ? 'تنبيه' : 'Notice',
              widget.isAr
                  ? 'تم تفعيل الاشتراك. حدّث القائمة أو أعد فتح الطلب لإتمام الصفقة.'
                  : 'Subscription active. Refresh the list or reopen the request to complete your deal.',
              isError: false,
            );
          }
        }
        break;
      case MarketingSubscriptionResumeKind.createContract:
        final r1 = _findMarketerRowForSubscriptionResume(intent);
        if (r1 != null) {
          await _createMarketingContract(r1);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. حدّث القائمة ثم أنشئ العقد من بطاقة العرض المقبول.'
                : 'Subscription active. Refresh the list, then create the contract from the accepted offer card.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.submitPermit:
        final rp = _findMarketerRowForSubscriptionResume(intent);
        if (rp != null) {
          await _submitMarketingPermit(rp);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. حدّث القائمة ثم ارفع التصريح من بطاقة التراخيص.'
                : 'Subscription active. Refresh the list, then submit the permit from the permits card.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.linkRegaPermit:
        final rl = _findMarketerRowForSubscriptionResume(intent);
        if (rl != null) {
          await _linkRegaAdLicenseWithAuthority(rl);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. حدّث القائمة ثم أكمل ربط التصريح.'
                : 'Subscription active. Refresh the list, then complete REGA linking.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.publishListing:
        final pub = _findMarketerRowForSubscriptionResume(intent);
        if (pub != null) {
          await _showPublishMarketingListingDialog(pub);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. حدّث القائمة ثم أكمل النشر.'
                : 'Subscription active. Refresh the list, then complete publishing.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.reportRegaMismatch:
        final rr = _findMarketerRowForSubscriptionResume(intent);
        if (rr != null) {
          await _reportRegaLicenseMismatch(rr);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. حدّث القائمة ثم سجّل البلاغ إن لزم.'
                : 'Subscription active. Refresh the list, then submit the report if needed.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.contractChat:
        final rc = _findMarketerRowForSubscriptionResume(intent);
        if (rc != null) {
          await _openMarketerChatWithOwnerGated(rc);
        } else {
          _showNotification(
            widget.isAr ? 'تنبيه' : 'Notice',
            widget.isAr
                ? 'تم تفعيل الاشتراك. افتح دردشة المالك من البطاقة بعد التحديث.'
                : 'Subscription active. Open owner chat from the card after refresh.',
            isError: false,
          );
        }
        break;
      case MarketingSubscriptionResumeKind.postPaidUnlock:
        _showNotification(
          widget.isAr ? 'تم' : 'Done',
          widget.isAr
              ? 'تم تفعيل الاشتراك — يمكنك تنفيذ الإجراء الآن من نفس البطاقة.'
              : 'Subscription active — you can complete the action from the same card.',
          isError: false,
        );
        break;
      case MarketingSubscriptionResumeKind.addPropertyListing:
        await _runAddPropertyListingFlow();
        break;
    }
  }

  Future<void> _refreshSubscriptionMenuBadge() async {
    if (_isGuest || _uid.isEmpty) {
      _ss(() => _subscriptionMenuBadge = 0);
      return;
    }
    try {
      final svc = SubscriptionService(_sb);
      var badge = await svc.subscriptionMenuBadge();
      if (_orgNavIsOwner) {
        final oid = await _orgUnitIdForSubscriptionsMenu();
        if (oid != null && oid.isNotEmpty) {
          final b2 = await svc.subscriptionMenuBadge(organizationId: oid);
          if (b2 > badge) badge = b2;
        }
      }
      if (AppRoleHelper.isMarketingAccountType(_accountType) &&
          !AppRoleHelper.isStandaloneMarketer(_accountType)) {
        final oidM = await _marketingSubscriptionOrganizationId();
        if (oidM != null && oidM.isNotEmpty) {
          final b3 = await svc.subscriptionMenuBadge(organizationId: oidM);
          if (b3 > badge) badge = b3;
        }
      }
      _ss(() => _subscriptionMenuBadge = badge);
    } catch (_) {
      _ss(() => _subscriptionMenuBadge = 0);
    }
  }

  void _openSubscriptionsHub({int initialIndex = 0}) {
    unawaited(() async {
      if (_isGuest) {
        _showLoginDialog();
        return;
      }
      final oid = await _orgUnitIdForSubscriptionsMenu();
      if (!mounted) return;
      await _pushBody<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/dashboard/subscriptions'),
          builder: (_) => SubscriptionsRootScreen(
            lang: widget.lang,
            accountType: _accountType,
            organizationId: oid,
            initialIndex: initialIndex,
            embedAppBar: true,
          ),
        ),
      );
      if (mounted) unawaited(_refreshSubscriptionMenuBadge());
    }());
  }
}
