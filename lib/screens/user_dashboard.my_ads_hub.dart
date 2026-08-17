part of 'user_dashboard.dart';

/// واجهة تبويبات «صفحتي» (مسوّق/معلن): راجع `docs/MARKETING_FULL_FLOW_USER_SPEC_AR.md` لربط المراحل.

extension _UserDashboardStateMyAdsHub on _UserDashboardState {
  /// تنبيه بصري: طلبات كمعلن تحتاج مراجعة عروض (يشمل المسوّق الذي يطرح طلبات).
  int get _ownerOffersAttentionCount {
    if (_isGuest) return 0;
    if (_isMarketerRole && _ownerListingRequests.isEmpty) return 0;
    var n = 0;
    for (final r in _ownerListingRequests) {
      final ctx = ListingWorkflowUiContext.fromListingRequest(
        Map<String, dynamic>.from(r),
      );
      if (!ctx.showOwnerOffersEntry) continue;
      if (r['owner_viewed_offers_at'] != null) continue;
      n++;
    }
    return n;
  }

  /// تبويبات التسويق/المعلن (لا تخلطها مع [_buildMyAdsHub] في ui.dart).
  Widget _buildMyAdsMarketingHub(List<Property> myItems) {
    final cs = Theme.of(context).colorScheme;

    if (_isGuest) {
      final l10n = AppLocalizations.of(context)!;
      return ListView(
        controller: _scrollControllerForOnboardingTab(1),
        physics: _myAdsHubScrollPhysics,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 60),
          Icon(
            Icons.lock_outline,
            size: 84,
            color: _brandPrimary.withOpacity(_op(180)),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.loginToManageListingsBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _navigateToLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 14,
              ),
            ),
            child: Text(
              l10n.userSignIn,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    }

    // مثل النسخة الاحتياطية: مسوّق/مكتب/… → تبويبات صفحتي (وليس قائمة مسطّحة).
    // ويب يستخدم AnimatedBuilder لتبويب واحد/إطار (سرعة) مع الإبقاء على TabBar.
    final bool isMarketer = _isMarketingAccountType;

    if (isMarketer) {
      _ensureSubTabControllers();
      final ctrl = _marketerTabsCtrl;
      if (ctrl == null) {
        if (kIsWeb) {
          return PropertyCardSkeletonList(
            scrollController: _scrollControllerForOnboardingTab(1),
            count: 3,
            topPadding: 16,
          );
        }
        return _buildHubPreparingState(
          title: AppLocalizations.of(context)!.preparingMarketingTabsTitle,
          onRetry: _ensureSubTabControllers,
        );
      }
      // إن كان لديه طلبات كمعلن: مبدّل ذكي بين دور المسوّق ودور المالك.
      if (_hasOwnerRequestsData) {
        return _buildMarketerDualRoleMyAds(cs, ctrl);
      }
      return _buildMarketerMyAds(cs, ctrl);
    }

    // مالك فرد بلا طلبات تسويق: بطاقات إعلاناته مباشرة (المنشورة ليست في التبويبات السبعة).
    if (kIsWeb && !_hasOwnerRequestsData) {
      return _buildOwnerDirectMineCards(cs, myItems);
    }

    _ensureSubTabControllers();
    final ctrl = _ownerTabsCtrl;
    if (ctrl == null) {
      if (kIsWeb) {
        return PropertyCardSkeletonList(
          scrollController: _scrollControllerForOnboardingTab(1),
          count: 3,
          topPadding: 16,
        );
      }
      return _buildHubPreparingState(
        title: AppLocalizations.of(context)!.preparingListingsTabsTitle,
        onRetry: _ensureSubTabControllers,
      );
    }

    return _buildOwnerMyAds(cs, myItems, ctrl);
  }

  /// صفحتي للمالك الفرد على الويب: قائمة بطاقات فورية (بدون 7 تبويبات فارغة).
  Widget _buildOwnerDirectMineCards(ColorScheme cs, List<Property> myItems) {
    final scroll = _scrollControllerForOnboardingTab(1);
    final ar = widget.isAr;
    final items = List<Property>.from(myItems)
      ..sort((a, b) => b.displayDate.compareTo(a.displayDate));

    if (_loadingMine && items.isEmpty) {
      return PropertyCardSkeletonList(
        scrollController: scroll,
        count: 3,
        topPadding: 16,
      );
    }

    if (items.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      return ListView(
        controller: scroll,
        physics: _myAdsHubScrollPhysics,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.home_work_outlined,
            size: 72,
            color: _brandPrimary.withOpacity(_op(180)),
          ),
          const SizedBox(height: 16),
          Text(
            ar ? 'لا توجد إعلانات بعد' : 'No listings yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            ar
                ? 'أضف إعلاناً من زر + وسيظهر هنا فوراً.'
                : 'Add a listing from + and it will show here instantly.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => unawaited(_openCenterPlus()),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.navAdd),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

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
        final rowCount = (items.length + cross - 1) ~/ cross;
        return ListView.separated(
          controller: scroll,
          primary: false,
          physics: _myAdsHubScrollPhysics,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          cacheExtent: 360,
          itemCount: rowCount,
          separatorBuilder: (_, __) => const SizedBox(height: spacing),
          itemBuilder: (context, row) {
            final start = row * cross;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < cross; j++) ...[
                  if (j > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: start + j < items.length
                        ? Builder(
                            builder: (context) {
                              final p = items[start + j];
                              final isOwner = p.ownerId == _uid;
                              return _wrapEqualGridCardHeight(
                                height: equalH,
                                child: _RealEstateCard(
                                  property: p,
                                  isOwner: isOwner,
                                  isAr: ar,
                                  bankColor: _brandPrimary,
                                  favorite: !_isGuest && _isFav(p.id),
                                  onToggleFav: () => _toggleFav(p.id),
                                  onOpenDetails: () => _openDetails(p),
                                  activeCartHoldsCount:
                                      _activeReservationHoldCount(p.id),
                                  isReserved: _isReservedByAnyone(p.id),
                                  reservedUntil: _reservedUntil(p.id),
                                  reservedByName: _reservedByName(p.id),
                                  onAddToCart: null,
                                  currentUserId: _uid.isEmpty ? 'guest' : _uid,
                                  showEditDelete: isOwner,
                                  onEditProperty:
                                      isOwner ? () => _editProperty(p) : null,
                                  onDeleteProperty: isOwner
                                      ? () => _requestDeleteProperty(p)
                                      : null,
                                  timeAgo: _timeAgo,
                                  canShowCartButton: false,
                                  showListingQuickActions: true,
                                  onCopyListingWebLink: _copyListingPublicLink,
                                  suppressPublicOwnerIdentity: true,
                                  preferStaticPrimaryImage: true,
                                ),
                              );
                            },
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

  /// مسار قديم (ويب مسطّح) — لم يعد يُستدعى؛ التبويبات عبر [_buildMarketerMyAds].
  Widget _buildMarketerWebFlatHub(ColorScheme cs, List<Property> myItems) {
    return _buildOwnerDirectMineCards(cs, myItems);
  }

  Widget _buildHubPreparingState({
    required String title,
    required VoidCallback onRetry,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return PropertyCardSkeletonList(
      scrollController: _scrollControllerForOnboardingTab(1),
      count: 5,
      topPadding: 20,
      bottomPadding: 32,
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.ifContinuesTapRetry,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Property> _filterOwnerHubTab(List<Property> items, int tabIndex) {
    // مجموعة معرّفات الإعلانات التي لها صف listing_request (نتجنّب تكرار البطاقة).
    final reqPids = <String>{};
    for (final r in _ownerListingRequests) {
      final pp = (r['preview_property_id'] ?? r['property_id'] ?? '')
          .toString()
          .trim();
      if (pp.isNotEmpty) reqPids.add(pp);
    }

    return items.where((p) {
      if (p.deletedByUser) return false;
      if (p.deleteApproved) return false;
      if (tabIndex == 8) {
        final st = p.normalizedStatus;
        final soldLike = st == 'sold' || st == 'completed';
        if (!soldLike) return false;
        if (_hiddenCompletedDealPropertyIds.contains(p.id)) return false;
        return true;
      }

      final stage = p.effectiveWorkflowStage;

      // إعلانات قبل النشر للمالك الفردي (غير مرتبطة بطلب نشر) — تظهر في تبويب 0.
      // كنّا نُخفيها سابقاً لأن decideFromProperty يستثني المراحل قبل النشر.
      final isPrePublish = stage == ListingWorkflowStage.addedByOwner ||
          stage == ListingWorkflowStage.waitingMarketers;
      if (isPrePublish &&
          tabIndex == 0 &&
          !reqPids.contains(p.id) &&
          !_isMarketingAccountType) {
        return true;
      }

      final decision = ListingPostPublishUiHelper.decideFromProperty(p);
      if (!decision.showInOwnerPage) return false;
      return ListingStageUiHelper.ownerTabMatches(
        tabIndex,
        stage,
      );
    }).toList();
  }

  List<double> _hubRowNumbers(Map<String, dynamic> r, List<String> keys) {
    final out = <double>[];
    for (final key in keys) {
      final v = r[key];
      if (v == null) continue;
      if (v is num) {
        out.add(v.toDouble());
        continue;
      }
      final parsed = double.tryParse(
        _norm(v.toString()).replaceAll(RegExp(r'[^0-9.]'), ''),
      );
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  bool _matchesHubRowAnyRange(
    Map<String, dynamic> r,
    List<String> keys,
    double? min,
    double? max,
  ) {
    if (min == null && max == null) return true;
    final values = _hubRowNumbers(r, keys).where((v) => v > 0).toList();
    if (values.isEmpty) return false;
    return values.any((v) {
      if (min != null && v < min) return false;
      if (max != null && v > max) return false;
      return true;
    });
  }

  bool _matchesHubRowSearch(Map<String, dynamic> r) {
    final q = _searchQuery.trim();
    final nq = _norm(q);
    if (nq.isEmpty) return true;
    final tokens = _tokens(nq);
    if (tokens.isEmpty) return true;
    final hay = _norm(_flattenSearchValue(r));
    if (hay.isEmpty) return false;
    return hay.contains(nq) || _containsAllTokens(hay, tokens);
  }

  bool _matchesHubRowRanges(Map<String, dynamic> r) {
    final priceOk = _matchesHubRowAnyRange(
        r,
        const [
          'price',
          'request_price',
          'preview_price',
          'budget_min',
          'budget_max',
          'offer_price',
          'marketing_fee',
        ],
        _priceMinFilter,
        _priceMaxFilter);
    final areaOk = _matchesHubRowAnyRange(
        r,
        const [
          'area',
          'area_m2',
          'area_min_m2',
          'preview_area',
          'land_area',
        ],
        _areaMinFilter,
        _areaMaxFilter);
    return priceOk && areaOk;
  }

  /// طلبات التسويق حسب مرحلة الطلب (قبل النشر).
  List<Map<String, dynamic>> _ownerRequestRowsForTab(int tabIndex) {
    if (tabIndex >= 4) return const <Map<String, dynamic>>[];
    return _ownerListingRequests.where((r) {
      if (!_matchesHubRowSearch(r)) return false;
      if (!_matchesHubRowRanges(r)) return false;
      final decision = ListingPostPublishUiHelper.decideFromRequestRow(
          Map<String, dynamic>.from(r));
      if (decision.kind == ListingUiEntityKind.publishedProperty) return false;
      if (_rowShouldPurgeFromHub(r)) return false;
      if (tabIndex == 2) {
        return _ownerRequestRowShowsInInactive72hTab(r) ||
            ListingStageUiHelper.ownerTabMatches(tabIndex, decision.stage);
      }
      if (tabIndex == 3) {
        if (_rowShouldMoveInactiveToCancelled(r)) return true;
        return ListingStageUiHelper.ownerTabMatches(tabIndex, decision.stage);
      }
      if (tabIndex == 0 && _ownerRequestRowShowsInInactive72hTab(r)) {
        return false;
      }
      return ListingStageUiHelper.ownerTabMatches(tabIndex, decision.stage);
    }).toList();
  }

  bool _ownerRequestRowInWaitingMarketersBucket(Map<String, dynamic> r) {
    final decision = ListingPostPublishUiHelper.decideFromRequestRow(
      Map<String, dynamic>.from(r),
    );
    if (decision.kind == ListingUiEntityKind.publishedProperty) return false;
    return ListingStageUiHelper.ownerTabMatches(0, decision.stage);
  }

  bool _ownerRequestRowHasPendingMarketerOffers(Map<String, dynamic> r) {
    if (_ownerPendingOffersCountForRow(r) > 0) return true;
    final st = (r['status'] ?? r['listing_request_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return st == 'offers_received' || st == 'assigned';
  }

  bool _ownerRequestRowShowsInSubmittedOffersTab(Map<String, dynamic> r) {
    if (!_ownerRequestRowInWaitingMarketersBucket(r)) return false;
    if (_ownerRequestRowShowsInInactive72hTab(r)) return false;
    if (_ownerRequestRowHasPendingMarketerOffers(r)) return true;
    return false;
  }

  /// تبويب «لم يتخذ إجراء 72 ساعة» — مرحلة inactive أو عروض منتهية بلا سوق مفتوح.
  /// بعد «إتاحة فرصة» / إعادة للسوق (`waiting_marketers`) لا تُعاد البطاقة هنا
  /// حتى لو بقيت أعلام انتهاء عروض الجولة السابقة على الصف.
  bool _ownerRequestRowShowsInInactive72hTab(Map<String, dynamic> r) {
    final decision = ListingPostPublishUiHelper.decideFromRequestRow(
      Map<String, dynamic>.from(r),
    );
    if (decision.kind == ListingUiEntityKind.publishedProperty) return false;
    final reqId = (r['request_id'] ?? r['id'] ?? '').toString().trim();
    if (reqId.isNotEmpty && _exhaustedOpportunityRequestIds.contains(reqId)) {
      return false;
    }
    if (_rowShouldMoveInactiveToCancelled(r)) return false;
    if (_rowShouldPurgeFromHub(r)) return false;
    if (decision.stage == ListingWorkflowStage.inactive72h) return true;
    // سوق مفتوح لجولة جديدة: التبويب المناسب انتظار المسوّقين / العروض المقدمة.
    if (decision.stage == ListingWorkflowStage.waitingMarketers) {
      return false;
    }
    if (r['_owner_offers_all_expired_by_deadline'] == true) return true;
    if (r['_owner_offers_need_relist'] == true) return true;
    return false;
  }

  bool _ownerRowShowsRelistAction(Map<String, dynamic> row) {
    final wf = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(row),
    );
    if (wf.showOwnerRelist) return true;
    if (row['_owner_offers_need_relist'] == true) return true;
    if (row['_owner_offers_all_expired_by_deadline'] == true) return true;
    return false;
  }

  /// تبويب «بانتظار المسوقين» — بدون عروض مقدَّمة بعد.
  List<Map<String, dynamic>> _ownerRequestRowsWaitingNoOffers() {
    return _ownerListingRequests.where((r) {
      if (!_matchesHubRowSearch(r) || !_matchesHubRowRanges(r)) return false;
      if (!_ownerRequestRowInWaitingMarketersBucket(r)) return false;
      if (_ownerRequestRowShowsInSubmittedOffersTab(r)) return false;
      if (_ownerRequestRowShowsInInactive72hTab(r)) return false;
      return true;
    }).toList();
  }

  /// تبويب «العروض المقدمة» — وصلت عروض ولم يُعاد توجيه الطلب لتعاقد بعد.
  List<Map<String, dynamic>> _ownerRequestRowsSubmittedOffersOnly() {
    return _ownerListingRequests.where((r) {
      if (!_matchesHubRowSearch(r) || !_matchesHubRowRanges(r)) return false;
      return _ownerRequestRowShowsInSubmittedOffersTab(r);
    }).toList();
  }

  Widget _buildOwnerMyAds(
    ColorScheme cs,
    List<Property> myItems,
    TabController ctrl,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final ar = widget.isAr;
    final t0 = ar ? 'بانتظار عروض المسوقين' : 'Awaiting marketer offers';
    final t0b = ar ? 'العروض المقدمة' : 'Submitted offers';
    final t1 = ar ? 'بانتظار التصريح' : 'Awaiting permit';
    final t2 = ar ? 'لم يتخذ إجراء 72 ساعة' : 'No action (72h)';
    final t3 = ar ? 'مفسوخ / ملغى' : 'Cancelled / terminated';
    final t4 = ar ? 'العقارات المحجوزة' : 'Reserved properties';
    // ملاحظة: تم حذف تبويب «إعلاناتي المنشورة» — الإعلانات المنشورة تظهر
    // في الرئيسية وفي «إعلاناتي/طلباتي» المجاور للرئيسية.
    final t6 = ar ? 'صفقات مكتملة' : 'Completed deals';

    return Column(
      children: [
        _buildStableTabBar(
          cs: cs,
          controller: ctrl,
          showOwnerScenarioGuide: true,
          tabs: [
            _ownerTabWithBadge(
              t0,
              _ownerMyPageTabBadgeCount(0, myItems),
            ),
            _ownerTabWithBadge(
              t0b,
              _ownerMyPageTabBadgeCount(1, myItems),
            ),
            _ownerTabWithBadge(
              t1,
              _ownerMyPageTabBadgeCount(2, myItems),
            ),
            _ownerTabWithBadge(
              t2,
              _ownerMyPageTabBadgeCount(3, myItems),
            ),
            _ownerTabWithBadge(
              t3,
              _ownerMyPageTabBadgeCount(4, myItems),
            ),
            _ownerTabWithBadge(
              t4,
              _ownerMyPageTabBadgeCount(5, myItems),
            ),
            _ownerTabWithBadge(
              t6,
              _ownerMyPageTabBadgeCount(6, myItems),
            ),
          ],
        ),
        Expanded(
          child: ClipRect(
            child: _myAdsHubPreferSwipeableSubTabs
                ? TabBarView(
                    controller: ctrl,
                    physics: _myAdsHubTabViewPhysics,
                    children: [
                      _buildOwnerHubTab(
                        propertyItems: _filterOwnerHubTab(myItems, 0),
                        requestRows: _ownerRequestRowsWaitingNoOffers(),
                        emptyText: l10n.myAdsEmptyWaitingMediator,
                        ownerMarketingFeedScope: 1,
                      ),
                      _buildOwnerHubTab(
                        propertyItems: const <Property>[],
                        requestRows: _ownerRequestRowsSubmittedOffersOnly(),
                        emptyText: ar
                            ? 'لا توجد عروض مقدَّمة بعد'
                            : 'No submitted offers yet',
                        ownerMarketingFeedScope: 2,
                      ),
                      _buildOwnerHubTab(
                        propertyItems: _filterOwnerHubTab(myItems, 1),
                        requestRows: _ownerRequestRowsForTab(1),
                        emptyText: ar
                            ? 'لا توجد طلبات بانتظار إصدار التصريح حالياً'
                            : 'Nothing awaiting permit issuance right now',
                      ),
                      _buildOwnerHubTab(
                        propertyItems: _filterOwnerHubTab(myItems, 2),
                        requestRows: _ownerRequestRowsForTab(2),
                        emptyText: ar
                            ? 'لا توجد عقارات متوقفة هنا'
                            : 'Nothing in this bucket',
                      ),
                      _buildOwnerHubTab(
                        propertyItems: _filterOwnerHubTab(myItems, 3),
                        requestRows: _ownerRequestRowsForTab(3),
                        emptyText: ar
                            ? 'لا توجد عقارات مفسوخة هنا'
                            : 'Nothing cancelled here',
                      ),
                      _buildOwnerReservationsTab(l10n),
                      _buildOwnerCompletedDealsTab(myItems),
                    ],
                  )
                : AnimatedBuilder(
                    animation: ctrl,
                    builder: (context, _) {
                      return KeyedSubtree(
                        key: ValueKey<int>(ctrl.index),
                        child: _buildOwnerHubSelectedTab(
                          ctrl.index,
                          myItems: myItems,
                          l10n: l10n,
                          ar: ar,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerHubSelectedTab(
    int index, {
    required List<Property> myItems,
    required AppLocalizations l10n,
    required bool ar,
  }) {
    switch (index) {
      case 1:
        return _buildOwnerHubTab(
          propertyItems: const <Property>[],
          requestRows: _ownerRequestRowsSubmittedOffersOnly(),
          emptyText:
              ar ? 'لا توجد عروض مقدَّمة بعد' : 'No submitted offers yet',
          ownerMarketingFeedScope: 2,
        );
      case 2:
        return _buildOwnerHubTab(
          propertyItems: _filterOwnerHubTab(myItems, 1),
          requestRows: _ownerRequestRowsForTab(1),
          emptyText: ar
              ? 'لا توجد طلبات بانتظار إصدار التصريح حالياً'
              : 'Nothing awaiting permit issuance right now',
        );
      case 3:
        return _buildOwnerHubTab(
          propertyItems: _filterOwnerHubTab(myItems, 2),
          requestRows: _ownerRequestRowsForTab(2),
          emptyText:
              ar ? 'لا توجد عقارات متوقفة هنا' : 'Nothing in this bucket',
        );
      case 4:
        return _buildOwnerHubTab(
          propertyItems: _filterOwnerHubTab(myItems, 3),
          requestRows: _ownerRequestRowsForTab(3),
          emptyText:
              ar ? 'لا توجد عقارات مفسوخة هنا' : 'Nothing cancelled here',
        );
      case 5:
        return _buildOwnerReservationsTab(l10n);
      case 6:
        return _buildOwnerCompletedDealsTab(myItems);
      case 0:
      default:
        return _buildOwnerHubTab(
          propertyItems: _filterOwnerHubTab(myItems, 0),
          requestRows: _ownerRequestRowsWaitingNoOffers(),
          emptyText: l10n.myAdsEmptyWaitingMediator,
          ownerMarketingFeedScope: 1,
        );
    }
  }

  /// تربط فهرس تبويب المالك (في الواجهة) بصندوق الفلترة المستخدم في
  /// [_filterOwnerHubTab]. تم حذف تبويب «إعلاناتي المنشورة» سابقاً، لذلك
  /// أُعيد ترقيم الفهارس هنا حتى لا تنحرف الفلترة عن العَرض.
  int _ownerSubTabPropertyBucket(int displayedTabIdx) {
    switch (displayedTabIdx) {
      case 0:
        return 0; // بانتظار عروض
      case 2:
        return 1; // التعاقد (بعد الموافقة حتى التصريح)
      case 3:
        return 2; // بدون إجراء 72س
      case 4:
        return 3; // مفسوخ
      case 5:
        return 4; // المحجوزة
      case 6:
        return 6; // الصفقات المكتملة
      default:
        return 0;
    }
  }

  Widget _buildOwnerCompletedDealsTab(List<Property> myItems) {
    final items = _filterOwnerHubTab(myItems, 8);
    final hiddenN = _hiddenCompletedDealPropertyIds.length;
    final cs = Theme.of(context).colorScheme;
    final ar = widget.isAr;

    if (_loadingMine && items.isEmpty) {
      return const CartRowSkeletonList(count: 4, topPadding: 16);
    }

    if (items.isEmpty) {
      return ListView(
        physics: _myAdsHubScrollPhysics,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          if (hiddenN > 0) ...[
            Center(
              child: OutlinedButton.icon(
                onPressed: _restoreAllHiddenCompletedDeals,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(
                  ar
                      ? 'إظهار الصفقات المخفية ($hiddenN)'
                      : 'Show hidden deals ($hiddenN)',
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 40),
          Icon(
            Icons.handshake_outlined,
            size: 72,
            color: _brandPrimary.withOpacity(_op(160)),
          ),
          const SizedBox(height: 16),
          Text(
            ar ? 'لا توجد صفقات مكتملة بعد' : 'No completed deals yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            ar
                ? 'عند إتمام البيع من «صفقاتي» يُسجَّل العقار كمباع ويظهر هنا. يمكنك مراجعة التفاصيل أو إخفاء السجل أو طلب حذف الإعلان أو فتح إعلان جديد لإعادة البيع.'
                : 'When you complete a sale from the cart, the listing is marked sold and appears here. You can review details, hide this record, request deletion, or start a new listing to sell again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
        ],
      );
    }

    String thumbUrl(Property p) {
      return PropertyListingDisplay.propertyHeroNetworkUrl(p, _sb) ?? '';
    }

    return ListView(
      physics: _myAdsHubScrollPhysics,
      padding: const EdgeInsets.all(12),
      children: [
        if (hiddenN > 0) ...[
          OutlinedButton.icon(
            onPressed: _restoreAllHiddenCompletedDeals,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(
              ar ? 'إظهار المخفي ($hiddenN)' : 'Show hidden ($hiddenN)',
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildOwnerCompletedDealCard(
            items[i],
            cs,
            ar,
            thumbUrl,
          ),
        ],
      ],
    );
  }

  Widget _buildOwnerCompletedDealCard(
    Property p,
    ColorScheme cs,
    bool ar,
    String Function(Property) thumbUrl,
  ) {
    final url = thumbUrl(p);
    final code = (p.listingPublicCode ?? '').trim();
    final codePlain = code.isEmpty ? '' : DisplayIds.plainNumericOrClean(code);

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetails(p),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (ctx) {
                      final sw = MediaQuery.sizeOf(ctx).width;
                      final (w, h) = listingHeroThumbSizeForList(sw);
                      return ListingHeroThumb(
                        networkUrl: url.isEmpty ? null : url,
                        width: w,
                        height: h,
                        borderRadius: 10,
                        showVideoBadge:
                            p.showVideoAsListingCover && url.isEmpty,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ar ? 'مباع' : 'Sold',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // — قاعدة موحّدة: كل البطاقات (هنا وفي الرئيسية والسلة وصفقاتي
              //   وإعلاناتي/طلباتي للمسوّق) تعرض السعر الأساسي كما أدخله المعلن
              //   دون أي حسابات. تفصيل الفاتورة (الضريبة + العمولة + المجموع
              //   النهائي) يُعرض فقط عند الضغط على البطاقة داخل صفحة التفاصيل.
              AppMoneyLine(
                amount: p.price,
                currencyCode: p.currency,
                isAr: ar,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (codePlain.isNotEmpty)
                    InputChip(
                      avatar: Icon(Icons.tag, size: 18, color: cs.primary),
                      label: Text(
                        ar ? 'رمز الإعلان: $codePlain' : 'Listing: $codePlain',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () => _copyPlainToClipboard(
                        codePlain,
                        ar ? 'تم نسخ رمز الإعلان' : 'Listing code copied',
                      ),
                    ),
                  InputChip(
                    avatar:
                        Icon(Icons.fingerprint, size: 18, color: cs.primary),
                    label: Text(
                      ar ? 'معرّف: ${p.id}' : 'ID: ${p.id}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    onPressed: () => _copyPlainToClipboard(
                      p.id,
                      ar ? 'تم نسخ المعرّف' : 'ID copied',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openDetails(p),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(ar ? 'التفاصيل' : 'Details'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _hideCompletedDealFromOwnerHub(p.id),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: Text(ar ? 'إخفاء' : 'Hide'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openOwnerAddPropertyShortcut(),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(ar ? 'إعلان جديد' : 'New listing'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _requestDeleteProperty(p),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(ar ? 'حذف' : 'Delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerReservationsTab(AppLocalizations l10n) {
    if (_loadingOffers && _offers.isEmpty) {
      return const CartRowSkeletonList(count: 5, topPadding: 16);
    }
    if (_errorOffers != null && _offers.isEmpty) {
      return _simpleErrorBox(
        title: l10n.failedToLoadReservations,
        err: _errorOffers!,
        onRetry: () => _loadMineAndOffers(force: true),
      );
    }
    if (_offers.isEmpty) {
      return ListView(
        physics: _myAdsHubScrollPhysics,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 72,
            color: _brandPrimary.withOpacity(_op(160)),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isAr ? 'لا توجد حجوزات على إعلاناتك' : 'No reservations yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: _myAdsHubScrollPhysics,
      padding: const EdgeInsets.all(12),
      itemCount: _offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _offers[i];
        final propertyId = (r['property_id'] ?? '').toString();
        final p = _myPropertyById[propertyId];
        final stLine = (r['status'] ?? '').toString();
        final reserver = (r['reserved_by_name'] ?? '').toString().trim();
        final exp = _tryParseDt(r['expires_at']);

        return ListTile(
          isThreeLine: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          title: Text(
            p?.title ?? (widget.isAr ? 'إعلان' : 'Listing'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.isAr ? 'الحالة' : 'Status'}: $stLine',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (reserver.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.isAr ? 'حجزه: $reserver' : 'Reserved by: $reserver',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (exp != null) ...[
                const SizedBox(height: 6),
                _ReservationExpiryCountdown(
                  expiresAt: exp,
                  isAr: widget.isAr,
                ),
              ],
            ],
          ),
          trailing: Icon(Icons.chevron_right, color: _brandPrimary),
          onTap: () {
            if (p != null) _openDetails(p);
          },
        );
      },
    );
  }

  /// طلبات listing_requests (مثلاً مستخدم غير موثّق) + عقارات properties في نفس التبويب.
  Widget _buildOwnerHubTab({
    required List<Property> propertyItems,
    required List<Map<String, dynamic>> requestRows,
    required String emptyText,
    int ownerMarketingFeedScope = 0,
  }) {
    final hasReq = requestRows.isNotEmpty;
    final hasProp = propertyItems.isNotEmpty;

    if (_loadingOwnerRequests && !hasReq && !hasProp) {
      return _buildTabLoadingState(
        title: widget.isAr
            ? 'جارٍ تحميل طلبات الإعلان'
            : 'Loading listing requests',
      );
    }

    if (!hasReq && !hasProp) {
      return _buildOwnerPublishedPropertiesList(
        items: propertyItems,
        emptyText: emptyText,
      );
    }

    // طلب تسويق يعرض صور/بيانات من صف الطلب + المعاينة؛ هذا ليس «إعلان عقار» في القائمة السفلية.
    // إن وُجد طلب ولم يُطابق أي Property نفس التبويب، لا نعرض رسالة «لا يوجد عقار» تحت البطاقة.
    if (hasReq && !hasProp) {
      final bottomPad = _marketerHubScrollBottomPadding(context);
      return _myAdsHubScrollWrap(
        ListView(
          physics: _myAdsHubScrollPhysics,
          cacheExtent: _myAdsHubListCacheExtent,
          padding: EdgeInsets.fromLTRB(8, 4, 8, bottomPad),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: Text(
                widget.isAr
                    ? 'طلبات التسويق (بدون عقار مباشر أو قيد المراجعة)'
                    : 'Marketing requests',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ..._ownerMarketingRequestTiles(
              requestRows,
              ownerMarketingFeedScope: ownerMarketingFeedScope,
            ),
          ],
        ),
      );
    }

    final bottomPad = _marketerHubScrollBottomPadding(context);
    final children = <Widget>[];
    if (hasReq) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Text(
            widget.isAr
                ? 'طلبات التسويق (بدون عقار مباشر أو قيد المراجعة)'
                : 'Marketing requests',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      children.addAll(
        _ownerMarketingRequestTiles(
          requestRows,
          ownerMarketingFeedScope: ownerMarketingFeedScope,
        ),
      );
    }
    if (hasReq && hasProp) {
      children.add(const Divider(height: 20));
    }
    if (hasProp) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(
            widget.isAr ? 'إعلاناتك كعقار' : 'Your listings',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      children.addAll(_ownerPublishedPropertyTiles(propertyItems));
    }
    return _myAdsHubScrollWrap(
      ListView(
        physics: _myAdsHubScrollPhysics,
        cacheExtent: _myAdsHubListCacheExtent,
        padding: EdgeInsets.fromLTRB(8, 4, 8, bottomPad),
        children: children,
      ),
    );
  }

  List<Widget> _ownerMarketingRequestTiles(
    List<Map<String, dynamic>> requestRows, {
    int ownerMarketingFeedScope = 0,
  }) {
    final useGrid = _useGridLayout(context);
    if (!useGrid) {
      return [
        for (var i = 0; i < requestRows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildOwnerListingRequestCard(
            requestRows[i],
            horizontalLayout: true,
            ownerMarketingFeedScope: ownerMarketingFeedScope,
          ),
        ],
      ];
    }
    final cross = _hubPropertyCrossAxisCount(MediaQuery.sizeOf(context).width);
    const spacing = 10.0;
    final tiles = <Widget>[];
    for (var start = 0; start < requestRows.length; start += cross) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: spacing));
      final end = start + cross > requestRows.length
          ? requestRows.length
          : start + cross;
      final chunk = requestRows.sublist(start, end);
      tiles.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cross; j++) ...[
                if (j > 0) const SizedBox(width: spacing),
                Expanded(
                  child: j < chunk.length
                      ? _buildOwnerListingRequestCard(
                          chunk[j],
                          horizontalLayout: true,
                          ownerMarketingFeedScope: ownerMarketingFeedScope,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return tiles;
  }

  List<Widget> _ownerPublishedPropertyTiles(List<Property> items) {
    final useGrid = _useGridLayout(context);
    if (!useGrid) {
      return [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildOwnerPublishedPropertyCard(items[i]),
        ],
      ];
    }
    final cross = _hubPropertyCrossAxisCount(MediaQuery.sizeOf(context).width);
    const spacing = 12.0;
    final tiles = <Widget>[];
    for (var start = 0; start < items.length; start += cross) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: spacing));
      final end = start + cross > items.length ? items.length : start + cross;
      final chunk = items.sublist(start, end);
      tiles.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cross; j++) ...[
                if (j > 0) const SizedBox(width: spacing),
                Expanded(
                  child: j < chunk.length
                      ? _buildOwnerPublishedPropertyCard(chunk[j])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return tiles;
  }

  /// عرض الصور في بطاقة طلب التسويق: نفس منطق دمج المسوّقين (معاينة ثم payload).
  List<String> _effectiveImageUrlsForOwnerRequestRow(
    Map<String, dynamic> row,
  ) {
    final payload = _mergedJsonPayloadForRow(row);
    final payloadPaths = ListingMediaUrls.imagePathsExcludingVideo(
      _payloadImagePaths(payload),
    );
    if (row['default_cover_used'] == true && payloadPaths.isEmpty) {
      return const [];
    }
    final fromPayloadUrls = payloadPaths
        .map((p) {
          final s = p.toString().trim();
          if (s.isEmpty) return '';
          if (s.startsWith('http://') || s.startsWith('https://')) return s;
          return _sb.storage.from('property-images').getPublicUrl(s);
        })
        .where((s) => s.isNotEmpty)
        .toList();
    final mergedDyn = _mergeImageUrlLists(
      row['preview_image_urls'],
      fromPayloadUrls,
    );
    final direct = ListingMediaUrls.imagePathsExcludingVideo(
      mergedDyn.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
    );
    List<String> toPublic(Iterable<String> raw) {
      return raw
          .map((u) {
            if (u.startsWith('http://') || u.startsWith('https://')) {
              return u;
            }
            return _sb.storage.from('property-images').getPublicUrl(u);
          })
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    if (direct.isNotEmpty) {
      return toPublic(direct);
    }
    return <String>[];
  }

  Property? _propertyFromLocalCaches(String propertyId) {
    final pid = propertyId.trim();
    if (pid.isEmpty) return null;
    final cached = _propertyCache[pid] ?? _myPropertyById[pid];
    if (cached != null) return cached;
    for (final p in _mine) {
      if (p.id == pid) return p;
    }
    for (final p in _all) {
      if (p.id == pid) return p;
    }
    return null;
  }

  Property? _ownerPropertyByListingPublicCode(String code) {
    final c = code.trim();
    if (c.isEmpty) return null;
    for (final p in _mine) {
      if ((p.listingPublicCode ?? '').trim() == c) return p;
    }
    for (final p in _all) {
      if ((p.listingPublicCode ?? '').trim() == c) return p;
    }
    return null;
  }

  Property? _linkedPropertyForOwnerRequestCard(Map<String, dynamic> row) {
    final pid = (row['preview_property_id'] ??
            row['property_id'] ??
            row['linked_property_id'] ??
            '')
        .toString()
        .trim();
    if (pid.isNotEmpty) {
      final cached = _propertyFromLocalCaches(pid);
      if (cached != null) return cached;
    }
    final code = (row['preview_listing_public_code'] ??
            row['listing_request_public_code'] ??
            row['listing_public_code'] ??
            '')
        .toString()
        .trim();
    return _ownerPropertyByListingPublicCode(code);
  }

  int _ownerPendingOffersCountForRow(Map<String, dynamic> row) {
    final v = row['_owner_pending_offers_count'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  /// يظهر للمالك سطر «جهة التسويق» بعد اختيار/موافقة أو عقد أو نشر بوسيط (لا يُعرض مبكراً في «بانتظار المسوقين» فقط).
  bool _ownerRowShowsApprovedMarketerContact(Map<String, dynamic> row) {
    if ((row['selected_marketer_id'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    if ((row['contract_id'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    final pubBy = (row['preview_published_by_marketer_id'] ??
            row['published_by_marketer_id'] ??
            '')
        .toString()
        .trim();
    if (pubBy.isNotEmpty) return true;
    final st =
        (row['status'] ?? row['request_status'] ?? '').toString().toLowerCase();
    return st == 'owner_accepted' ||
        st == 'converted_to_contract' ||
        st == 'contract_signed' ||
        st == 'published';
  }

  List<Map<String, dynamic>> _ownerPendingOffersPreviewSlice(
      Map<String, dynamic> row) {
    final v = row['_owner_pending_offers_preview'];
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['id'] ?? '').toString().trim().isNotEmpty)
        .take(8)
        .toList();
  }

  /// بعد أي إجراء مسار (قبول/رفض/إعادة/نشر): إبطال الكاش + إعادة تحميل + انتقال تبويب.
  Future<void> _refreshMyPageHubAfterAction({
    int? ownerTabIndex,
    int? marketerTabIndex,
    bool notifyHub = true,
  }) async {
    if (!mounted) return;
    if (_isMarketerRole) {
      MarketingBucketsCache.instance.invalidateMarketer(_uid);
      MarketingBucketsCache.instance.invalidateOwner(_uid);
    } else {
      MarketingBucketsCache.instance.invalidateOwner(_uid);
    }
    if (notifyHub) {
      MarketingWorkflowHub.notifyBucketsChanged();
    }
    try {
      if (_isMarketerRole) {
        final asPublisher = ownerTabIndex != null;
        if (asPublisher) {
          if (mounted) {
            setState(() => _setMarketerPublisherHubMode(1));
          }
          await Future.wait([
            _loadOwnerRequestsBuckets(force: true),
            _loadMarketerBuckets(force: true, silent: true),
          ]);
          if (!mounted) return;
          _ensureSubTabControllers();
          final ctrl = _ownerTabsCtrl;
          final idx = ownerTabIndex;
          if (ctrl != null &&
              idx != null &&
              idx >= 0 &&
              idx < ctrl.length &&
              ctrl.index != idx) {
            ctrl.animateTo(idx);
          }
        } else {
          if (mounted && marketerTabIndex != null) {
            setState(() => _setMarketerPublisherHubMode(0));
          }
          await _loadMarketerBuckets(force: true);
          if (_hasOwnerRequestsData) {
            unawaited(_loadOwnerRequestsBuckets(force: true, silent: true));
          }
          if (!mounted) return;
          _ensureSubTabControllers();
          final ctrl = _marketerTabsCtrl;
          final idx = marketerTabIndex;
          if (ctrl != null &&
              idx != null &&
              idx >= 0 &&
              idx < ctrl.length &&
              ctrl.index != idx) {
            ctrl.animateTo(idx);
          }
        }
      } else if (!_isGuest) {
        await _loadOwnerRequestsBuckets(force: true);
        if (mounted) await _loadMineAndOffers(force: true);
        if (!mounted) return;
        _ensureSubTabControllers();
        final ctrl = _ownerTabsCtrl;
        final idx = ownerTabIndex;
        if (ctrl != null &&
            idx != null &&
            idx >= 0 &&
            idx < ctrl.length &&
            ctrl.index != idx) {
          ctrl.animateTo(idx);
        }
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _ownerAfterOfferMutation() {
    // قبول العرض → تبويب «بانتظار التصريح» (فهرس 2) بعد بيانات طازجة + تحديث الشارات.
    unawaited(_refreshMyPageHubAfterAction(
      ownerTabIndex: 2,
      marketerTabIndex: 2,
      notifyHub: true,
    ));
  }

  Future<void> _ownerAcceptOfferInline(String offerId) async {
    final id = offerId.trim();
    if (id.isEmpty) return;
    _ss(() => _ownerHubInlineOfferBusyId = id);
    try {
      await MarketingFlowService(_sb).acceptListingOfferById(id);
      if (!mounted) return;
      _ownerAfterOfferMutation();
      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        ListingWorkflowCopy.snackOfferAccepted(widget.isAr),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final friendly = raw.contains('offer_status') || raw.contains('22P02')
          ? (widget.isAr
              ? 'تعذّر قبول العرض بسبب إعدادات الخادم. جرّب بعد تحديث النظام أو تواصل مع الدعم.'
              : 'Could not accept the offer due to a server configuration issue. Try again after a system update or contact support.')
          : raw;
      _showNotification(
        widget.isAr ? 'تعذر القبول' : 'Could not accept',
        friendly,
        isError: true,
      );
    } finally {
      if (mounted) _ss(() => _ownerHubInlineOfferBusyId = null);
    }
  }

  Future<void> _ownerDeclineOfferInline(
    String offerId,
    String requestId,
  ) async {
    final oid = offerId.trim();
    final rid = requestId.trim();
    if (oid.isEmpty || rid.isEmpty) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: widget.isAr ? 'رفض العرض' : 'Decline offer',
      message: widget.isAr
          ? 'سيتم رفض هذا العرض وإبلاغ المسوّق. هل تؤكد؟'
          : 'This offer will be declined and the marketer notified. Continue?',
      confirmLabel: widget.isAr ? 'رفض' : 'Decline',
      cancelLabel: widget.isAr ? 'تراجع' : 'Back',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    _ss(() => _ownerHubInlineOfferBusyId = oid);
    try {
      await MarketingFlowService(_sb).ownerDeclineOffer(
        offerId: oid,
        requestId: rid,
      );
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        ListingWorkflowCopy.snackOfferDeclined(widget.isAr),
      );
      await _refreshMyPageHubAfterAction(notifyHub: false);
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر الرفض' : 'Could not decline',
        e.toString(),
        isError: true,
      );
    } finally {
      if (mounted) _ss(() => _ownerHubInlineOfferBusyId = null);
    }
  }

  /// تبويب «العروض المقدمة»: مراجعة كاملة + قبول/رفض سريع تحت البطاقة عند توفر المعاينة.
  Widget _buildOwnerSingleMarketerOffersFooter(
    Map<String, dynamic> row,
    String requestId,
  ) {
    final n = _ownerPendingOffersCountForRow(row);
    final ar = widget.isAr;
    final previews = _ownerPendingOffersPreviewSlice(row);
    final cs = Theme.of(context).colorScheme;

    String priceLine(Map<String, dynamic> o) {
      final raw = o['offer_price'] ?? o['offer_amount'] ?? o['price'];
      final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (v == null || v <= 0) {
        return ar ? 'عرض سعري' : 'Priced offer';
      }
      return AppMoney.formatWithCurrencyCode(v, isAr: ar);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (previews.isNotEmpty) ...[
            Text(
              ar ? 'عروض على هذا الطلب' : 'Offers on this request',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < previews.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Builder(
                builder: (ctx) {
                  final o = previews[i];
                  final oid = (o['id'] ?? '').toString().trim();
                  final busy = _ownerHubInlineOfferBusyId == oid;
                  return Material(
                    color: cs.surfaceContainerHighest.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ar
                                ? (o['is_repeat_offer'] == true
                                    ? 'عرض للمرة الثانية — ${priceLine(o)}'
                                    : 'عرض ${i + 1} — ${priceLine(o)}')
                                : (o['is_repeat_offer'] == true
                                    ? 'Second-time offer — ${priceLine(o)}'
                                    : 'Offer ${i + 1} — ${priceLine(o)}'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              final mid =
                                  (o['marketer_id'] ?? '').toString().trim();
                              if (mid.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: UserPresenceStrip(
                                  userId: mid,
                                  isAr: ar,
                                  compact: true,
                                  surface: PresenceDisplaySurface.listingCards,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: busy || oid.isEmpty
                                      ? null
                                      : () => unawaited(
                                            _ownerAcceptOfferInline(oid),
                                          ),
                                  child: Text(
                                    ar ? 'قبول' : 'Accept',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy || oid.isEmpty
                                      ? null
                                      : () => unawaited(
                                            _ownerDeclineOfferInline(
                                              oid,
                                              requestId,
                                            ),
                                          ),
                                  child: Text(
                                    ar ? 'رفض' : 'Decline',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: requestId.isEmpty
                ? null
                : () => unawaited(_openOwnerOffersForRequest(requestId)),
            icon: const Icon(Icons.groups_outlined),
            label: Text(
              ar
                  ? (n > 0 ? 'عروض المسوقين ($n)' : 'عروض المسوقين')
                  : (n > 0 ? 'Marketer offers ($n)' : 'Marketer offers'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Property _propertyForOwnerMarketingCardRow(
    Map<String, dynamic> row, {
    Property? linked,
  }) {
    if (linked != null) {
      final reqPub =
          (row['listing_request_public_code'] ?? '').toString().trim();
      final propPub = (linked.listingPublicCode ?? '').trim();
      if (propPub.isEmpty &&
          reqPub.length == 10 &&
          RegExp(r'^[0-9]{10}$').hasMatch(reqPub)) {
        return linked.copyWith(listingPublicCode: reqPub);
      }
      return linked;
    }
    final rid = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    final urls = _effectiveImageUrlsForOwnerRequestRow(row);
    final wfCtx = ListingWorkflowUiContext.fromListingRequest(row);
    final title =
        (row['request_title'] ?? row['title'] ?? '').toString().trim();
    final fallbackTitle =
        PropertyListingDisplay.purposeLabelForRequestRow(row, widget.isAr);
    final city = PropertyListingDisplay.cityLineFromRequestRow(row);
    final typeKey =
        (row['preview_type'] ?? row['request_property_type'] ?? 'villa')
            .toString();
    final priceRaw = row['preview_price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse('$priceRaw') ?? 0;
    final areaRaw = row['preview_area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;
    final reqCode =
        (row['listing_request_public_code'] ?? '').toString().trim();
    return Property(
      id: rid.isNotEmpty ? rid : 'owner-req-preview',
      ownerId: _uid,
      title: title.isNotEmpty ? title : fallbackTitle,
      type: Property.parseType(typeKey),
      listingTypeKey: PropertyTypeCatalog.normalize(typeKey),
      description:
          (row['preview_description'] ?? row['request_description'] ?? '')
              .toString(),
      city: city == '-' ? '' : city,
      area: area,
      price: price,
      isAuction: row['preview_is_auction'] == true,
      images: urls,
      views: (row['preview_views'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${row['created_at']}') ??
          DateTime.tryParse('${row['request_created_at']}') ??
          DateTime.now(),
      workflowStage: wfCtx.stage.wireValue,
      purpose: PropertyListingDisplay.purposeCodeFromRequestRow(row),
      listingPublicCode:
          reqCode.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(reqCode)
              ? reqCode
              : null,
      currency: (row['preview_currency'] ?? 'SAR').toString(),
    );
  }

  Widget _buildOwnerHubRealEstateCard({
    required Map<String, dynamic> row,
    required Property property,
    required VoidCallback onOpenDetails,
    required Widget belowMainRow,
    required List<Widget> footerActions,
  }) {
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    final uid = _uid.isEmpty ? 'guest' : _uid;
    final regulatory = _ownerHubListingShowsRegulatory(property);
    final tail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        belowMainRow,
        if (footerActions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildSmartMarketerActionBar(footerActions),
          ),
      ],
    );
    return RepaintBoundary(
      key: id.isNotEmpty
          ? _hubCardKeyForRequest(id)
          : ValueKey<String>('hub_owner_card_${property.id}'),
      child: _RealEstateCard(
        property: property,
        isOwner: true,
        isAr: widget.isAr,
        bankColor: _brandPrimary,
        favorite: false,
        onToggleFav: () {},
        onOpenDetails: onOpenDetails,
        isReserved: false,
        reservedUntil: null,
        reservedByName: null,
        onAddToCart: null,
        currentUserId: uid,
        timeAgo: _timeAgo,
        relaxTextTruncation: true,
        canShowCartButton: false,
        showRegulatoryIdentityOnCard: regulatory,
        omitMarketingLicenseEntriesOnCard: true,
        suppressPublicOwnerIdentity: true,
        showFullOwnerLegalNameOnCard: true,
        ownerHubListingCard: true,
        cardBelowMainRow: tail,
      ),
    );
  }

  /// بطاقة «صفحتي» للمالك — نفس تخطيط بطاقة المسوّق الموحّدة (بدون اسم/جوال المعلن على البطاقة).
  Widget _buildOwnerHubUnifiedMarketingCard({
    required Map<String, dynamic> row,
    required ListingWorkflowUiContext wfCtx,
    required VoidCallback onOpenDetails,
    Property? linkedProperty,
    Widget? belowMainRow,
    List<Widget>? footerActions,
  }) {
    final cs = Theme.of(context).colorScheme;
    final merged = Map<String, dynamic>.from(row);
    if (linkedProperty != null) {
      if (merged['preview_price'] == null && linkedProperty.price > 0) {
        merged['preview_price'] = linkedProperty.price;
      }
      final pc = merged['preview_currency']?.toString().trim();
      if (pc == null || pc.isEmpty) {
        merged['preview_currency'] = linkedProperty.currency;
      }
    }
    final id = (merged['request_id'] ?? merged['id'] ?? '').toString().trim();
    final urlsFromProp = linkedProperty != null
        ? PropertyListingDisplay.propertyCardImagePaths(linkedProperty)
        : const <String>[];
    final urlsFromRow = _effectiveImageUrlsForOwnerRequestRow(merged);
    final urls = ListingMediaUrls.mergePathLists([urlsFromProp, urlsFromRow]);
    final previewViews = (merged['preview_views'] as num?)?.toInt() ??
        (linkedProperty != null ? linkedProperty.views : null);
    final mergedReq = _mergedJsonPayloadForRow(merged);
    final vidRow =
        (mergedReq['request_video_path'] ?? mergedReq['video_url'] ?? '')
            .toString()
            .trim();
    final vidProp = (linkedProperty?.videoUrl ?? '').trim();
    final vidRaw = vidRow.isNotEmpty ? vidRow : vidProp;
    var coverVid = false;
    final lgReq = mergedReq['listing_guidance'];
    if (lgReq is Map) {
      final c = (lgReq['cover_primary'] ?? 'image').toString().toLowerCase();
      coverVid = c == 'video';
    }
    // إن وُجدت صور حقيقية لا تُقدَّم فيديو الغلاف تلقائياً (إلا بطلب صريح).
    if (urls.isNotEmpty && !coverVid) {
      coverVid = false;
    }
    final purposeLabel =
        PropertyListingDisplay.purposeLabelForRequestRow(merged, widget.isAr);
    final requestTitle = PropertyListingDisplay.sanitizeListingTitle(
      (merged['request_title'] ?? merged['title'] ?? '').toString().trim(),
      typeLabel: PropertyListingDisplay.typeLabelForRequestRow(
        merged,
        widget.isAr,
      ),
      isAr: widget.isAr,
    );
    final propTitle = linkedProperty != null
        ? PropertyListingDisplay.displayListingTitle(
            linkedProperty,
            widget.isAr,
          )
        : '';
    // الموضوع أولاً — من بيانات العقار نفسه عند الربط، بدون لاحقات نوع متعارضة.
    final title = propTitle.isNotEmpty
        ? propTitle
        : (requestTitle.isNotEmpty
            ? requestTitle
            : (purposeLabel.trim().isNotEmpty
                ? purposeLabel
                : (widget.isAr ? 'طلب تسويق' : 'Marketing request')));
    final locationText = linkedProperty != null
        ? _propertyCardLocationLine(linkedProperty)
        : _marketingLocationText(merged);
    final statusWire = wfCtx.stage.wireValue;
    final statusLabel =
        _trMarketingStatus(statusWire, ownerHubPerspective: true);
    final statusColor = _marketingStatusColor(statusWire, cs);
    final purposeAccent = PropertyListingDisplay.accentForRequestRow(merged);
    final typeKey =
        (merged['preview_type'] ?? merged['request_property_type'] ?? '')
            .toString()
            .trim();
    final typeAccent =
        typeKey.isEmpty ? cs.primary : PropertyTypeCatalog.accentFor(typeKey);
    final typeLabel = typeKey.isEmpty
        ? ''
        : (widget.isAr
            ? _trPropertyTypeAr(typeKey)
            : _trPropertyTypeEn(typeKey));
    final deedNo = _hubDeedNumberFromRow(merged, linkedProperty);
    final deedDate = _hubDeedDateFromRow(merged, linkedProperty);
    final roundNo = (merged['marketing_round'] as num?)?.toInt() ?? 1;
    final opportunityGranted = _ownerRequestHasOpportunityGrant(merged);
    final relisted = roundNo > 1 ||
        _allowPreviousMarketersRetryOnRequest(merged) ||
        opportunityGranted;
    final relistTooltip = relisted ? _ownerRelistHoverText(merged) : '';
    final reofferBadgeLabel = opportunityGranted
        ? (widget.isAr ? 'فرصة' : 'Chance')
        : (widget.isAr ? 'معادة' : 'Relisted');

    Map<String, dynamic>? snapMap;
    final rawSnap = merged['preview_marketing_license_snapshot'] ??
        merged['marketing_license_snapshot'];
    if (rawSnap is Map) {
      snapMap = Map<String, dynamic>.from(rawSnap);
    } else if (rawSnap is String && rawSnap.trim().startsWith('{')) {
      try {
        final d = jsonDecode(rawSnap);
        if (d is Map) snapMap = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    final marketerTop =
        Property.marketerEntityLineFromLicenseSnapshot(snapMap, widget.isAr);

    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    final propPublished = parseDt(merged['preview_published_at']);
    final lrReqPub =
        (merged['listing_request_public_code'] ?? '').toString().trim();
    final listingTen = _hubTenDigitPublicListingCodeRaw(merged);
    final reqTen =
        (lrReqPub.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(lrReqPub))
            ? lrReqPub
            : null;
    final duplicateListingAndRequestTen =
        reqTen != null && listingTen != null && reqTen == listingTen;
    final showMarketingRequestRow =
        lrReqPub.isNotEmpty && !duplicateListingAndRequestTen;
    final subtitleRaw =
        (merged['request_title'] ?? merged['title'] ?? '').toString().trim();
    // لا تكرر الموضوع إن كان هو العنوان الرئيسي.
    final subtitle = (subtitleRaw.isNotEmpty &&
            !_hubTextLooksLikeDuplicateTitle(subtitleRaw, title) &&
            subtitleRaw != purposeLabel)
        ? subtitleRaw
        : '';
    final areaRaw = merged['preview_area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;
    final areaIc = PropertyListingDisplay.areaIconForRequestRow(merged);

    final ownerTrackTap = !_isGuest && !_isMarketerRole && id.isNotEmpty
        ? () => _showOwnerRequestActivityDialog(merged)
        : null;

    final imageColumn = _buildMarketingPreviewImage(
      urls,
      type: 'invite',
      views: previewViews,
      videoStoragePath:
          (vidRaw.isNotEmpty && (urls.isEmpty || coverVid)) ? vidRaw : null,
      coverPrefersVideo: coverVid,
      showTrackingMark: ownerTrackTap != null,
      onImageTrackingTap: ownerTrackTap,
      showInviteSeenEye: false,
      showReofferBadge: relisted,
      reofferBadgeLabel: reofferBadgeLabel,
      reofferReason: relistTooltip,
      onReofferHelpTap:
          relisted ? () => _showMarketRelistReasonDialog(merged) : null,
    );

    final dataColumn = Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (_, c) {
              final mw =
                  c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mw),
                  child: Text(
                    title,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      height: 1.25,
                      color: Color(0xFF041D18),
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              );
            },
          ),
          if (purposeLabel.trim().isNotEmpty &&
              purposeLabel.trim() != title.trim()) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: purposeAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: purposeAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  purposeLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    color: purposeAccent,
                  ),
                ),
              ),
            ),
          ],
          if (typeLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.home_work_outlined, size: 15, color: typeAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!_isMarketerRole &&
              wfCtx.isPublishedPublic &&
              _ownerRowShowsApprovedMarketerContact(merged) &&
              marketerTop != null &&
              marketerTop.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.business_outlined, size: 17, color: purposeAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final mw = c.maxWidth.isFinite && c.maxWidth > 0
                          ? c.maxWidth
                          : 9999.0;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: mw),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'جهة التسويق العقاري'
                                    : 'Marketing entity',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                marketerTop.trim(),
                                maxLines: 2,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: cs.onSurface,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          _hubMarketerListingIdRow(merged, cs, listingIdGreen: true),
          if (showMarketingRequestRow) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (ctx) {
                final code = DisplayIds.tenDigit(lrReqPub);
                return _hubLabeledMetricRow(
                  ctx,
                  icon: Icons.assignment_outlined,
                  label:
                      widget.isAr ? 'رقم طلب التسويق' : 'Marketing request no.',
                  value: code,
                  copyPlain: code,
                  valueMaxLines: 1,
                  valueAllowWrap: false,
                );
              },
            ),
          ],
          if (locationText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final mw = c.maxWidth.isFinite && c.maxWidth > 0
                          ? c.maxWidth
                          : 9999.0;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: mw),
                          child: Text(
                            locationText,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          if (area > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(areaIc, size: 15, color: purposeAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final mw = c.maxWidth.isFinite && c.maxWidth > 0
                          ? c.maxWidth
                          : 9999.0;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: mw),
                          child: Text(
                            widget.isAr
                                ? '${AppMoney.formatNumber(area, isAr: false, maxFractionDigits: 0)} م²'
                                : '${AppMoney.formatNumber(area, isAr: false, maxFractionDigits: 0)} m²',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          if (deedNo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.isAr ? 'رقم الصك: $deedNo' : 'Deed no.: $deedNo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (deedDate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event_available_outlined,
                    size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.isAr
                        ? 'تاريخ الصك: $deedDate'
                        : 'Deed date: $deedDate',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          _hubPeerPresenceStrip(
            merged,
            marketerView: false,
            showMarketerName: true,
          ),
          _hubRequestCreatedDateTimeRow(merged, cs),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (_, c) {
                final mw =
                    c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: mw),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          if (wfCtx.isPublishedPublic && propPublished != null) ...[
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (_, c) {
                final mw =
                    c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: mw),
                    child: Text(
                      widget.isAr
                          ? 'نشر الطلب: ${_timeAgo(propPublished, widget.isAr)}'
                          : 'Request published: ${_timeAgo(propPublished, widget.isAr)}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, c) {
              final mw =
                  c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mw),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: statusColor.withOpacity(0.35)),
                        ),
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (merged['_owner_has_repeat_pending_offer'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: cs.tertiary.withOpacity(0.35)),
                          ),
                          child: Text(
                            widget.isAr
                                ? 'عرض للمرة الثانية'
                                : 'Second-time offer',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          _hubMarketerPriceStrip(merged, cs),
        ],
      ),
    );

    final fa = footerActions ?? const <Widget>[];

    return RepaintBoundary(
      key: id.isNotEmpty
          ? _hubCardKeyForRequest(id)
          : ValueKey<String>(
              'hub_owner_unified_${(merged['id'] ?? '').toString()}',
            ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: UnifiedRealEstateCard(
          decoration: _homeFeedCardFaceDecoration(
            cs: cs,
            typeAccent: typeAccent,
            purposeAccent: purposeAccent,
            borderHint: cs.outlineVariant,
            borderStrong: Color.alphaBlend(
              typeAccent.withValues(alpha: 0.35),
              Color.alphaBlend(
                purposeAccent.withValues(alpha: 0.28),
                _kAqarBrandPrimary.withValues(alpha: 0.45),
              ),
            ),
            borderWidth: 1.45,
          ),
          isAr: widget.isAr,
          kind: UnifiedCardKind.request,
          onCardTap: onOpenDetails,
          belowMainRow: belowMainRow,
          cardRadius: _kHomeCardRadius,
          dataColumn: dataColumn,
          imageColumn: imageColumn,
          // صورة بعرض كامل أعلى البيانات — نسبة أقصر لتفادي فراغ رأسي.
          fullWidthHeroImage: !_homeListingCardsUseSideBySideLayout(context),
          heroAspectRatio: _homeListingHeroAspectRatio(context),
          footer: fa.isEmpty ? null : _buildSmartMarketerActionBar(fa),
        ),
      ),
    );
  }

  Widget _buildOwnerLinkedPropertyCard(
    Map<String, dynamic> row,
    Property property,
    ListingWorkflowUiContext wfCtx, {
    int ownerMarketingFeedScope = 0,
  }) {
    final l10n = AppLocalizations.of(context);
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    final inContractingTab =
        ListingStageUiHelper.ownerTabMatches(1, wfCtx.stage);
    final inWaitingMarketersHub =
        ListingStageUiHelper.ownerTabMatches(0, wfCtx.stage);

    final reqPub = (row['listing_request_public_code'] ?? '').toString().trim();
    final propPub = (property.listingPublicCode ?? '').trim();
    final Property cardProperty = propPub.isNotEmpty
        ? property
        : (reqPub.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(reqPub)
            ? property.copyWith(listingPublicCode: reqPub)
            : property);

    void open() {
      if (id.isNotEmpty) {
        unawaited(
          _openOwnerListingRequestFromRow(row, requestStatusId: id),
        );
      } else {
        unawaited(_openDetails(cardProperty));
      }
    }

    final Widget? waitingFooter = !inWaitingMarketersHub
        ? null
        : (ownerMarketingFeedScope == 1
            ? null
            : (ownerMarketingFeedScope == 2
                ? _buildOwnerSingleMarketerOffersFooter(row, id)
                : null));

    final belowMain = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waitingFooter != null) waitingFooter,
        Padding(
          padding:
              EdgeInsets.fromLTRB(12, waitingFooter != null ? 6 : 4, 12, 8),
          child: ListingWorkflowProgressStrip(
            stage: wfCtx.stage,
            compact: true,
            dense: true,
            deadline: wfCtx.primaryDeadline,
            permitSoundContextId: id.isEmpty ? null : id,
          ),
        ),
      ],
    );

    final actions = <Widget>[];
    final showPeerChat = !inWaitingMarketersHub && _ownerPeerChatReady(row);
    if (!inWaitingMarketersHub) {
      if (inContractingTab) {
        if (showPeerChat) {
          actions.add(
            FilledButton.icon(
              onPressed: () => unawaited(_openOwnerChatWithMarketerForRow(row)),
              icon: const Icon(Icons.chat_bubble_outline, size: 22),
              label: Text(
                widget.isAr ? 'دردشة مع المسوّق' : 'Chat with marketer',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
              ),
            ),
          );
        } else if (MarketingWorkflowUiConfig.contractsSigningEnabled) {
          final contractId = (row['contract_id'] ?? '').toString().trim();
          if (contractId.isNotEmpty) {
            actions.add(
              FilledButton.icon(
                onPressed: () => unawaited(_openOwnerContractChat(contractId)),
                icon: const Icon(Icons.description_outlined, size: 22),
                label: Text(
                  widget.isAr ? 'مراجعة العقد' : 'Review contract',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                ),
              ),
            );
          }
        }
      } else if (wfCtx.showOwnerOffersEntry) {
        actions.add(
          FilledButton.icon(
            onPressed: id.isEmpty
                ? null
                : () => unawaited(_openOwnerOffersForRequest(id)),
            icon: const Icon(Icons.rate_review_outlined, size: 22),
            label: Text(
              l10n?.ownerBtnRealEstateOffers ??
                  (widget.isAr ? 'العروض العقارية' : 'Real estate offers'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        );
      }
      if (_ownerRowShowsRelistAction(row)) {
        actions.add(
          Padding(
            padding: EdgeInsets.only(top: actions.isNotEmpty ? 10 : 0),
            child: OutlinedButton.icon(
              onPressed: id.isEmpty
                  ? null
                  : () => unawaited(_ownerRelistMarketingRequestFromRow(row)),
              icon: const Icon(Icons.storefront_outlined, size: 22),
              label: Text(
                widget.isAr ? 'إعادة للسوق العقاري' : 'Relist to market',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
              ),
            ),
          ),
        );
      }
    }

    return _buildOwnerHubUnifiedMarketingCard(
      row: row,
      wfCtx: wfCtx,
      onOpenDetails: open,
      linkedProperty: cardProperty,
      belowMainRow: belowMain,
      footerActions: actions,
    );
  }

  /// «صفحتي» فقط: عنوان صغير فوق القيمة، أيقونة اختيارية، نسخ للأرقام، قيمة بخط غامق دون التفاف غير ضروري.
  Widget _hubLabeledMetricRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? copyPlain,
    int valueMaxLines = 2,
    bool valueAllowWrap = false,
    bool showLeadingIcon = true,
  }) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final ar = widget.isAr;
    final copyTrim = (copyPlain ?? '').trim();
    final showCopy = copyTrim.isNotEmpty;
    final toCopy = showCopy ? copyTrim : v;

    final valueStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 14,
      height: 1.2,
      color: cs.onSurface,
    );

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );

    final valueBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                v,
                maxLines: valueMaxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: valueAllowWrap,
                style: valueStyle,
              ),
            ),
            if (showCopy)
              IconButton(
                tooltip: ar ? 'نسخ' : 'Copy',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.copy_rounded, color: cs.primary),
                onPressed: () => _copyPlainToClipboard(
                  toCopy,
                  ar ? 'تم النسخ' : 'Copied',
                ),
              ),
          ],
        ),
      ],
    );

    if (!showLeadingIcon) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: valueBlock,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2),
            child: Icon(icon, size: 17, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(child: valueBlock),
        ],
      ),
    );
  }

  Widget _buildOwnerListingRequestCard(
    Map<String, dynamic> row, {
    required bool horizontalLayout,
    int ownerMarketingFeedScope = 0,
  }) {
    final l10n = AppLocalizations.of(context);
    var id = _marketingRequestIdFromRow(row);
    if (id.isEmpty) {
      id = (row['id'] ?? '').toString().trim();
    }
    final wfCtx = ListingWorkflowUiContext.fromListingRequest(
        Map<String, dynamic>.from(row));
    final linkedProperty = _linkedPropertyForOwnerRequestCard(row);
    if (linkedProperty != null) {
      return _buildOwnerLinkedPropertyCard(
        row,
        linkedProperty,
        wfCtx,
        ownerMarketingFeedScope: ownerMarketingFeedScope,
      );
    }

    assert(horizontalLayout || !horizontalLayout);
    final inContractingTab =
        ListingStageUiHelper.ownerTabMatches(1, wfCtx.stage);
    final inWaitingOffersTab =
        ListingStageUiHelper.ownerTabMatches(0, wfCtx.stage);

    void open() {
      if (id.isEmpty) return;
      unawaited(_openOwnerListingRequestFromRow(row, requestStatusId: id));
    }

    final waitingFooter = !inWaitingOffersTab
        ? null
        : (ownerMarketingFeedScope == 1
            ? null
            : (ownerMarketingFeedScope == 2
                ? _buildOwnerSingleMarketerOffersFooter(row, id)
                : null));

    final deadline = _marketingRowPermitDeadline(row) ?? wfCtx.primaryDeadline;

    final belowMain = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waitingFooter != null) waitingFooter,
        Padding(
          padding:
              EdgeInsets.fromLTRB(12, waitingFooter != null ? 6 : 4, 12, 8),
          child: ListingWorkflowProgressStrip(
            stage: wfCtx.stage,
            compact: true,
            dense: true,
            deadline: deadline,
            permitSoundContextId: id.isEmpty ? null : id,
          ),
        ),
      ],
    );

    final actions = <Widget>[];
    final scopeOk =
        ownerMarketingFeedScope != 1 && ownerMarketingFeedScope != 2;
    if (scopeOk && (inContractingTab || inWaitingOffersTab)) {
      if (inContractingTab) {
        final chatOk = _ownerPeerChatReady(row);
        if (chatOk) {
          actions.add(
            FilledButton.icon(
              onPressed: () => unawaited(_openOwnerChatWithMarketerForRow(row)),
              icon: const Icon(Icons.chat_bubble_outline, size: 22),
              label: Text(
                widget.isAr ? 'دردشة مع المسوّق' : 'Chat with marketer',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
              ),
            ),
          );
        } else if (MarketingWorkflowUiConfig.contractsSigningEnabled) {
          final contractId = (row['contract_id'] ?? '').toString().trim();
          if (contractId.isNotEmpty) {
            actions.add(
              FilledButton.icon(
                onPressed: () => unawaited(_openOwnerContractChat(contractId)),
                icon: const Icon(Icons.description_outlined, size: 22),
                label: Text(
                  widget.isAr ? 'مراجعة العقد' : 'Review contract',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                ),
              ),
            );
          }
        }
      } else if (inWaitingOffersTab || wfCtx.showOwnerOffersEntry) {
        actions.add(
          FilledButton.icon(
            onPressed: id.isEmpty
                ? null
                : () => unawaited(_openOwnerOffersForRequest(id)),
            icon: const Icon(Icons.rate_review_outlined, size: 22),
            label: Text(
              l10n?.ownerBtnRealEstateOffers ??
                  (widget.isAr ? 'العروض العقارية' : 'Real estate offers'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        );
      }
    }
    // v8: زر «إعادة للسوق» الجديد لـ owner_action_required (انقضاء 72h
    // للتصريح أو العقد). يَستخدم RPC owner_return_request_to_market مع
    // خيار السماح/المنع للمسوّق السابق.
    if (scopeOk && _ownerRowAwaitsReturnToMarket(row)) {
      actions.add(
        Padding(
          padding: EdgeInsets.only(top: actions.isNotEmpty ? 10 : 0),
          child: FilledButton.icon(
            onPressed: id.isEmpty
                ? null
                : () => unawaited(_ownerReturnRequestToMarket(row)),
            icon: const Icon(Icons.storefront_outlined, size: 22),
            label: Text(
              widget.isAr ? 'إعادة للسوق' : 'Return to market',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        ),
      );
    }
    // تبويب «لم يتخذ إجراء 72 ساعة»: إتاحة فرصة لإعادة العرض إلى «العروض المقدمة».
    if (scopeOk && _ownerRequestRowShowsInInactive72hTab(row)) {
      actions.add(
        Padding(
          padding: EdgeInsets.only(top: actions.isNotEmpty ? 10 : 0),
          child: FilledButton.tonalIcon(
            onPressed: id.isEmpty
                ? null
                : () => unawaited(_ownerGrantOpportunityFromInactive72h(row)),
            icon: const Icon(Icons.replay_circle_filled_outlined, size: 22),
            label: Text(
              widget.isAr ? 'إتاحة فرصة' : 'Grant another chance',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        ),
      );
    }
    if (scopeOk &&
        _ownerRowShowsRelistAction(row) &&
        !_ownerRowAwaitsReturnToMarket(row)) {
      actions.add(
        Padding(
          padding: EdgeInsets.only(top: actions.isNotEmpty ? 10 : 0),
          child: OutlinedButton.icon(
            onPressed: id.isEmpty
                ? null
                : () => unawaited(_ownerRelistMarketingRequestFromRow(row)),
            icon: const Icon(Icons.storefront_outlined, size: 22),
            label: Text(
              widget.isAr ? 'إعادة للسوق العقاري' : 'Relist to market',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        ),
      );
    }
    return _buildOwnerHubUnifiedMarketingCard(
      row: row,
      wfCtx: wfCtx,
      onOpenDetails: open,
      linkedProperty: null,
      belowMainRow: belowMain,
      footerActions: actions,
    );
  }

  Future<void> _openOwnerOffersForRequest(String requestId) async {
    if (requestId.isEmpty) return;
    final h = MediaQuery.sizeOf(context).height;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SizedBox(
          height: h * 0.92,
          child: OwnerOffersPage(
            requestId: requestId,
            lang: widget.lang,
            embeddedInSheet: true,
            onOfferAccepted: _ownerAfterOfferMutation,
          ),
        );
      },
    );
    if (mounted) await _loadOwnerRequestsBuckets(force: true);
  }

  Future<void> _openOwnerContractChat(String contractId) async {
    if (contractId.isEmpty) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: AppRoutes.listingContractChat),
        builder: (_) => ListingContractChatPage(
          contractId: contractId,
          lang: widget.lang,
          embedAppBar: false,
        ),
      ),
    );
    if (mounted) await _loadOwnerRequestsBuckets(force: true);
  }

  Future<void> _ownerRelistMarketingRequestFromRow(
    Map<String, dynamic> row,
  ) async {
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (!_ownerRowShowsRelistAction(row)) return;

    var allowPreviousMarketersRetry = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(
              widget.isAr ? 'إعادة طرحه للسوق العقاري' : 'Relist to market',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isAr
                      ? 'سيتم فتح الطلب لعروض مسوقين جدد حسب الجولة التالية.'
                      : 'The request will reopen for new marketer offers.',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.isAr
                        ? 'السماح لنفس المسوّق بالتقديم مجدداً'
                        : 'Allow the same marketer to submit again',
                  ),
                  value: allowPreviousMarketersRetry,
                  onChanged: (v) =>
                      setLocal(() => allowPreviousMarketersRetry = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(widget.isAr ? 'تأكيد' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await MarketingFlowService(_sb).relistListingRequestForMarketing(
        requestId: id,
        allowPreviousMarketersRetry: allowPreviousMarketersRetry,
      );
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        ListingWorkflowCopy.snackRelistSuccess(widget.isAr),
      );
      await _refreshMyPageHubAfterAction(
        ownerTabIndex: 0,
        marketerTabIndex: 0,
        notifyHub: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر الإعادة' : 'Could not relist',
        ListingWorkflowCopy.rpcFailedFriendly(widget.isAr, e),
        isError: true,
      );
    }
  }

  /// هل وُقّع العقد أو وافق المالك على العرض؟ (لإظهار الدردشة بعد الموافقة).
  bool _ownerRowContractSigned(Map<String, dynamic> r) {
    final selMid = (r['selected_marketer_id'] ?? '').toString().trim();
    if (selMid.isNotEmpty) return true;
    final cs = (r['contract_status'] ?? '').toString().toLowerCase().trim();
    if (cs == 'signed') return true;
    final ownerSigned =
        (r['contract_owner_signed_at'] ?? '').toString().trim().isNotEmpty;
    final marketerSigned =
        (r['contract_marketer_signed_at'] ?? '').toString().trim().isNotEmpty;
    if (ownerSigned && marketerSigned) return true;
    final wf = (r['workflow_stage'] ??
            r['request_workflow_stage'] ??
            r['preview_workflow_stage'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    return const {
      'contract_signed',
      'permit_pending',
      'awaiting_permits',
      'pending_permits',
      'permit_issued',
      'published',
      'reserved',
    }.contains(wf);
  }

  /// الدردشة مع المالك — تُفتح فقط بعد موافقة المالك على عرض هذا المسوق.
  bool _marketerOwnerChatUnlocked(Map<String, dynamic> r) {
    if (_isGuest) return false;
    final uid = _uid.trim();
    if (uid.isEmpty || uid == 'guest') return false;
    final selected =
        (r['selected_marketer_id'] ?? r['request_selected_marketer_id'] ?? '')
            .toString()
            .trim();
    if (selected.isEmpty || selected != uid) return false;
    final st = _workflowStageFromMarketerRow(r);
    if (st == ListingWorkflowStage.inactive72h ||
        st == ListingWorkflowStage.cancelled ||
        st == ListingWorkflowStage.terminated ||
        st == ListingWorkflowStage.contractCancelled) {
      return false;
    }
    return const {
      ListingWorkflowStage.marketerSelected,
      ListingWorkflowStage.contractPending,
      ListingWorkflowStage.contractSent,
      ListingWorkflowStage.contractReturned,
      ListingWorkflowStage.contractSigned,
      ListingWorkflowStage.permitPending,
      ListingWorkflowStage.permitIssued,
    }.contains(st);
  }

  /// جوال المالك — بعد موافقة المالك، أو إن فعّل إظهاره من السوق عند الإضافة.
  bool _marketerOwnerPhoneVisibleOnCard(Map<String, dynamic> r) {
    if (_listingRevealsOwnerPhoneFromMarket(r)) return true;
    if (!_marketerInApprovedWorkflowSubTab) return false;
    return _marketerOwnerChatUnlocked(r);
  }

  String _marketerOwnerChatDraftFromRow(Map<String, dynamic> r) {
    return MarketerOwnerChatIntroAr.build(
      isAr: widget.isAr,
      ownerDisplayName: _marketingOwnerName(r),
      listingNoTenDigit: MarketerOwnerChatIntroAr.tenDigitListingCodeFromRow(r),
      locationLine: _marketingLocationText(r),
      subject: MarketerOwnerChatIntroAr.inferSubject(r),
    );
  }

  /// شارة واضحة «منشور» أو «محجوز» لتبويب منشور/محجوز.
  Widget _hubPublishedOrReservedStatusChip(
    Map<String, dynamic> r,
    ColorScheme cs,
  ) {
    final st = _workflowStageFromMarketerRow(r);
    final statusRaw = (r['request_workflow_stage'] ??
            r['workflow_stage'] ??
            r['preview_workflow_stage'] ??
            r['status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final reserved = st == ListingWorkflowStage.reserved ||
        statusRaw == 'reserved' ||
        statusRaw.contains('reserv');
    final label = reserved
        ? (widget.isAr ? 'محجوز' : 'Reserved')
        : (widget.isAr ? 'منشور' : 'Published');
    final color = reserved ? const Color(0xFFB45309) : const Color(0xFF0B4D3E);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  /// مواصفات مختصرة (مساحة/غرف/موقع) — نفس أسلوب بطاقة الرئيسية.
  Widget _hubUnifiedCardSpecRow(Map<String, dynamic> r, ColorScheme cs) {
    final typeKey = (r['preview_type'] ?? r['request_property_type'] ?? '')
        .toString()
        .trim();
    final areaRaw = r['preview_area'] ?? r['area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;
    final areaText = area > 0
        ? (widget.isAr
            ? '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} م²'
            : '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} m²')
        : '';
    final bedsRaw =
        PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(typeKey)
            ? (r['preview_bedrooms'] as num?)?.toInt()
            : null;
    final roomsText = bedsRaw != null && bedsRaw > 0
        ? (widget.isAr ? '$bedsRaw غرف' : '$bedsRaw bd')
        : '';
    final districtText = '';
    final locationParts = _marketingLocationHierarchyParts(r);
    final purposeAccent = PropertyListingDisplay.accentForRequestRow(r);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: UnifiedCardSpecRow(
        bankColor: purposeAccent,
        areaText: areaText,
        roomsText: roomsText,
        districtText: districtText,
        locationParts: locationParts,
      ),
    );
  }

  Widget _buildMarketerHubCreativeSummary(
    Map<String, dynamic> r,
    ColorScheme cs,
  ) {
    final owner = _marketingOwnerName(r);
    final city = (r['preview_city'] ?? r['city'] ?? '').toString().trim();
    final purpose =
        PropertyListingDisplay.purposeLabelForRequestRow(r, widget.isAr);
    final areaRaw = r['preview_area'] ?? r['area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;
    final createdRaw =
        (r['preview_created_at'] ?? r['created_at'] ?? '').toString().trim();
    final createdDt = DateTime.tryParse(createdRaw)?.toLocal();
    final createdLabel =
        createdDt == null ? '' : _formatListingRequestCreatedFull(createdDt);
    final base = _propertyBaseSarForMarketingFee(r);
    final priceLabel = base != null && base > 0
        ? AppMoney.formatWithCurrencyCode(base, isAr: widget.isAr)
        : '';

    Widget cell(String label, String value, IconData icon) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final cells = <Widget>[
      if (owner.isNotEmpty)
        cell(
          widget.isAr ? 'شريكنا — المالك' : 'Our partner — Owner',
          owner,
          Icons.person_outline_rounded,
        ),
      if (purpose.isNotEmpty)
        cell(
          widget.isAr ? 'الغرض' : 'Purpose',
          purpose,
          Icons.category_outlined,
        ),
      if (city.isNotEmpty)
        cell(
          widget.isAr ? 'المدينة' : 'City',
          city,
          Icons.location_city_outlined,
        ),
      if (area > 0)
        cell(
          widget.isAr ? 'المساحة' : 'Area',
          widget.isAr
              ? '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} م²'
              : '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} m²',
          Icons.square_foot_outlined,
        ),
      if (createdLabel.isNotEmpty)
        cell(
          widget.isAr ? 'تاريخ الإنشاء' : 'Created',
          createdLabel,
          Icons.event_rounded,
        ),
      if (priceLabel.isNotEmpty)
        cell(
          widget.isAr ? 'السعر' : 'Price',
          priceLabel,
          Icons.payments_outlined,
        ),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.28),
            cs.secondaryContainer.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isAr ? 'تفاصيل السوق' : 'Market details',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth >= 420 ? 2 : 1;
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: cross == 2 ? 2.8 : 3.2,
                children: cells,
              );
            },
          ),
        ],
      ),
    );
  }

  /// شرط ظهور أيقونة دردشة المالك داخل بطاقات «صفحتي» للمسوّق.
  bool _canShowMarketerChatIconForRow(Map<String, dynamic> r) {
    if (!_marketerOwnerChatUnlocked(r)) return false;
    final hubCtx = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(r),
    );
    return !hubCtx.isPublishedPublic;
  }

  /// يفتح دردشة المالك مع المسوّق المختار/المتعاقد (في صفحتي للمالك،
  /// تبويب «تصاريح 72 ساعة» أو «بانتظار التعاقد») — يبحث عن `selected_marketer_id`
  /// أوّلاً ثم يلجأ إلى عرض الإعلان المعاين.
  Future<void> _openOwnerChatWithMarketerForRow(Map<String, dynamic> r) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    final mid = (r['selected_marketer_id'] ??
            r['prev_selected_marketer_id'] ??
            r['marketer_id'] ??
            '')
        .toString()
        .trim();
    final pid = (r['preview_property_id'] ?? '').toString().trim();
    if (pid.isNotEmpty) {
      await ChatNavigation.push(
        context,
        isAr: widget.isAr,
        propertyId: pid,
        counterpartyId: mid.isNotEmpty && mid != _uid ? mid : null,
        title: widget.isAr ? 'محادثة مع المسوّق' : 'Chat with marketer',
      );
      return;
    }
    if (mid.isNotEmpty && mid != _uid) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'لا يوجد إعلان معاينة بعد — تُفتح المحادثة بعد قبول العرض وإنشاء الإعلان.'
            : 'No preview listing yet — chat opens after offer acceptance.',
        isError: false,
      );
      return;
    }
    _showNotification(
      widget.isAr ? 'تنبيه' : 'Notice',
      widget.isAr
          ? 'لا يوجد مسوّق مختار بعد لفتح المحادثة.'
          : 'No selected marketer to chat with yet.',
      isError: false,
    );
  }

  Future<void> _openMarketerChatWithOwnerForRow(Map<String, dynamic> r) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }
    final draft = _marketerOwnerChatDraftFromRow(r);
    final rid = _marketingRequestIdFromRow(r);
    final pid = (r['preview_property_id'] ?? '').toString().trim();
    if (pid.isNotEmpty) {
      await ChatNavigation.push(
        context,
        isAr: widget.isAr,
        propertyId: pid,
        title: widget.isAr ? 'محادثة مع المالك' : 'Chat with owner',
        initialDraftMessage: draft,
      );
      return;
    }
    final oid =
        (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
    if (oid.isNotEmpty && oid != _uid) {
      if (rid.isNotEmpty) {
        await ChatNavigation.push(
          context,
          isAr: widget.isAr,
          kind: ConversationKind.marketRequest,
          marketRequestId: rid,
          counterpartyId: oid,
          title: widget.isAr ? 'محادثة مع المالك' : 'Chat with owner',
          initialDraftMessage: draft,
        );
        return;
      }
      await ChatNavigation.push(
        context,
        isAr: widget.isAr,
        kind: ConversationKind.direct,
        counterpartyId: oid,
        title: widget.isAr ? 'محادثة مع المالك' : 'Chat with owner',
        initialDraftMessage: draft,
      );
      return;
    }
    _showNotification(
      widget.isAr ? 'تنبيه' : 'Notice',
      widget.isAr
          ? 'تعذر فتح المحادثة: لا يوجد مالك مرتبط بهذا الطلب.'
          : 'Could not open chat: no owner linked to this request.',
      isError: false,
    );
  }

  ListingWorkflowStage _workflowStageFromMarketerRow(Map<String, dynamic> row) {
    return ListingWorkflowUnified.fromMarketerMergedRow(row);
  }

  String _marketingRequestIdFromRow(Map<String, dynamic> row) {
    return (row['request_id'] ?? row['listing_request_id'] ?? '')
        .toString()
        .trim();
  }

  Map<String, dynamic>? _findMarketerRowForSubscriptionResume(
    MarketingSubscriptionResumeIntent intent,
  ) {
    if (intent.kind == MarketingSubscriptionResumeKind.addPropertyListing ||
        intent.kind == MarketingSubscriptionResumeKind.postPaidUnlock) {
      return null;
    }
    final rid = intent.requestId.trim();
    final hk = intent.hubKind.trim();
    final offerNeedle = intent.offerId?.trim() ?? '';
    final cidNeedle = intent.contractId?.trim() ?? '';

    if (intent.kind == MarketingSubscriptionResumeKind.contractChat &&
        cidNeedle.isNotEmpty) {
      for (final r in _mkContracts) {
        if ((r['id'] ?? '').toString().trim() == cidNeedle) return r;
      }
      return null;
    }

    final lists = <List<Map<String, dynamic>>>[
      _mkInvites,
      _mkOffers,
      _mkContracts,
      _mkPermits,
      _mkPublished,
    ];
    Map<String, dynamic>? loose;
    for (final list in lists) {
      for (final r in list) {
        if (rid.isNotEmpty && _marketingRequestIdFromRow(r) != rid) continue;
        if (offerNeedle.isNotEmpty) {
          final so = (r['selected_offer_id'] ?? '').toString().trim();
          if (so != offerNeedle) continue;
        }
        loose ??= r;
        if (hk.isEmpty) return r;
        final rk = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString().trim();
        if (rk == hk) return r;
      }
    }
    return loose;
  }

  bool _marketerRowHasContract(Map<String, dynamic> row) {
    if ((row['contract_id'] ?? '').toString().trim().isNotEmpty) return true;
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return false;
    return _mkContracts.any(
      (c) => (c['request_id'] ?? '').toString().trim() == requestId,
    );
  }

  bool _marketerRowPublishedByOther(Map<String, dynamic> row) {
    if (AppRoleHelper.isOrgEntity(_accountType)) {
      // منشأة: المنشور باسم زميل لا يُستبعد — كان يُفرّغ تبويب «منشور/محجوز» بالخطأ.
      return false;
    }
    final workflow = (row['request_workflow_stage'] ??
            row['workflow_stage'] ??
            row['preview_workflow_stage'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final status = (row['preview_status'] ?? row['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final publishedBy = (row['preview_published_by_marketer_id'] ??
            row['published_by_marketer_id'] ??
            row['selected_marketer_id'] ??
            '')
        .toString()
        .trim();
    final published =
        workflow == 'published' || status == 'published' || status == 'live';
    return published && publishedBy.isNotEmpty && publishedBy != _uid;
  }

  ({
    bool canSubmitOffer,
    bool canViewDetails,
    bool canCardTap,
    String? inviteOfferBlockMessage,
    String? inviteDetailsBlockMessage,
  }) _marketerCardActionMatrix(
    Map<String, dynamic> row, {
    required String type,
  }) {
    final requestId = _marketingRequestIdFromRow(row);
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();
    final inviteGate = (type == 'invite'
            ? (row['invite_gate_status'] ?? row['status'])
            : row['status'])
        .toString()
        .trim()
        .toLowerCase();
    final workflowRaw =
        (row['request_workflow_stage'] ?? row['workflow_stage'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final requestStatusRaw =
        (row['listing_request_status'] ?? row['request_status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final deadlineInactive =
        row['_owner_offers_all_expired_by_deadline'] == true;

    const closedAfterMarketing = <String>{
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'published',
      'reserved',
      'inactive_72h',
      'cancelled',
      'terminated',
      'archived',
      'contract_cancelled',
    };

    final activelyCollecting =
        _requestActivelyCollectingOffers(workflowRaw, requestStatusRaw);

    final inviteBlockedByStatus = inviteGate == 'declined' ||
        inviteGate == 'expired' ||
        (!activelyCollecting &&
            (inviteGate == 'offered' ||
                inviteGate == 'accepted' ||
                inviteGate == 'withdrawn'));

    // للدعوات: لا نستخدم listing_request_status (غالباً active/published) كحظر — ذلك كان يُعطّل زر العرض.
    final relistReoffer = _allowPreviousMarketersRetryOnRequest(row);
    final openAfterRelist = relistReoffer &&
        const {
          'waiting_marketers',
          'collecting_offers',
          'seeking',
          'bidding',
          'negotiating',
        }.contains(workflowRaw);

    final workflowClosedForOffers = deadlineInactive ||
        (!_requestActivelyCollectingOffers(workflowRaw, requestStatusRaw) &&
            (type == 'invite'
                ? (closedAfterMarketing.contains(workflowRaw) &&
                    !openAfterRelist)
                : (workflowRaw == 'published' ||
                    requestStatusRaw == 'published' ||
                    requestStatusRaw == 'live' ||
                    requestStatusRaw == 'active')));

    final canSubmitOffer = type == 'invite' &&
        requestId.isNotEmpty &&
        !inviteBlockedByStatus &&
        !workflowClosedForOffers;
    final canViewDetails = requestId.isNotEmpty ||
        previewPropertyId.isNotEmpty ||
        type == 'published';
    // في «السوق العقاري»: الضغط على البطاقة أو الصورة يفتح تفاصيل الإعلان (كالرئيسية).
    final canCardTap = canViewDetails;

    final ar = widget.isAr;
    String? inviteOfferBlockMessage;
    String? inviteDetailsBlockMessage;
    if (type == 'invite') {
      if (!canSubmitOffer) {
        if (requestId.isEmpty) {
          inviteOfferBlockMessage = ar
              ? 'لا يوجد طلب مرتبط بهذه الدعوة بعد.'
              : 'No listing request is linked to this invite yet.';
        } else if (inviteBlockedByStatus) {
          inviteOfferBlockMessage = ar
              ? 'لا يمكن إتمام الصفقة لهذه الدعوة في حالتها الحالية.'
              : 'You cannot complete a deal for this invite in its current state.';
        } else if (deadlineInactive) {
          inviteOfferBlockMessage = ar
              ? 'انتهت مهلة العروض على هذا الطلب دون اختيار من المالك. يمكن إعادة طرحه لاحقاً.'
              : 'The offer window ended without an owner selection. It may be relisted.';
        } else if (workflowClosedForOffers) {
          inviteOfferBlockMessage = ar
              ? 'تجاوز هذا الطلب مرحلة استقبال عروض المسوّقين.'
              : 'This request is past the marketer offer stage.';
        }
      }
      if (!canViewDetails) {
        inviteDetailsBlockMessage = ar
            ? 'لا تتوفر تفاصيل إعلان مرتبطة بعد.'
            : 'No listing details are available yet.';
      }
    }

    return (
      canSubmitOffer: canSubmitOffer,
      canViewDetails: canViewDetails,
      canCardTap: canCardTap,
      inviteOfferBlockMessage: inviteOfferBlockMessage,
      inviteDetailsBlockMessage: inviteDetailsBlockMessage,
    );
  }

  bool _requestActivelyCollectingOffers(
    String workflowRaw,
    String requestStatusRaw,
  ) {
    if (workflowRaw == 'waiting_marketers') return true;
    return const {
      'waiting_marketers',
      'offers_received',
      'new',
      'invited',
      'pending',
    }.contains(requestStatusRaw);
  }

  bool _allowPreviousMarketersRetryOnRequest(Map<String, dynamic> r) {
    final v = r['allow_previous_marketers_retry'];
    return v == true ||
        v == 1 ||
        (v is String &&
            const {'true', 't', '1', 'yes'}.contains(v.toLowerCase()));
  }

  bool _marketerOfferRetryAllowedForRow(Map<String, dynamic> r) {
    final os = (r['status'] ?? '').toString().toLowerCase();
    if (!const {'owner_rejected', 'rejected', 'declined'}.contains(os)) {
      return false;
    }
    return _allowPreviousMarketersRetryOnRequest(r);
  }

  bool _marketerOfferRejectedNoRetry(Map<String, dynamic> r) {
    final os = (r['status'] ?? '').toString().toLowerCase();
    if (!const {'owner_rejected', 'rejected', 'declined'}.contains(os)) {
      return false;
    }
    return !_marketerOfferRetryAllowedForRow(r);
  }

  // ---------------------------------------------------------------------------
  // «إشعار آخر» — Last Call (v8 — أتمتة 48 ساعة).
  //
  // الزر يَظهر تحت بطاقة العرض في تبويب «عروضي» للمسوّق إذا:
  //   - حالة العرض submitted/pending،
  //   - مرّ 48 ساعة على آخر إشعار (أو على إنشاء العرض إن لم يَسبقه إشعار)،
  //   - والمالك لم يَختَر مسوّقاً آخر بعد.
  // ---------------------------------------------------------------------------

  /// قرار محلّي سريع (بدون ضرب الشبكة) لِإظهار الزر. الـRPC تَتحقّق سيرفر-سايد.
  bool _marketerCanShowLastCallButton(Map<String, dynamic> r) {
    final st = (r['status'] ?? '').toString().toLowerCase().trim();
    if (!const {'submitted', 'pending', ''}.contains(st)) return false;
    if (_marketerRowInactive72h(r)) return false;

    final selectedMid = (r['selected_marketer_id'] ?? '').toString().trim();
    if (selectedMid.isNotEmpty && selectedMid != _uid) return false;

    final lastCallAtStr = (r['last_call_at'] ?? '').toString().trim();
    final createdAtStr = (r['created_at'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse(createdAtStr)?.toUtc();
    if (createdAt == null) return false;

    final ref = lastCallAtStr.isNotEmpty
        ? DateTime.tryParse(lastCallAtStr)?.toUtc() ?? createdAt
        : createdAt;
    final now = DateTime.now().toUtc();
    return now.difference(ref) >= const Duration(hours: 48);
  }

  /// زر «إلغاء العرض» بعد 48 ساعة دون موافقة المالك (نفس شروط إشعار آخر).
  bool _marketerCanShowCancelOfferAfter48h(Map<String, dynamic> r) {
    return _marketerCanShowLastCallButton(r);
  }

  Future<void> _marketerCancelOfferAfter48hFromRow(
      Map<String, dynamic> r) async {
    final offerId = (r['id'] ?? '').toString().trim();
    final requestId = _marketingRequestIdFromRow(r);
    if (offerId.isEmpty) return;

    bool showInMarket = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(widget.isAr ? 'إلغاء العرض' : 'Cancel offer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isAr
                      ? 'سيُلغى عرضك الحالي ويُزال من تبويب «عروضي». يمكنك اختيار إظهار هذا الإعلان في «السوق العقاري» لإتمام صفقة جديدة لاحقاً.'
                      : 'Your current offer will be cancelled and removed from My offers. You can choose whether this listing stays visible in the market tab.',
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: showInMarket,
                  onChanged: (v) => setSt(() => showInMarket = v),
                  title: Text(
                    widget.isAr
                        ? 'إظهار الإعلان في السوق العقاري'
                        : 'Show in real estate market',
                  ),
                  subtitle: Text(
                    widget.isAr
                        ? 'مفعّل: يمكنك إتمام صفقة جديدة لاحقاً. مغلق: لن يظهر لك مرة أخرى.'
                        : 'On: you can submit again later. Off: hidden from your market tab.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(widget.isAr ? 'تراجع' : 'Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(widget.isAr ? 'إلغاء العرض' : 'Cancel offer'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await MarketingFlowService(_sb).marketerWithdrawListingOffer(offerId);
      if (requestId.isNotEmpty) {
        await MarketerMarketVisibilityPrefs.setHidden(
          marketerUid: _uid,
          requestId: requestId,
          hidden: !showInMarket,
        );
        if (!showInMarket) {
          _marketerHiddenMarketRequestIds.add(requestId);
        } else {
          _marketerHiddenMarketRequestIds.remove(requestId);
        }
      }
      if (!mounted) return;
      await _loadMarketerBuckets(force: true, silent: true);
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تم الإلغاء' : 'Cancelled',
        widget.isAr ? 'تم إلغاء عرضك.' : 'Your offer was cancelled.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر الإلغاء' : 'Could not cancel',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _marketerSendOfferLastCall(Map<String, dynamic> r) async {
    final offerId = (r['id'] ?? '').toString().trim();
    if (offerId.isEmpty) return;
    final svc = MarketingWorkflowAutomationService(Supabase.instance.client);

    // فحص إضافي قبل الضغط (يَتفقّد cooldown ودولة المالك).
    final pre = await svc.canSendLastCall(offerId);
    if (pre['allow'] != true) {
      final reason = (pre['reason'] ?? '').toString();
      String msg;
      if (reason == 'owner_selected_other') {
        msg = widget.isAr
            ? 'تعذّر الإشعار: المالك اختار مسوّقاً آخر.'
            : 'Owner has selected another marketer.';
      } else if (reason == 'cooldown') {
        msg = widget.isAr
            ? 'مهلة إشعار آخر فعّالة. حاول لاحقاً.'
            : 'Last-call cooldown active. Try again later.';
      } else if (reason == 'before_first_window') {
        msg = widget.isAr
            ? 'لا يمكن إرسال إشعار آخر قبل مرور 48 ساعة على إتمام الصفقة.'
            : 'You can send a last-call only 48 hours after completing your deal.';
      } else if (reason == 'offer_not_active') {
        msg = widget.isAr
            ? 'هذا العرض لم يَعد نشطاً.'
            : 'This offer is no longer active.';
      } else {
        msg = widget.isAr
            ? 'تعذّر إرسال إشعار آخر الآن.'
            : 'Cannot send a last-call right now.';
      }
      _showNotification(widget.isAr ? 'تنبيه' : 'Notice', msg, isError: true);
      return;
    }

    final res = await svc.sendLastCall(offerId);
    if (res['ok'] == true) {
      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        widget.isAr
            ? 'تم إرسال إشعار صوتي للمالك وتجديد عرضك 48 ساعة أخرى.'
            : 'A sound alert was sent to the owner and your offer was renewed for 48 hours.',
        isError: false,
      );
      try {
        // حدّث الصف محلياً لإعادة تعطيل الزر فوراً
        r['last_call_at'] = DateTime.now().toUtc().toIso8601String();
        r['last_call_count'] =
            ((r['last_call_count'] as num?)?.toInt() ?? 0) + 1;
        if (mounted) setState(() {});
        unawaited(_loadMarketerBuckets(force: true));
      } catch (_) {}
    } else {
      _showNotification(
        widget.isAr ? 'خطأ' : 'Error',
        widget.isAr
            ? 'تعذّر إرسال الإشعار. حاول لاحقاً.'
            : 'Could not send the alert. Try again later.',
        isError: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // «إعادة للسوق» — للمالك، بعد owner_action_required (انقضاء 72h).
  // ---------------------------------------------------------------------------

  /// هل البطاقة (للمالك) في حالة «لم يُتَّخذ إجراء 72 ساعة»؟
  bool _ownerRowAwaitsReturnToMarket(Map<String, dynamic> r) {
    final stage = (r['workflow_stage'] ?? '').toString().toLowerCase().trim();
    if (const {
      'owner_action_required',
      'inactive_72h',
      'inactive72h',
    }.contains(stage)) {
      return true;
    }
    if ((r['owner_action_required_at'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    if ((r['inactive_72h_at'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    final st = (r['status'] ?? r['listing_request_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return const {
      'owner_action_required',
      'inactive_72h',
      'inactive72h',
    }.contains(st);
  }

  bool _rpcMapOk(Map<String, dynamic> res) {
    final v = res['ok'];
    if (v == true) return true;
    if (v == false || v == null) return false;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't';
  }

  bool _errorLooksLikeAlreadyOnMarket(Object? error) {
    final s = (error ?? '').toString().toLowerCase();
    return s.contains('invalid_stage_for_relist') ||
        s.contains('no_owner_action_pending') ||
        (s.contains('already') && s.contains('market'));
  }

  /// بعد نجاح السيرفر قد يفشل الاستدعاء الثاني/المهلة — نؤكد من الصف.
  Future<bool> _listingRequestIsOnMarketerMarket(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return false;
    try {
      final row = await _sb
          .from('listing_requests')
          .select('workflow_stage,status')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return false;
      final stage =
          (row['workflow_stage'] ?? '').toString().toLowerCase().trim();
      final status = (row['status'] ?? '').toString().toLowerCase().trim();
      const ok = {
        'waiting_marketers',
        'offers_received',
        'waiting_offers',
      };
      return ok.contains(stage) || ok.contains(status);
    } catch (_) {
      return false;
    }
  }

  Future<void> _ownerReturnRequestToMarket(Map<String, dynamic> r) async {
    final reqId = (r['id'] ?? r['request_id'] ?? '').toString().trim();
    if (reqId.isEmpty) return;
    final ar = widget.isAr;

    bool allowSame = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(ar ? 'إعادة الطلب للسوق' : 'Return to market'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ar
                      ? 'سيُعاد الطلب إلى السوق ليَتقدّم عليه المسوّقون من جديد.'
                      : 'Your request will be re-listed for marketers to bid on.',
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    ar
                        ? 'السماح للمسوّق السابق بالعودة'
                        : 'Allow previous marketer to retry',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    ar
                        ? 'إن أوقفته، لن يَستطيع نفس المسوّق إتمام صفقة جديدة.'
                        : 'If off, the previous marketer cannot submit a new offer.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: allowSame,
                  onChanged: (v) => setSt(() => allowSame = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ar ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(ar ? 'إعادة للسوق' : 'Return'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;

    final svc = MarketingWorkflowAutomationService(Supabase.instance.client);
    final res = await svc.returnRequestToMarket(
      requestId: reqId,
      allowSameMarketer: allowSame,
    );
    Future<void> succeed({bool hasOffers = false}) async {
      if (!mounted) return;
      r['_hub_inactive_72h'] = false;
      r['_owner_offers_all_expired_by_deadline'] = false;
      r['_owner_offers_need_relist'] = false;
      _showNotification(
        ar ? 'تم' : 'Done',
        ar ? 'تمت إعادة الطلب إلى السوق.' : 'Request returned to market.',
        isError: false,
      );
      try {
        await _refreshMyPageHubAfterAction(
          ownerTabIndex: hasOffers ? 1 : 0,
          marketerTabIndex: 0,
          notifyHub: true,
        );
      } catch (_) {
        if (mounted) setState(() {});
      }
    }

    if (_rpcMapOk(res)) {
      await succeed(hasOffers: res['has_pending_offers'] == true);
      return;
    }

    final err = res['error']?.toString() ?? '';
    try {
      await MarketingFlowService(_sb).relistListingRequestForMarketing(
        requestId: reqId,
        allowPreviousMarketersRetry: allowSame,
      );
      await succeed();
      return;
    } catch (e) {
      if (_errorLooksLikeAlreadyOnMarket(e) ||
          _errorLooksLikeAlreadyOnMarket(err) ||
          await _listingRequestIsOnMarketerMarket(reqId)) {
        await succeed();
        return;
      }
      if (!mounted) return;
      _showNotification(
        ar ? 'خطأ' : 'Error',
        ListingWorkflowCopy.rpcFailedFriendly(ar, e),
        isError: true,
      );
    }
  }

  static const Duration _inactiveToCancelledAfter = Duration(days: 14);
  static const Duration _cancelledPurgeAfter = Duration(days: 45);

  DateTime? _inactiveAnchorAt(Map<String, dynamic> r) {
    for (final k in const [
      'inactive_72h_at',
      'auto_expired_at',
      'owner_action_required_at',
    ]) {
      final dt = DateTime.tryParse((r[k] ?? '').toString())?.toUtc();
      if (dt != null) return dt;
    }
    return null;
  }

  bool _rowShouldMoveInactiveToCancelled(Map<String, dynamic> r) {
    final dt = _inactiveAnchorAt(r);
    if (dt == null) return false;
    return DateTime.now().toUtc().difference(dt) >= _inactiveToCancelledAfter;
  }

  bool _rowShouldPurgeFromHub(Map<String, dynamic> r) {
    final dt = _inactiveAnchorAt(r);
    if (dt == null) return false;
    return DateTime.now().toUtc().difference(dt) >= _cancelledPurgeAfter;
  }

  String _marketerCancelledDismissKey(Map<String, dynamic> r) {
    final reqId = _marketingRequestIdFromRow(r);
    if (reqId.isNotEmpty) return 'req:$reqId';
    final id = (r['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'row:$id';
    return '';
  }

  Future<void> _dismissMarketerCancelledCard(Map<String, dynamic> r) async {
    final key = _marketerCancelledDismissKey(r);
    if (key.isEmpty) return;
    final ar = widget.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف من صفحتي' : 'Remove from My page'),
        content: Text(
          ar
              ? 'ستختفي البطاقة من تبويب مفسوخ/ملغى. لن يؤثر ذلك على سجلات النظام.'
              : 'This card will disappear from Cancelled. System records are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'تراجع' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _marketerDismissedCancelledIds.add(key));
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _uid.trim();
      if (uid.isNotEmpty) {
        await prefs.setStringList(
          'mk_dismissed_cancelled_v1_$uid',
          _marketerDismissedCancelledIds.toList(),
        );
      }
    } catch (_) {}
    if (!mounted) return;
    _showNotification(
      ar ? 'تم الحذف' : 'Removed',
      ar ? 'اختفت البطاقة من مفسوخ/ملغى.' : 'Card removed from Cancelled.',
    );
  }

  Future<void> _refreshExhaustedOpportunityIds(
    Iterable<String> requestIds,
  ) async {
    final uid = _uid.trim();
    if (uid.isEmpty || uid == 'guest') return;
    final out = <String>{};
    final counts = <String, int>{};
    for (final raw in requestIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final n = await OpportunityGrantStore.countFor(
        userId: uid,
        requestId: id,
      );
      if (n > 0) counts[id] = n;
      if (n >= OpportunityGrantStore.maxGrants) out.add(id);
    }
    if (!mounted) return;
    setState(() {
      _exhaustedOpportunityRequestIds = out;
      _opportunityGrantCountsByRequestId = counts;
    });
  }

  Future<void> _ownerGrantOpportunityFromInactive72h(
    Map<String, dynamic> r,
  ) async {
    final reqId = (r['id'] ?? r['request_id'] ?? '').toString().trim();
    if (reqId.isEmpty) return;
    final uid = _uid.trim();
    final ar = widget.isAr;
    if (await OpportunityGrantStore.isExhausted(
      userId: uid,
      requestId: reqId,
    )) {
      if (!mounted) return;
      _showNotification(
        ar ? 'تنبيه' : 'Notice',
        ar
            ? 'استُنفدت فرص الإعادة الأربع لهذا الطلب — لن يظهر في تبويب بدون إجراء 72 ساعة.'
            : 'All 4 chances were used — this request no longer appears in the 72h inactive tab.',
        isError: false,
      );
      setState(() => _exhaustedOpportunityRequestIds.add(reqId));
      return;
    }
    final used = await OpportunityGrantStore.countFor(
      userId: uid,
      requestId: reqId,
    );
    final next = used + 1;
    final ordinal = OpportunityGrantStore.ordinalLabel(next, isAr: ar);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'إتاحة فرصة' : 'Grant another chance'),
        content: Text(
          ar
              ? 'هذه الفرصة $ordinal من أصل ${OpportunityGrantStore.maxGrants}.\n'
                  'سيُعاد الطلب إلى تبويب «العروض المقدمة» ليتابع المسوّقون.\n'
                  'بعد الفرصة الرابعة يختفي من «بدون إجراء 72 ساعة».'
              : 'This is the $ordinal of ${OpportunityGrantStore.maxGrants} chances.\n'
                  'The request returns to Submitted offers.\n'
                  'After the 4th chance it leaves the 72h inactive tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ar ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final granted = await OpportunityGrantStore.increment(
      userId: uid,
      requestId: reqId,
    );
    if (granted == null) return;

    final svc = MarketingWorkflowAutomationService(Supabase.instance.client);
    final res = await svc.returnRequestToMarket(
      requestId: reqId,
      allowSameMarketer: true,
    );
    if (!mounted) return;

    Future<void> grantSucceed() async {
      if (!mounted) return;
      // امسح أعلام التبويب المحلي فوراً حتى لا تُعاد البطاقة لـ 72 ساعة قبل اكتمال الجلب.
      r['_hub_inactive_72h'] = false;
      r['_owner_offers_all_expired_by_deadline'] = false;
      r['_owner_offers_need_relist'] = false;
      r['_hub_opportunity_grant'] = true;
      setState(() {
        _opportunityGrantCountsByRequestId = {
          ..._opportunityGrantCountsByRequestId,
          reqId: granted,
        };
      });
      _showNotification(
        ar ? 'تمت إتاحة الفرصة' : 'Chance granted',
        ar
            ? 'الفرصة ${OpportunityGrantStore.ordinalLabel(granted, isAr: true)}. انتقل إلى العروض المقدمة.'
            : 'Chance ${OpportunityGrantStore.ordinalLabel(granted, isAr: false)}. Opened Submitted offers.',
      );
      await _refreshMyPageHubAfterAction(
        ownerTabIndex: 1,
        marketerTabIndex: 0,
        notifyHub: true,
      );
      if (!mounted) return;
      if (granted >= OpportunityGrantStore.maxGrants) {
        setState(() => _exhaustedOpportunityRequestIds.add(reqId));
      }
    }

    if (_rpcMapOk(res)) {
      await grantSucceed();
      return;
    }

    try {
      await MarketingFlowService(_sb).relistListingRequestForMarketing(
        requestId: reqId,
        allowPreviousMarketersRetry: true,
      );
      await grantSucceed();
    } catch (e) {
      if (_errorLooksLikeAlreadyOnMarket(e) ||
          _errorLooksLikeAlreadyOnMarket(res['error']) ||
          await _listingRequestIsOnMarketerMarket(reqId)) {
        await grantSucceed();
        return;
      }
      if (!mounted) return;
      _showNotification(
        ar ? 'خطأ' : 'Error',
        ListingWorkflowCopy.rpcFailedFriendly(ar, e),
        isError: true,
      );
    }
  }

  Future<void> _grantOpportunityFromInactive72h(Map<String, dynamic> r) async {
    final reqId = _marketingRequestIdFromRow(r);
    if (reqId.isEmpty) return;
    final uid = _uid.trim();
    final ar = widget.isAr;
    if (await OpportunityGrantStore.isExhausted(
      userId: uid,
      requestId: reqId,
    )) {
      if (!mounted) return;
      _showNotification(
        ar ? 'تنبيه' : 'Notice',
        ar
            ? 'استُنفدت الفرص الأربع — لن يظهر هذا الطلب في تبويب بدون إجراء 72 ساعة.'
            : 'All 4 chances used — this item leaves the 72h inactive tab.',
      );
      setState(() => _exhaustedOpportunityRequestIds.add(reqId));
      return;
    }
    final used = await OpportunityGrantStore.countFor(
      userId: uid,
      requestId: reqId,
    );
    final next = used + 1;
    final ordinal = OpportunityGrantStore.ordinalLabel(next, isAr: ar);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'إتاحة فرصة' : 'Grant another chance'),
        content: Text(
          ar
              ? 'هذه الفرصة $ordinal من أصل ${OpportunityGrantStore.maxGrants}.\n'
                  'سيُعاد العرض إلى تبويب «عروضي» ويستمر بغض النظر عن قبول المالك لاحقاً.\n'
                  'بعد الرابعة يختفي من «بدون إجراء 72 ساعة».'
              : 'This is the $ordinal of ${OpportunityGrantStore.maxGrants}.\n'
                  'Your offer returns to My offers and stays active regardless of later owner acceptance.\n'
                  'After the 4th it leaves the 72h inactive tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ar ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final granted = await OpportunityGrantStore.increment(
      userId: uid,
      requestId: reqId,
    );
    if (granted == null) return;

    final offerId = (r['id'] ?? r['offer_id'] ?? '').toString().trim();
    final svc = MarketingWorkflowAutomationService(Supabase.instance.client);
    var ok = false;
    if (offerId.isNotEmpty && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(offerId)) {
      final res = await svc.sendLastCall(offerId);
      ok = res['ok'] == true;
    }
    r['_hub_inactive_72h'] = false;
    r['_owner_offers_all_expired_by_deadline'] = false;
    r['_hub_opportunity_grant'] = true;
    setState(() {
      _opportunityGrantCountsByRequestId = {
        ..._opportunityGrantCountsByRequestId,
        reqId: granted,
      };
    });
    final exp = DateTime.now().toUtc().add(const Duration(hours: 48));
    r['expires_at'] = exp.toIso8601String();
    if (!ok && offerId.isNotEmpty) {
      try {
        await _sb.from('listing_offers').update({
          'expires_at': exp.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', offerId);
        ok = true;
      } catch (_) {}
    }

    if (!mounted) return;
    _showNotification(
      ar ? 'تمت إتاحة الفرصة' : 'Chance granted',
      ar
          ? 'الفرصة ${OpportunityGrantStore.ordinalLabel(granted, isAr: true)}. راجع تبويب عروضي.'
          : 'Chance ${OpportunityGrantStore.ordinalLabel(granted, isAr: false)}. Check My offers.',
    );
    if (granted >= OpportunityGrantStore.maxGrants) {
      setState(() => _exhaustedOpportunityRequestIds.add(reqId));
    }
    await _refreshMyPageHubAfterAction(
      marketerTabIndex: 1,
      notifyHub: false,
    );
  }

  Future<void> _marketerWithdrawOfferFromRow(Map<String, dynamic> r) async {
    final offerId = (r['id'] ?? '').toString().trim();
    if (offerId.isEmpty) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: widget.isAr ? 'إلغاء العرض' : 'Cancel offer',
      message: widget.isAr
          ? 'سيتم سحب عرضك ولن يظهر في «عروضي». هل تؤكد؟'
          : 'Your offer will be withdrawn and removed from My offers. Continue?',
      confirmLabel: widget.isAr ? 'إلغاء العرض' : 'Cancel offer',
      cancelLabel: widget.isAr ? 'تراجع' : 'Back',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    try {
      await MarketingFlowService(_sb).marketerWithdrawListingOffer(offerId);
      if (!mounted) return;
      await _refreshMyPageHubAfterAction(notifyHub: false);
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تم الإلغاء' : 'Cancelled',
        widget.isAr ? 'تم سحب عرضك بنجاح.' : 'Your offer was withdrawn.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تعذر الإلغاء' : 'Could not cancel',
        widget.isAr
            ? 'تعذر تنفيذ الطلب. حاول لاحقاً أو راجع الاتصال.'
            : e.toString(),
        isError: true,
      );
    }
  }

  /// عرض نشط للمسوّق الحالي على نفس الطلب (_mkOffers مُصفّاة لهذا المستخدم).
  bool _marketerHasActiveOfferForRequestRow(Map<String, dynamic> row) {
    final reqId = _marketingRequestIdFromRow(row);
    if (reqId.isEmpty) return false;
    final curRound = (row['marketing_round'] as num?)?.toInt() ?? 1;
    return _mkOffers.any((o) {
      final oid =
          (o['request_id'] ?? o['listing_request_id'] ?? '').toString().trim();
      if (oid != reqId) return false;
      final rn = (o['round_no'] as num?)?.toInt() ?? curRound;
      if (rn != curRound) return false;
      final st = (o['status'] ?? '').toString().toLowerCase().trim();
      return const {'submitted', 'pending', ''}.contains(st);
    });
  }

  /// لا تُعرض الدعوة في «السوق العقاري» إن وُجد للمسوّق عرض نشط على نفس الطلب.
  bool _inviteHiddenDueToActiveMarketerOffer(Map<String, dynamic> inviteRow) {
    return _marketerHasActiveOfferForRequestRow(inviteRow);
  }

  DateTime? _marketingRowPermitDeadline(Map<String, dynamic> r) {
    for (final k in const [
      'permit_deadline_at',
      'request_permit_deadline_at',
      'permits_due_at',
      'marketer_response_deadline_at',
    ]) {
      final v = r[k];
      if (v == null) continue;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d;
    }
    return null;
  }

  /// صف عقد في تبويب التصريح: [id] هو مُعرّف العقد لا تصريح — نزيله لمسار [insert] في [_submitMarketingPermit].
  Map<String, dynamic> _rowAsPermitSubmitSource(Map<String, dynamic> r) {
    final hk = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString();
    if (hk == 'contract') {
      final m = Map<String, dynamic>.from(r);
      m.remove('id');
      return m;
    }
    return r;
  }

  bool _marketerRowShowsPermitWorkflowChrome(
    String type,
    Map<String, dynamic> r,
  ) {
    if (!_marketerContractFlowUnlocked(r)) return false;
    if (type == 'permit') return true;
    if (type != 'contract' && type != 'offer') return false;
    final st = _workflowStageFromMarketerRow(r);
    // بدون توقيع عقود: بعد قبول العرض مباشرةً تظهر أزرار الإصدار/النشر.
    if (!MarketingWorkflowUiConfig.contractsSigningEnabled) {
      return const {
        ListingWorkflowStage.marketerSelected,
        ListingWorkflowStage.contractPending,
        ListingWorkflowStage.contractSent,
        ListingWorkflowStage.contractReturned,
        ListingWorkflowStage.contractSigned,
        ListingWorkflowStage.permitPending,
        ListingWorkflowStage.permitIssued,
      }.contains(st);
    }
    // مع العقود: النشر/REGA فقط في مرحلة التصريح.
    return st == ListingWorkflowStage.permitPending ||
        st == ListingWorkflowStage.permitIssued;
  }

  /// جاهزية دردشة المالك↔المسوّق على بطاقة صفحتي.
  bool _ownerPeerChatReady(Map<String, dynamic> row) {
    final selectedMid = (row['selected_marketer_id'] ?? '').toString().trim();
    if (selectedMid.isEmpty || selectedMid == _uid) return false;
    if (!MarketingWorkflowUiConfig.contractsSigningEnabled) return true;
    return _ownerRowContractSigned(row);
  }

  bool _marketerWasPrevSelectedOnRow(Map<String, dynamic> r) {
    final prev = (r['prev_selected_marketer_id'] ??
            r['request_prev_selected_marketer_id'] ??
            '')
        .toString()
        .trim();
    if (prev == _uid) return true;
    if ((r['marketer_id'] ?? '').toString() != _uid) return false;
    final os = (r['status'] ?? '').toString().toLowerCase().trim();
    return const {'owner_accepted', 'selected', 'approved'}.contains(os);
  }

  bool _marketerRowInactive72h(Map<String, dynamic> r) {
    return ListingWorkflowUnified.marketerHubRowInactive72h(r);
  }

  List<Map<String, dynamic>> _filterMarketerRowsForTab(int tabIndex) {
    bool involved(Map<String, dynamic> r) {
      final uid = _uid;
      if ((r['marketer_id'] ?? '').toString() == uid) return true;
      if ((r['selected_marketer_id'] ?? '').toString() == uid) return true;
      final prev = (r['prev_selected_marketer_id'] ??
              r['request_prev_selected_marketer_id'] ??
              '')
          .toString()
          .trim();
      return prev == uid;
    }

    Iterable<Map<String, dynamic>> sourceRows() sync* {
      switch (tabIndex) {
        case 0:
          yield* _mkInvites;
          return;
        case 1:
          yield* _mkOffers;
          return;
        case 2:
          yield* _mkOffers;
          yield* _mkContracts;
          return;
        case 3:
          yield* _mkPermits;
          return;
        case 4:
          yield* _mkPublished;
          return;
        case 5:
          yield* _mkOffers;
          yield* _mkContracts;
          yield* _mkPermits;
          return;
        case 6:
          yield* _mkOffers;
          yield* _mkContracts;
          yield* _mkPermits;
          return;
        default:
          yield* _mkInvites;
          yield* _mkOffers;
          yield* _mkContracts;
          yield* _mkPermits;
          yield* _mkPublished;
      }
    }

    return sourceRows().where((r) {
      if (!_matchesHubRowSearch(r)) return false;
      if (!_matchesHubRowRanges(r)) return false;
      if (_marketerRowPublishedByOther(r)) return false;
      if (tabIndex == 0 && _marketerRowHasContract(r)) return false;
      if (tabIndex == 2 &&
          (r['_hubKind'] ?? r['_ui_type'] ?? '').toString() == 'offer') {
        if (_marketerRowHasContract(r)) return false;
        if (_marketerRowInactive72h(r)) return false;
      }
      if (tabIndex == 1) {
        final hk = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString();
        if (hk != 'offer') return false;
        if (_marketerRowHasContract(r)) return false;
        final os = (r['status'] ?? '').toString().toLowerCase();
        if (os == 'withdrawn' ||
            os == 'cancelled' ||
            os == 'rejected' ||
            os == 'owner_rejected' ||
            os == 'declined') {
          return false;
        }
        if (os == 'owner_accepted' ||
            os == 'converted_to_contract' ||
            os == 'selected' ||
            os == 'approved') {
          return false;
        }
        if (_marketerRowInactive72h(r)) return false;
      }
      // تبويب «السوق العقاري» (0): فقط طلبات بانتظار مسوّقين بلا مسوّق مختار.
      if (tabIndex == 0) {
        if (!_isMarketerOpenMarketEligibleRow(r)) return false;
        if (_inviteHiddenDueToActiveMarketerOffer(r)) return false;
        if ((r['_open_market_synthetic'] ?? false) != true) {
          final reqId = _marketingRequestIdFromRow(r);
          if (reqId.isNotEmpty) {
            final invRound = (r['round_no'] as num?)?.toInt() ??
                (r['marketing_round'] as num?)?.toInt() ??
                1;
            final curRound = (r['marketing_round'] as num?)?.toInt() ?? 1;
            if (invRound < curRound) return false;
          }
        }
        return true;
      }
      if (tabIndex == 5 || tabIndex == 6) {
        final st = _workflowStageFromMarketerRow(r);
        final reqId = _marketingRequestIdFromRow(r);
        final exhausted =
            reqId.isNotEmpty && _exhaustedOpportunityRequestIds.contains(reqId);
        final moveCancel = _rowShouldMoveInactiveToCancelled(r);
        final purged = _rowShouldPurgeFromHub(r);
        if (tabIndex == 5) {
          if (exhausted || moveCancel || purged) return false;
          if (_marketerRowInactive72h(r) && involved(r)) {
            return true;
          }
          if (st != ListingWorkflowStage.inactive72h) {
            return false;
          }
        }
        if (tabIndex == 6) {
          if (purged) return false;
          final dismissKey = _marketerCancelledDismissKey(r);
          if (dismissKey.isNotEmpty &&
              _marketerDismissedCancelledIds.contains(dismissKey)) {
            return false;
          }
          // إن بقيت فرصة/مهلة نشطة في مسار 72 ساعة — لا تُعرض هنا.
          final reqId = _marketingRequestIdFromRow(r);
          final stillHasChance = reqId.isNotEmpty &&
              !_exhaustedOpportunityRequestIds.contains(reqId) &&
              _marketerRowInactive72h(r) &&
              !_rowShouldMoveInactiveToCancelled(r);
          if (stillHasChance) return false;

          final isCancelledStage = const {
            ListingWorkflowStage.cancelled,
            ListingWorkflowStage.contractCancelled,
            ListingWorkflowStage.terminated,
          }.contains(st);
          final os = (r['status'] ?? '').toString().toLowerCase().trim();
          final isCancelledOffer = const {
            'cancelled',
            'withdrawn',
            'rejected',
            'owner_rejected',
            'declined',
          }.contains(os);
          if (!isCancelledStage &&
              !isCancelledOffer &&
              !(moveCancel && !purged)) {
            return false;
          }
        }
        return involved(r) || _marketerWasPrevSelectedOnRow(r);
      }
      final st = _workflowStageFromMarketerRow(r);
      if (tabIndex == 1 && _marketerRowInactive72h(r)) return false;
      return ListingStageUiHelper.marketerTabMatches(
        tabIndex,
        st,
        publishedByMe: tabIndex == 4,
        involvedInContract: involved(r),
        hasInviteOrOffer: true,
      );
    }).toList();
  }

  Widget _marketerTabWithBadge(String label, int count) {
    return _buildAdaptiveTabWithBadge(label: label, count: count);
  }

  /// شارات تبويبات «صفحتي» للمالك — عدد العناصر الفعلي في كل تبويب.
  int _ownerMyPageTabBadgeCount(int tabBarIndex, List<Property> myItems) {
    switch (tabBarIndex) {
      case 0:
        return _filterOwnerHubTab(myItems, 0).length +
            _ownerRequestRowsWaitingNoOffers().length;
      case 1:
        return _ownerRequestRowsSubmittedOffersOnly().length;
      case 2:
        return _filterOwnerHubTab(myItems, 1).length +
            _ownerRequestRowsForTab(1).length;
      case 3:
        return _filterOwnerHubTab(myItems, 2).length +
            _ownerRequestRowsForTab(2).length;
      case 4:
        return _filterOwnerHubTab(myItems, 3).length +
            _ownerRequestRowsForTab(3).length;
      case 5:
        return _offers.length;
      case 6:
        return _filterOwnerHubTab(myItems, 6).length;
      default:
        return 0;
    }
  }

  Widget _ownerTabWithBadge(String label, int count) {
    return _buildAdaptiveTabWithBadge(label: label, count: count);
  }

  /// شارة عدد متكيّفة مع حجم الشاشة:
  /// - الجوال/المتصفح الضيّق: النص + الرقم بجوار بعضهما (لا يغطّي).
  /// - يستخدم [Badge] فقط على الشاشات الكبيرة جداً حيث يكون التداخل غير محسوس.
  /// النصوص الطويلة تُقصّ بـ [TextOverflow.ellipsis] بدلاً من الالتفاف.
  Widget _buildAdaptiveTabWithBadge({
    required String label,
    required int count,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (count <= 0) {
      return Tab(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      );
    }
    final text = count > 99 ? '99+' : '$count';
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(
              minWidth: 18,
              minHeight: 16,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: cs.error,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: cs.onError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// مسوّق يملك طلبات طرحها للسوق: TabBar ثابت (52px) + TabBarView بلا Scroll متداخل.
  /// نستفيد من شكل مقترح TabBar دون إعادة بناء الدلاء داخل SingleChildScrollView.
  Widget _buildMarketerDualRoleMyAds(ColorScheme cs, TabController mkCtrl) {
    _ensureMarketerPublisherRoleTabsCtrl();
    final roleCtrl = _marketerPublisherRoleTabsCtrl;
    final ownerCtrl = _ownerTabsCtrl;
    if (roleCtrl == null || ownerCtrl == null) {
      return _buildMarketerMyAds(cs, mkCtrl);
    }

    final ar = widget.isAr;
    final ownedCount = _ownerListingRequests.length;
    final attention = _ownerOffersAttentionCount;
    final isDark = cs.brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(context).width < 380;
    final barBg = isDark ? cs.surface : Colors.white;
    final hairline = isDark
        ? cs.outlineVariant.withValues(alpha: 0.45)
        : const Color(0xFFE5E7EB);

    Widget roleTab({
      required IconData icon,
      required String label,
      int badge = 0,
    }) {
      return Tab(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge > 0)
              Badge(
                isLabelVisible: true,
                label: Text(
                  '${badge.clamp(1, 99)}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: Icon(icon, size: narrow ? 16 : 18),
              )
            else
              Icon(icon, size: narrow ? 16 : 18),
            SizedBox(width: narrow ? 6 : 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: barBg,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: barBg,
              border: Border(bottom: BorderSide(color: hairline)),
            ),
            child: SizedBox(
              height: 52,
              child: TabBar(
                controller: roleCtrl,
                isScrollable: false,
                labelPadding: EdgeInsets.symmetric(horizontal: narrow ? 6 : 12),
                labelColor: _brandPrimary,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: _brandPrimary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: TextStyle(
                  fontSize: narrow ? 13 : 15,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: narrow ? 12 : 14,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  roleTab(
                    icon: Icons.business_center_outlined,
                    label: ar ? 'كمسوّق' : 'As marketer',
                  ),
                  roleTab(
                    icon: Icons.home_work_outlined,
                    label: ar
                        ? 'كمعلن ($ownedCount)'
                        : 'As publisher ($ownedCount)',
                    badge: attention,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: TabBarView(
              controller: roleCtrl,
              // كمعلن/كمسوّق: تبديل بالضغط فقط — السحب الأفقي للتبويبات الفرعية داخلياً.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                KeyedSubtree(
                  key: const ValueKey<String>('hub-role-marketer'),
                  child: _buildMarketerMyAds(cs, mkCtrl),
                ),
                KeyedSubtree(
                  key: const ValueKey<String>('hub-role-owner'),
                  child: _buildOwnerMyAds(cs, sortedMineForHub(), ownerCtrl),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketerMyAds(ColorScheme cs, TabController ctrl) {
    final l10n = AppLocalizations.of(context)!;
    final ar = widget.isAr;
    return Column(
      children: [
        _buildStableTabBar(
          cs: cs,
          controller: ctrl,
          showMarketerScenarioGuide: true,
          tabs: [
            _marketerTabWithBadge(
              l10n.marketerTabInvites,
              _marketerTabBadgeCount(0),
            ),
            _marketerTabWithBadge(
              l10n.marketerTabMyOffers,
              _marketerTabBadgeCount(1),
            ),
            _marketerTabWithBadge(
              l10n.marketerTabAwaitingOwner,
              _marketerTabBadgeCount(2),
            ),
            _marketerTabWithBadge(
              ar ? 'التصريح 72 ساعة' : 'Permit 72h',
              _marketerTabBadgeCount(3),
            ),
            _marketerTabWithBadge(
              ar ? 'منشور / محجوز' : 'Published / reserved',
              _marketerTabBadgeCount(4),
            ),
            _marketerTabWithBadge(
              ar ? 'بدون إجراء 72' : 'Inactive 72h',
              _marketerTabBadgeCount(5),
            ),
            _marketerTabWithBadge(
              ar ? 'مفسوخ / ملغى' : 'Terminated',
              _marketerTabBadgeCount(6),
            ),
          ],
        ),
        Expanded(
          child: ClipRect(
            child: _myAdsHubPreferSwipeableSubTabs
                ? TabBarView(
                    controller: ctrl,
                    physics: _myAdsHubTabViewPhysics,
                    children: [
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(0),
                        emptyText: l10n.marketerEmptyInvites,
                        type: 'invite',
                        marketerInvitesTabLayout: true,
                      ),
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(1),
                        emptyText: ar
                            ? 'لا توجد عروض تتبّعها حالياً'
                            : 'No offers to track',
                        type: 'offer',
                        marketerMyOffersTabLayout: true,
                      ),
                      _buildMarketerContractingTab(l10n),
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(3),
                        emptyText: l10n.marketerEmptyPermits,
                        type: 'permit',
                      ),
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(4),
                        emptyText: l10n.marketerEmptyPublished,
                        type: 'published',
                      ),
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(5),
                        emptyText: ar
                            ? 'لا توجد طلبات بدون إجراء 72 ساعة'
                            : 'No 72h inactive items',
                        type: 'inactive72h',
                      ),
                      _buildMarketerTabBody(
                        rows: _filterMarketerRowsForTab(6),
                        emptyText:
                            ar ? 'لا توجد عقارات مفسوخة' : 'Nothing cancelled',
                        type: 'cancelled',
                      ),
                    ],
                  )
                : AnimatedBuilder(
                    animation: ctrl,
                    builder: (context, _) {
                      // سطح مكتب عريض: تبويب واحد لكل إطار (أخف).
                      return KeyedSubtree(
                        key: ValueKey<int>(ctrl.index),
                        child: _buildMarketerHubSelectedTab(
                          ctrl.index,
                          l10n: l10n,
                          ar: ar,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  int _marketerTabBadgeCount(int tabIndex) {
    return _filterMarketerRowsForTab(tabIndex).length;
  }

  Widget _buildMarketerHubSelectedTab(
    int index, {
    required AppLocalizations l10n,
    required bool ar,
  }) {
    switch (index) {
      case 1:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(1),
          emptyText: ar ? 'لا توجد عروض تتبّعها حالياً' : 'No offers to track',
          type: 'offer',
          marketerMyOffersTabLayout: true,
        );
      case 2:
        return _buildMarketerContractingTab(l10n);
      case 3:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(3),
          emptyText: l10n.marketerEmptyPermits,
          type: 'permit',
        );
      case 4:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(4),
          emptyText: l10n.marketerEmptyPublished,
          type: 'published',
        );
      case 5:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(5),
          emptyText:
              ar ? 'لا توجد طلبات بدون إجراء 72 ساعة' : 'No 72h inactive items',
          type: 'inactive72h',
        );
      case 6:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(6),
          emptyText: ar ? 'لا توجد عقارات مفسوخة' : 'Nothing cancelled',
          type: 'cancelled',
        );
      case 0:
      default:
        return _buildMarketerTabBody(
          rows: _filterMarketerRowsForTab(0),
          emptyText: l10n.marketerEmptyInvites,
          type: 'invite',
          marketerInvitesTabLayout: true,
        );
    }
  }

  /// يحاول جلب الإعلانات الفعلية المتعلّقة بصف المسوّق حسب التبويب الحالي،
  /// عبر مطابقة `preview_property_id`/`listing_id` مع `_all`/`_mine`. إن لم
  /// تتوفّر معرّفات صريحة نُرجع الإعلانات التي يملكها المستخدم أو نشرها كمسوّق
  /// لاستخدامها قاعدةً للخريطة على الأقل.
  List<Property> _marketerListingsForCurrentTab(int tabIdx) {
    final rows = _filterMarketerRowsForTab(tabIdx);
    final ids = <String>{};
    for (final r in rows) {
      for (final k in const [
        'listing_id',
        'preview_property_id',
        'property_id',
      ]) {
        final v = (r[k] ?? '').toString().trim();
        if (v.isNotEmpty) ids.add(v);
      }
    }
    final pool = <String, Property>{};
    for (final p in _all) {
      pool[p.id] = p;
    }
    for (final p in _mine) {
      pool.putIfAbsent(p.id, () => p);
    }
    final list = <Property>[];
    for (final id in ids) {
      final p = pool[id];
      if (p != null) list.add(p);
    }
    if (list.isNotEmpty) return list;
    return _propertiesOwnedOrPublishedByMe();
  }

  Widget _buildMarketerContractingTab(AppLocalizations l10n) {
    final ar = widget.isAr;
    final merged = <Map<String, dynamic>>[
      ..._mkOffers.map((e) => {...e, '_hubKind': 'offer'}),
      ..._mkContracts.map((e) => {...e, '_hubKind': 'contract'}),
    ].where((r) {
      final hk = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString();
      if (hk == 'offer' && _marketerRowHasContract(r)) return false;
      return true;
    }).toList();
    final filtered = merged.where((r) {
      bool involved(Map<String, dynamic> row) {
        return (row['marketer_id'] ?? '').toString() == _uid ||
            (row['selected_marketer_id'] ?? '').toString() == _uid;
      }

      if (!involved(r)) return false;
      if (!_matchesHubRowSearch(r)) return false;
      if (!_matchesHubRowRanges(r)) return false;

      final st = _workflowStageFromMarketerRow(r);

      return ListingStageUiHelper.marketerTabMatches(
        2,
        st,
        publishedByMe: false,
        involvedInContract: true,
        hasInviteOrOffer: true,
      );
    }).toList();
    final rows = _dedupeMarketerHubRowsByRequest(filtered);

    if (_loadingMarketing && rows.isEmpty) {
      return _buildTabLoadingState(
        title: ar ? 'جارٍ تحميل الموافقات' : 'Loading approvals…',
      );
    }
    if (_errorMarketing != null && rows.isEmpty) {
      return _simpleErrorBox(
        title: ar ? 'تعذر تحميل الموافقات' : 'Failed to load',
        err: _errorMarketing!,
        onRetry: () => _loadMarketerBuckets(force: true),
      );
    }
    if (rows.isEmpty) {
      return ListView(
        physics: _myAdsHubScrollPhysics,
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Text(
              ar
                  ? 'لا توجد إعلانات بانتظار إصدار التصاريح بعد.'
                  : 'No listings awaiting permits yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return _buildSimpleRowsList(
      rows: rows,
      emptyText: l10n.marketerEmptyContracts,
      type: 'contract',
      marketerInvitesTabLayout: false,
      marketerHubUnifiedMarketCard: true,
    );
  }

  List<Map<String, dynamic>> _dedupeMarketerHubRowsByRequest(
    List<Map<String, dynamic>> rows,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final rid = _marketingRequestIdFromRow(r);
      if (rid.isEmpty) {
        out.add(r);
        continue;
      }
      if (!seen.add(rid)) continue;
      out.add(r);
    }
    return out;
  }

  Widget _buildStableTabBar({
    required ColorScheme cs,
    required TabController controller,
    required List<Widget> tabs,
    bool showMarketerScenarioGuide = false,
    bool showOwnerScenarioGuide = false,
  }) {
    return Material(
      color: cs.surface,
      elevation: 0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TabBar(
            controller: controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            splashBorderRadius: BorderRadius.circular(999),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => _brandPrimary.withValues(alpha: 0.06),
            ),
            labelPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            indicatorPadding: EdgeInsets.zero,
            indicator: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _brandPrimary.withValues(alpha: 0.16),
                  _brandPrimary.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _brandPrimary.withValues(alpha: 0.22),
              ),
            ),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            labelColor: _brandPrimary,
            unselectedLabelColor: cs.onSurfaceVariant,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: tabs
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 4,
                    ),
                    child: t,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMarketerTabBody({
    required List<Map<String, dynamic>> rows,
    required String emptyText,
    required String type,

    /// تخطيط زرّي «تفاصيل الإعلان» و«تقديم عرض» — تبويب **السوق العقاري** للمسوّق.
    bool marketerInvitesTabLayout = false,

    /// تبويب **عروضي** — زر تتبّع العرض أسفل البطاقة.
    bool marketerMyOffersTabLayout = false,
  }) {
    if (_loadingMarketing && rows.isEmpty) {
      return _buildTabLoadingState(
        title: widget.isAr
            ? 'جارٍ تحميل بيانات التسويق'
            : 'Loading marketing data',
      );
    }

    if (_errorMarketing != null && rows.isEmpty) {
      return _simpleErrorBox(
        title: widget.isAr
            ? 'تعذر تحميل بيانات التسويق'
            : 'Failed to load marketing data',
        err: _errorMarketing!,
        onRetry: () => _loadMarketerBuckets(force: true),
      );
    }

    return _buildSimpleRowsList(
      rows: rows,
      emptyText: emptyText,
      type: type,
      marketerInvitesTabLayout: marketerInvitesTabLayout,
      marketerMyOffersTabLayout: marketerMyOffersTabLayout,
      marketerHubUnifiedMarketCard: true,
    );
  }

  Widget _buildTabLoadingState({
    required String title,
  }) {
    // ويب: بدون عنوان «جارٍ التحميل» — يظهر الهيكل فقط حتى تصل البطاقات.
    if (kIsWeb) {
      return PropertyCardSkeletonList(
        key: ValueKey<String>('loading_$title'),
        count: 3,
        topPadding: 12,
      );
    }
    final cs = Theme.of(context).colorScheme;

    return PropertyCardSkeletonList(
      key: ValueKey<String>('loading_$title'),
      count: 5,
      topPadding: 24,
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
        ),
      ),
    );
  }

  String? _ownerRejectionReason(Property p) {
    String pickReason(Map<String, dynamic> row) {
      final keys = <String>[
        'rejection_reason',
        'owner_reject_reason',
        'decline_reason',
        'last_reject_reason',
        'reason',
        'notes',
      ];
      for (final k in keys) {
        final v = (row[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final pools = <List<Map<String, dynamic>>>[
      _ownerListingRequests,
    ];

    for (final pool in pools) {
      for (final row in pool) {
        final previewPropertyId =
            (row['preview_property_id'] ?? '').toString().trim();
        final status = (row['status'] ?? '').toString().trim().toLowerCase();
        if (previewPropertyId != p.id) continue;
        final reason = pickReason(row);
        if (reason.isNotEmpty &&
            (status.contains('reject') ||
                status.contains('declin') ||
                status.contains('return'))) {
          return reason;
        }
      }
    }

    return null;
  }

  String _trMarketingStatus(String? status,
      {bool ownerHubPerspective = false}) {
    final s = (status ?? '').trim().toLowerCase();

    if (widget.isAr) {
      switch (s) {
        case 'marketer_selected':
          return ownerHubPerspective
              ? 'بانتظار التصريح'
              : 'تمت الموافقة من المالك';
        case 'pending':
          return 'قيد الانتظار';
        case 'seen':
          return 'تمت المشاهدة';
        case 'declined':
          return 'مرفوضة';
        case 'expired':
          return 'منتهية';
        case 'new':
          return 'جديد';
        case 'invited':
          return 'تمت الدعوة';
        case 'submitted':
          return 'تم الإرسال';
        case 'assigned':
          return 'تم الإسناد';
        case 'contract':
          return 'بانتظار العقد';
        case 'draft':
          return 'مسودة عقد';
        case 'pending_owner':
          return 'بانتظار مراجعة المالك';
        case 'pending_marketer':
          return 'بانتظار تعديل المسوق';
        case 'signed':
          return 'تم التوقيع';
        case 'published':
          return 'منشور';
        case 'active':
          return 'نشط';
        case 'live':
          return 'ظاهر';
        case 'reserved':
          return 'محجوز';
        case 'sold':
          return 'مباع';
        case 'closed':
        case 'completed':
          return 'مكتمل';
        case 'waiting_marketers':
          return 'بانتظار المسوقين';
        case 'offers_received':
          return 'وصلت عروض';
        case 'contract_pending':
          return 'بانتظار العقد';
        case 'contract_sent':
          return 'أُرسل العقد للمالك';
        case 'contract_returned':
          return 'أُعيد العقد للتعديل';
        case 'contract_signed':
          return 'تم توقيع العقد';
        case 'permit_pending':
          return 'إصدار التصاريح — 72 ساعة';
        case 'permit_issued':
          return 'صدر التصريح';
        case 'permit_submitted':
          return 'تم رفع التصريح';
        case 'inactive_72h':
        case 'inactive72h':
          return 'بدون إجراء 72 ساعة';
        case 'approved':
          return 'معتمد';
        case 'rejected':
          return 'مرفوض';
        case 'owner_accepted':
          return 'تمت الموافقة من المالك';
        case 'owner_rejected':
          return 'لم يُختر';
        case 'cancelled':
          return 'ملغى';
        case 'converted_to_contract':
          return 'محوَّل لعقد';
        case 'withdrawn':
          return 'مسحوب';
        case 'marketer_revised':
          return 'عرض معدَّل';
        case 'marketer_accepted_rejection_reason':
          return 'قُبل سبب الرفض';
        case 'selected':
          return 'مختار';
        default:
          return status?.toString().trim().isNotEmpty == true
              ? status.toString()
              : 'غير محدد';
      }
    } else {
      switch (s) {
        case 'marketer_selected':
          return ownerHubPerspective ? 'Awaiting permit' : 'Owner approved';
        case 'pending':
          return 'Pending';
        case 'seen':
          return 'Seen';
        case 'declined':
          return 'Declined';
        case 'expired':
          return 'Expired';
        case 'new':
          return 'New';
        case 'invited':
          return 'Invited';
        case 'submitted':
          return 'Submitted';
        case 'assigned':
          return 'Assigned';
        case 'contract':
          return 'Awaiting contract';
        case 'draft':
          return 'Draft contract';
        case 'pending_owner':
          return 'Awaiting owner review';
        case 'pending_marketer':
          return 'Awaiting marketer revision';
        case 'signed':
          return 'Signed';
        case 'published':
          return 'Published';
        case 'active':
          return 'Active';
        case 'live':
          return 'Live';
        case 'reserved':
          return 'Reserved';
        case 'sold':
          return 'Sold';
        case 'closed':
        case 'completed':
          return 'Completed';
        case 'waiting_marketers':
          return 'Waiting marketers';
        case 'offers_received':
          return 'Offers received';
        case 'contract_pending':
          return 'Awaiting contract';
        case 'contract_sent':
          return 'Contract sent';
        case 'contract_returned':
          return 'Contract returned';
        case 'contract_signed':
          return 'Contract signed';
        case 'permit_pending':
          return 'Awaiting permit';
        case 'permit_issued':
          return 'Permit issued';
        case 'permit_submitted':
          return 'Permit submitted';
        case 'inactive_72h':
        case 'inactive72h':
          return 'No action 72h';
        case 'approved':
          return 'Approved';
        case 'rejected':
          return 'Rejected';
        case 'owner_accepted':
          return 'Owner approved';
        case 'owner_rejected':
          return 'Not selected';
        case 'cancelled':
          return 'Cancelled';
        case 'converted_to_contract':
          return 'Converted to contract';
        case 'withdrawn':
          return 'Withdrawn';
        case 'marketer_revised':
          return 'Revised offer';
        case 'marketer_accepted_rejection_reason':
          return 'Rejection reason accepted';
        case 'selected':
          return 'Selected';
        default:
          return status?.toString().trim().isNotEmpty == true
              ? status.toString()
              : 'N/A';
      }
    }
  }

  Color _marketingStatusColor(String? status, ColorScheme cs) {
    final s = (status ?? '').trim().toLowerCase();

    switch (s) {
      case 'signed':
      case 'approved':
      case 'published':
      case 'active':
        return Colors.green;

      case 'pending':
      case 'seen':
      case 'new':
      case 'invited':
      case 'submitted':
      case 'assigned':
      case 'contract':
      case 'pending_owner':
      case 'draft':
      case 'pending_marketer':
        return Colors.orange;

      case 'declined':
      case 'expired':
      case 'rejected':
      case 'owner_rejected':
      case 'cancelled':
      case 'withdrawn':
        return cs.error;

      case 'owner_accepted':
      case 'converted_to_contract':
      case 'selected':
        return Colors.green;

      case 'marketer_revised':
      case 'marketer_accepted_rejection_reason':
        return Colors.orange;

      case 'marketer_selected':
      case 'contract_pending':
      case 'contract_sent':
      case 'contract_returned':
      case 'waiting_marketers':
        return Colors.orange;

      case 'contract_signed':
      case 'permit_pending':
      case 'permit_issued':
        return Colors.teal.shade700;

      default:
        return cs.primary;
    }
  }

  String _mkRowTitle(Map<String, dynamic> r) {
    final typeLabel =
        PropertyListingDisplay.typeLabelForRequestRow(r, widget.isAr);
    String clean(String raw) => PropertyListingDisplay.sanitizeListingTitle(
          raw,
          typeLabel: typeLabel,
          isAr: widget.isAr,
        );

    final requestTitle =
        clean((r['request_title'] ?? '').toString().trim());
    final previewTitle =
        clean((r['preview_title'] ?? '').toString().trim());
    final title = clean((r['title'] ?? '').toString().trim());
    final city = (r['request_city'] ?? r['preview_city'] ?? r['city'] ?? '')
        .toString()
        .trim();

    if (requestTitle.isNotEmpty) return requestTitle;
    if (previewTitle.isNotEmpty) return previewTitle;
    if (title.isNotEmpty) return title;

    if (widget.isAr) {
      if (city.isNotEmpty) return 'طلب تسويق - $city';

      final type = (r['_ui_type'] ?? '').toString();
      switch (type) {
        case 'invite':
          return 'دعوة تسويق';
        case 'offer':
          return 'عرض تسويقي';
        case 'contract':
          return 'عقد تسويق';
        case 'permit':
          return 'تصريح تسويق';
        case 'published':
          return 'إعلان منشور';
        default:
          return 'طلب تسويق';
      }
    } else {
      if (city.isNotEmpty) return 'Marketing Request - $city';

      final type = (r['_ui_type'] ?? '').toString();
      switch (type) {
        case 'invite':
          return 'Marketing Invite';
        case 'offer':
          return 'Marketing Offer';
        case 'contract':
          return 'Marketing Contract';
        case 'permit':
          return 'Marketing Permit';
        case 'published':
          return 'Published Listing';
        default:
          return 'Marketing Request';
      }
    }
  }

  /// يكتشف تكرار العنوان/الوصف في بطاقات صفحتي (مسافات أو احتواء نصّي).
  bool _hubTextLooksLikeDuplicateTitle(String a, String b) {
    final na = a.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nb = b.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.length >= 8 && nb.contains(na)) return true;
    if (nb.length >= 8 && na.contains(nb)) return true;
    return false;
  }

  String _mkRowSubLine(Map<String, dynamic> r) {
    final city = (r['request_city'] ?? r['preview_city'] ?? r['city'] ?? '')
        .toString()
        .trim();
    final status = _trMarketingStatus(r['status']?.toString());

    if (widget.isAr) {
      return city.isNotEmpty ? '$city • الحالة: $status' : 'الحالة: $status';
    }
    return city.isNotEmpty ? '$city • Status: $status' : 'Status: $status';
  }

  String _mkTypeLabel(String type) {
    if (widget.isAr) {
      switch (type) {
        case 'invite':
          return 'دعوة';
        case 'offer':
          return 'عرض';
        case 'contract':
          return 'عقد';
        case 'permit':
          return 'تصريح';
        case 'published':
          return 'منشور';
        case 'inactive72h':
          return 'بدون إجراء';
        case 'cancelled':
          return 'مفسوخ / ملغى';
        default:
          return 'عنصر';
      }
    } else {
      switch (type) {
        case 'invite':
          return 'Invite';
        case 'offer':
          return 'Offer';
        case 'contract':
          return 'Contract';
        case 'permit':
          return 'Permit';
        case 'published':
          return 'Published';
        case 'inactive72h':
          return 'Inactive 72h';
        case 'cancelled':
          return 'Cancelled';
        default:
          return 'Item';
      }
    }
  }

  String _marketingDistrictFromPayload(Map<String, dynamic> r) {
    final m = _mergedJsonPayloadForRow(r);
    for (final k in const [
      'district',
      'neighborhood',
      'area_name',
    ]) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// أجزاء الموقع بدون تكرار (منطقة → محافظة → مدينة → حي).
  List<String> _marketingLocationHierarchyParts(Map<String, dynamic> r) {
    final m = _mergedJsonPayloadForRow(r);

    String pickAny(Iterable<String> keys) {
      for (final k in keys) {
        final v = (r[k] ?? m[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final region = pickAny(const [
      'preview_region',
      'region',
      'region_name',
      'preview_region_name',
    ]);
    final province = pickAny(const [
      'preview_province',
      'province',
      'governorate',
      'preview_governorate',
    ]);
    final city = pickAny(const [
      'preview_city',
      'request_city',
      'city',
    ]);
    final districtRaw = pickAny(const [
      'preview_district',
      'preview_neighborhood',
      'district',
      'neighborhood',
      'preview_area_name',
    ]);
    final district =
        districtRaw.isNotEmpty ? districtRaw : _marketingDistrictFromPayload(r);

    final seen = <String>{};
    final out = <String>[];
    for (final raw in [region, province, city, district]) {
      final t = _normalizeAdministrativeLocationPart(raw);
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
    }
    return out;
  }

  String _orderedLocationTriplet(String a, String b, String c) {
    final parts = <String>[
      if (a.trim().isNotEmpty) a.trim(),
      if (b.trim().isNotEmpty) b.trim(),
      if (c.trim().isNotEmpty) c.trim(),
    ];
    return parts.join(' — ');
  }

  /// يزيل بادئات «محافظة/منطقة/مدينة/حي» لتفادي «صامطة — محافظة صامطة».
  String _normalizeAdministrativeLocationPart(String? raw) {
    var t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    for (final prefix in ['محافظة ', 'منطقة ', 'مدينة ', 'حي ']) {
      if (t.startsWith(prefix)) {
        final stripped = t.substring(prefix.length).trim();
        if (stripped.isNotEmpty) t = stripped;
        break;
      }
    }
    return t;
  }

  /// منطقة → محافظة → مدينة → حي (بدون تكرار نفس الاسم).
  String _orderedLocationParts({
    String? region,
    String? province,
    String? city,
    String? district,
  }) {
    final seen = <String>{};
    final parts = <String>[];
    for (final raw in [region, province, city, district]) {
      final t = _normalizeAdministrativeLocationPart(raw);
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) parts.add(t);
    }
    return parts.join(' — ');
  }

  /// محافظة/منطقة — مدينة — حي (للبطاقات العربية: الأبعد إدارياً أولاً).
  String _propertyCardLocationLine(Property p) {
    final reg = (p.region ?? '').trim();
    final prov = (p.province ?? '').trim();
    final city = p.city.trim();
    var hood = (p.location ?? '').trim();
    if (hood.contains(' - ')) {
      final bits = hood
          .split(' - ')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (bits.length > 1 && city.isNotEmpty) {
        hood = bits.where((x) => x != city).join(' — ');
      }
    }
    final line = _orderedLocationParts(
      region: reg,
      province: prov,
      city: city,
      district: hood,
    );
    if (line.isNotEmpty) return line;
    return PropertyListingDisplay.cityLine(p);
  }

  String _marketingLocationText(Map<String, dynamic> r) {
    final m = _mergedJsonPayloadForRow(r);
    String pickRow(Iterable<String> keys) {
      for (final k in keys) {
        final v = (r[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    String pickAny(Iterable<String> keys) {
      for (final k in keys) {
        final v = (r[k] ?? m[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final region = pickAny(const [
      'preview_region',
      'region',
      'region_name',
      'preview_region_name',
    ]);
    final province = pickAny(const [
      'preview_province',
      'province',
      'governorate',
      'preview_governorate',
    ]);
    final city = pickAny(const [
      'preview_city',
      'request_city',
      'city',
    ]);
    final districtRaw = pickAny(const [
      'preview_district',
      'preview_neighborhood',
      'district',
      'neighborhood',
      'preview_area_name',
    ]);
    final district =
        districtRaw.isNotEmpty ? districtRaw : _marketingDistrictFromPayload(r);

    final ordered = _orderedLocationParts(
      region: region,
      province: province,
      city: city,
      district: district,
    );
    if (ordered.isNotEmpty) return ordered;

    final cityOnly = pickRow(const ['preview_city', 'request_city', 'city']);
    final loc = (r['preview_location'] ??
            r['preview_address_line'] ??
            r['request_location'] ??
            '')
        .toString()
        .trim();
    final extra = _marketingDistrictFromPayload(r);
    final locMerged =
        (loc.isNotEmpty && extra.isNotEmpty && !loc.contains(extra))
            ? '$loc — $extra'
            : (loc.isNotEmpty ? loc : extra);

    if (cityOnly.isNotEmpty && locMerged.isNotEmpty) {
      final cityKey = cityOnly.toLowerCase();
      if (!locMerged.toLowerCase().contains(cityKey)) {
        return '$cityOnly — $locMerged';
      }
      return locMerged;
    }
    if (cityOnly.isNotEmpty) return cityOnly;
    if (locMerged.isNotEmpty) return locMerged;

    return widget.isAr ? 'غير محدد' : 'N/A';
  }

  String _marketingOwnerName(Map<String, dynamic> r) {
    for (final k in const [
      'request_owner_full_name',
      'preview_owner_full_name',
      'owner_full_name',
      'request_owner_legal_name',
      'preview_owner_legal_name',
      'owner_legal_name',
      'request_owner_name',
      'preview_owner_name',
      'owner_name',
    ]) {
      final s = (r[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// `true` إذا كان المسوّق في تبويب «تم الموافقة» (المؤشر 2).
  bool get _marketerInApprovedWorkflowSubTab {
    final ctrl = _marketerTabsCtrl;
    if (ctrl == null) return false;
    return ctrl.index == 2;
  }

  /// @deprecated استخدم [_marketerInApprovedWorkflowSubTab]
  bool get _marketerInPermit72SubTab => _marketerInApprovedWorkflowSubTab;

  static const _regaBrokerEntry =
      'https://eservicesredp.rega.gov.sa/auth/queries/Brokerage';

  Future<void> _openRegaBrokerPortal() async {
    final u = Uri.parse(_regaBrokerEntry);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GovernmentInAppWebViewPage(
          uri: u,
          title: widget.isAr
              ? 'الهيئة العامة للعقار — استعلامات الوساطة'
              : 'REGA — brokerage inquiries',
        ),
      ),
    );
  }

  /// يُموِّه رقم الجوال السعودي إلى صيغة `******XXXX` مع إبقاء آخر 4 أرقام
  /// فقط — كافياً لتأكيد الرقم بصرياً دون كشف الخصوصية. يقبل أي طول ويعتمد
  /// على آخر 4 أرقام رقمية بعد إزالة الأحرف غير الرقمية.
  String _maskOwnerPhoneForMarketer(String raw) {
    if (raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return raw;
    final last4 = digits.substring(digits.length - 4);
    return '${'•' * (digits.length - 4)}$last4';
  }

  /// جوال المعلن للمسوّق — يظهر فقط بعد اختيار/موافقة المالك على هذا المسوّق.
  String _marketingOwnerPhone(Map<String, dynamic> r) {
    if (!_marketerMaySeeOwnerPhone(r)) return '';
    final m = _mergedJsonPayloadForRow(r);
    String pick(String k) => (r[k] ?? m[k] ?? '').toString().trim();

    for (final k in const [
      'preview_owner_phone',
      'request_owner_phone',
      'owner_phone',
      'contact_phone',
      'phone',
      'mobile',
      'owner_mobile',
    ]) {
      final n = _normalizeSaudiMobileTenDigits(pick(k));
      if (n != null) return n;
    }
    return '';
  }

  bool _marketerMaySeeOwnerPhone(Map<String, dynamic> r) {
    if (_listingRevealsOwnerPhoneFromMarket(r)) return true;
    final uid = _uid.trim();
    if (uid.isEmpty) return false;
    final selected = (r['selected_marketer_id'] ?? '').toString().trim();
    if (selected == uid) return true;
    return _marketerWasPrevSelectedOnRow(r);
  }

  /// هل أُتيحت فرصة محلية لهذا الطلب (تمييز الشارة عن «إعادة للسوق» فقط)؟
  bool _ownerRequestHasOpportunityGrant(Map<String, dynamic> r) {
    final id = (r['id'] ?? r['request_id'] ?? '').toString().trim();
    if (id.isEmpty) return false;
    final n = _opportunityGrantCountsByRequestId[id] ?? 0;
    if (n > 0) return true;
    final flag = r['_hub_opportunity_grant'];
    return flag == true || flag == 1 || '$flag'.toLowerCase() == 'true';
  }

  /// نص مرور لشارة الإعادة على بطاقة المالك.
  String _ownerRelistHoverText(Map<String, dynamic> r) {
    if (_ownerRequestHasOpportunityGrant(r)) {
      final id = (r['id'] ?? r['request_id'] ?? '').toString().trim();
      final n = _opportunityGrantCountsByRequestId[id] ?? 0;
      final ordinal =
          n > 0 ? OpportunityGrantStore.ordinalLabel(n, isAr: widget.isAr) : '';
      return widget.isAr
          ? 'إتاحة فرصة${ordinal.isEmpty ? '' : ' ($ordinal)'} من المعلن — يظهر للمسوّقين السابقين في تبويب عروضي.'
          : 'Opportunity granted${ordinal.isEmpty ? '' : ' ($ordinal)'} by the publisher — prior marketers see it under My offers.';
    }
    if (_allowPreviousMarketersRetryOnRequest(r)) {
      return widget.isAr
          ? 'أعاده المعلن للسوق العقاري — يظهر في بانتظار عروض المسوّقين، ويمكن للمسوّقين السابقين والجدد التقديم.'
          : 'Returned to the open market by the publisher — waiting for marketers; prior and new marketers may offer.';
    }
    final round = (r['marketing_round'] as num?)?.toInt() ?? 1;
    if (round > 1) {
      return widget.isAr
          ? 'طلب في جولة تسويق لاحقة بعد إتاحة فرصة أو إعادة للسوق.'
          : 'Later marketing round after granting another chance or returning to market.';
    }
    return _marketRelistReasonText(r);
  }

  /// سبب إعادة الطرح للسوق (للشارة «معادة» + الاستفهام).
  String _marketRelistReasonText(Map<String, dynamic> r) {
    final payload = _mergedJsonPayloadForRow(r);
    String pick(dynamic v) => (v ?? '').toString().trim();
    final candidates = <String>[
      pick(r['owner_action_reason']),
      pick(r['return_to_market_reason']),
      pick(r['relist_reason']),
      pick(payload['owner_action_reason']),
      pick(payload['return_to_market_reason']),
      pick(payload['relist_reason']),
      pick(r['lost_reason']),
    ].where((s) => s.isNotEmpty).toList();
    if (candidates.isNotEmpty) {
      final raw = candidates.first;
      final lower = raw.toLowerCase();
      if (lower.contains('inactive') ||
          lower.contains('72') ||
          lower.contains('permit')) {
        return widget.isAr
            ? 'أُعيد للسوق بعد انتهاء مهلة 72 ساعة دون إتمام إجراء من المسوّق المختار.'
            : 'Returned to market after 72h without action by the selected marketer.';
      }
      if (lower.contains('return') || lower.contains('relist')) {
        return widget.isAr
            ? 'أعاد المالك/المعلن الطلب إلى السوق العقاري لجولة جديدة.'
            : 'The owner returned this request to the open market for a new round.';
      }
      return raw;
    }
    if (_allowPreviousMarketersRetryOnRequest(r)) {
      return widget.isAr
          ? 'طلب معاد للسوق العقاري — يمكن للمسوّقين تقديم عروض مجدداً.'
          : 'Relisted on the open market — marketers may submit offers again.';
    }
    return widget.isAr
        ? 'أُعيد طرح هذا الطلب في السوق العقاري.'
        : 'This request was returned to the open market.';
  }

  void _showMarketRelistReasonDialog(Map<String, dynamic> r) {
    if (!mounted) return;
    final reason = _marketRelistReasonText(r);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isAr ? 'سبب الإعادة للسوق' : 'Why relisted?'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(widget.isAr ? 'حسناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  String? _normalizeSaudiMobileTenDigits(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    var d = s.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('966')) {
      d = '0${d.substring(3)}';
    }
    if (d.length > 10) {
      d = d.substring(d.length - 10);
    }
    if (d.length == 9 && d.startsWith('5')) {
      d = '0$d';
    }
    if (d.length == 10 &&
        d.startsWith('0') &&
        RegExp(r'^0[5-9]\d{8}$').hasMatch(d)) {
      return d;
    }
    return null;
  }

  String _marketingOwnerAvatarUrl(Map<String, dynamic> r) {
    for (final k in const [
      'request_owner_avatar_url',
      'preview_owner_avatar_url',
      'owner_avatar_url',
    ]) {
      final s = (r[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// رقم الإعلان العام (10 أرقام) إن وُجد في الصف — لإخفاء تكرار «رقم طلب التسويق».
  String? _hubTenDigitPublicListingCodeRaw(Map<String, dynamic> r) {
    String raw = (r['listing_request_public_code'] ?? '').toString().trim();
    if (raw.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(raw)) {
      raw = (r['preview_listing_public_code'] ?? r['listing_public_code'] ?? '')
          .toString()
          .trim();
    }
    if (raw.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(raw)) {
      return raw;
    }
    return null;
  }

  /// رقم الإعلان مع [FittedBox] لتفادي التفاف السطر على الشاشات الضيّقة.
  Widget _hubMarketerListingIdRow(
    Map<String, dynamic> r,
    ColorScheme cs, {
    bool listingIdGreen = false,
  }) {
    return Builder(
      builder: (_) {
        final raw = _hubTenDigitPublicListingCodeRaw(r);
        if (raw == null) return const SizedBox.shrink();
        final code = DisplayIds.tenDigit(raw);
        final accent = listingIdGreen ? const Color(0xFF1B5E20) : cs.primary;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: LayoutBuilder(
            builder: (_, c) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: c.maxWidth.isFinite && c.maxWidth > 0
                        ? c.maxWidth
                        : 9999,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.isAr
                              ? 'رقم الإعلان: $code'
                              : 'Listing no.: $code',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: accent,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: widget.isAr
                            ? 'نسخ رقم الإعلان'
                            : 'Copy listing no.',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: Icon(Icons.copy_rounded, color: accent),
                        onPressed: () => _copyPlainToClipboard(
                          code,
                          widget.isAr ? 'تم النسخ' : 'Copied',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _formatListingRequestCreatedFull(DateTime local) {
    try {
      // أرقام لاتينية دائماً (ويب جوال / تطبيق / ويندوز).
      return DateFormat('yyyy/MM/dd HH:mm', 'en').format(local);
    } catch (_) {
      return local.toIso8601String();
    }
  }

  String _hubAsciiDigits(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in input.split('')) {
      final ei = eastern.indexOf(ch);
      if (ei >= 0) {
        b.write('$ei');
        continue;
      }
      final pi = persian.indexOf(ch);
      if (pi >= 0) {
        b.write('$pi');
        continue;
      }
      b.write(ch);
    }
    return b.toString();
  }

  String _hubDeedNumberFromRow(Map<String, dynamic> r, [Property? prop]) {
    final fromProp = (prop?.deedNumber ?? '').toString().trim();
    if (fromProp.isNotEmpty) return _hubAsciiDigits(fromProp);
    for (final k in const [
      'deed_number',
      'preview_deed_number',
      'request_deed_number',
    ]) {
      final v = (r[k] ?? '').toString().trim();
      if (v.isNotEmpty) return _hubAsciiDigits(v);
    }
    final payload = r['payload_json'] ?? r['payload'];
    if (payload is Map) {
      final v = (payload['deed_number'] ?? payload['preview_deed_number'] ?? '')
          .toString()
          .trim();
      if (v.isNotEmpty) return _hubAsciiDigits(v);
    }
    return '';
  }

  String _hubDeedDateFromRow(Map<String, dynamic> r, [Property? prop]) {
    dynamic raw = prop?.deedDate;
    if (raw == null) {
      for (final k in const [
        'deed_date',
        'preview_deed_date',
        'request_deed_date',
      ]) {
        if (r[k] != null && '${r[k]}'.trim().isNotEmpty) {
          raw = r[k];
          break;
        }
      }
    }
    if (raw == null) {
      final payload = r['payload_json'] ?? r['payload'];
      if (payload is Map) {
        raw = payload['deed_date'] ?? payload['preview_deed_date'];
      }
    }
    if (raw == null) return '';
    if (raw is DateTime) {
      return DateFormat('yyyy/MM/dd', 'en').format(raw.toLocal());
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateFormat('yyyy/MM/dd', 'en').format(dt.toLocal());
    }
    return _hubAsciiDigits(s);
  }

  /// يحدّد مُعرّف الطرف الآخر لعرض حالة الاتصال (متصل الآن / آخر ظهور)
  /// داخل بطاقات «صفحتي» — فقط بعد موافقة المالك / اختيار المسوّق.
  String _hubPeerUserIdFromRow(
    Map<String, dynamic> r, {
    required bool marketerView,
  }) {
    if (marketerView) {
      if (!_marketerOwnerChatUnlocked(r)) return '';
      return (r['request_owner_id'] ?? r['owner_id'] ?? '').toString().trim();
    }
    return (r['selected_marketer_id'] ?? '').toString().trim();
  }

  /// متصل/آخر ظهور + الاسم: بعد موافقة المالك فقط (ليس في السوق ولا قبل القبول).
  bool _hubMayShowPeerPresenceOnCard(
    Map<String, dynamic> r, {
    required bool marketerView,
  }) {
    if (marketerView) return _marketerOwnerChatUnlocked(r);
    return (r['selected_marketer_id'] ?? '').toString().trim().isNotEmpty;
  }

  Widget _hubPeerPresenceStrip(
    Map<String, dynamic> r, {
    required bool marketerView,
    bool showAdvertiserName = false,
    bool showMarketerName = false,
  }) {
    if (!_hubMayShowPeerPresenceOnCard(r, marketerView: marketerView)) {
      return const SizedBox.shrink();
    }
    final uid = _hubPeerUserIdFromRow(r, marketerView: marketerView);
    if (uid.isEmpty || uid == _uid) return const SizedBox.shrink();

    final ownerName = marketerView ? _marketingOwnerName(r).trim() : '';
    final marketerName =
        !marketerView ? _marketingPeerMarketerName(r).trim() : '';
    final showOwner = showAdvertiserName && ownerName.isNotEmpty;
    final showMk = showMarketerName && marketerName.isNotEmpty;
    final peerLabel = showOwner
        ? (widget.isAr ? 'المعلن' : 'Advertiser')
        : (showMk ? (widget.isAr ? 'المسوق' : 'Marketer') : '');
    final peerName = showOwner ? ownerName : (showMk ? marketerName : '');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (peerLabel.isNotEmpty && peerName.isNotEmpty)
            LayoutBuilder(
              builder: (_, c) {
                final mw =
                    c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
                final adaptive = PropertyListingDisplay.scaleDisplayNameParts(
                  peerName,
                  mw,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        peerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        adaptive.isEmpty ? peerName : adaptive,
                        maxLines: 5,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.25,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          UserPresenceStrip(
            userId: uid,
            isAr: widget.isAr,
            compact: true,
            surface: PresenceDisplaySurface.listingCards,
          ),
        ],
      ),
    );
  }

  /// اسم المسوّق الظاهر للمالك على بطاقات التصاريح/التعاقد.
  String _marketingPeerMarketerName(Map<String, dynamic> r) {
    for (final k in const [
      'selected_marketer_full_name',
      'selected_marketer_name',
      'marketer_full_name',
      'marketer_display_name',
      'preview_marketer_full_name',
      'preview_marketer_name',
      '_marketer_display_name',
    ]) {
      final s = (r[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    Map<String, dynamic>? snap;
    final raw = r['preview_marketing_license_snapshot'] ??
        r['marketing_license_snapshot'];
    if (raw is Map) {
      snap = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) snap = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return Property.marketerEntityLineFromLicenseSnapshot(snap, widget.isAr) ??
        '';
  }

  Widget _hubRequestCreatedDateTimeRow(Map<String, dynamic> r, ColorScheme cs) {
    final raw = (r['created_at'] ??
            r['request_created_at'] ??
            r['preview_created_at'] ??
            r['listing_request_created_at'] ??
            '')
        .toString()
        .trim();
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return const SizedBox.shrink();
    final line = widget.isAr
        ? 'تاريخ ووقت الإعلان: ${_formatListingRequestCreatedFull(dt)}'
        : 'Listing date & time: ${_formatListingRequestCreatedFull(dt)}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LayoutBuilder(
        builder: (_, c) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              alignment: AlignmentDirectional.centerStart,
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.event_note_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        line,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMarketingListingViewsDialog(int? views) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final ar = widget.isAr;
        final body = (views != null && views >= 0)
            ? (ar ? 'عدد المشاهدات: $views' : 'View count: $views')
            : (ar
                ? 'لا تتوفر بيانات عدد المشاهدات.'
                : 'No view count available.');
        return AlertDialog(
          title: Text(ar ? 'المشاهدات' : 'Listing views'),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ar ? 'حسناً' : 'OK'),
            ),
          ],
        );
      },
    );
  }

  /// سعر العقار/المعاينة فوق أزرار الذيل — للبطاقة الموحّدة وتبويب السوق.
  Widget _hubMarketerPriceStrip(Map<String, dynamic> r, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LayoutBuilder(
        builder: (ctx, cts) {
          final maxW = cts.maxWidth;
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              alignment: AlignmentDirectional.centerStart,
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxW.isFinite && maxW > 0 ? maxW : 9999,
                ),
                child: _buildMarketingPriceLine(
                  r,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.25,
                  ),
                  // — قاعدة موحّدة: البطاقة تعرض السعر الأساسي فقط (الذي أدخله
                  //   المعلن). تفصيل الفاتورة (الضريبة + العمولة + المجموع
                  //   النهائي) يظهر فقط داخل تفاصيل الإعلان.
                  displayListingTotalIncVatAndFee: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarketingPriceLine(
    Map<String, dynamic> r, {
    required TextStyle style,

    /// سعر البطاقة الموحّدة: الأساس + 5٪ ضريبة + 2.5٪ أتعاب (غير المزاد).
    bool displayListingTotalIncVatAndFee = false,
  }) {
    final isAuction = r['preview_is_auction'] == true;
    final currency = (r['preview_currency'] ?? 'SAR').toString().trim();
    final curr = currency.isEmpty ? 'SAR' : currency;
    final previewPrice = (r['preview_price'] as num?)?.toDouble() ?? 0.0;
    final requestPrice = (r['request_price'] as num?)?.toDouble() ?? 0.0;
    final rowPrice = (r['price'] is num) ? (r['price'] as num).toDouble() : 0.0;
    final currentBid = (r['preview_current_bid'] as num?)?.toDouble() ?? 0.0;
    final baseValue = isAuction
        ? currentBid
        : (previewPrice > 0
            ? previewPrice
            : (requestPrice > 0
                ? requestPrice
                : (rowPrice > 0 ? rowPrice : 0.0)));

    if (baseValue <= 0) {
      return Text(
        widget.isAr ? 'السعر غير محدد' : 'Price not set',
        style: style,
      );
    }
    final amount = displayListingTotalIncVatAndFee && !isAuction
        ? MarketingOfferFee.listingDisplayTotalIncVatAndFee(baseValue)
        : baseValue;
    return AppMoneyLine(
      amount: AppMoney.roundSar(amount, fractionDigits: 0),
      currencyCode: curr,
      isAr: widget.isAr,
      maxFractionDigits: 0,
      style: style,
    );
  }

  List<Widget> _marketingPropertyChips(Map<String, dynamic> r) {
    final chips = <Widget>[];

    if (r['_hub_prior_round_marketer_offer'] == true) {
      chips.add(
        _miniStatChip(
          icon: Icons.history_edu_outlined,
          content: Text(
            widget.isAr ? 'سبق إتمام صفقة' : 'Prior-round deal',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    final purposeLabel =
        PropertyListingDisplay.purposeLabelForRequestRow(r, widget.isAr);
    if (purposeLabel.trim().isNotEmpty) {
      chips.add(
        _miniStatChip(
          icon: Icons.sell_outlined,
          content: Text(
            purposeLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    chips.add(
      _miniStatChip(
        icon: Icons.payments_outlined,
        content: _buildMarketingPriceLine(
          r,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            height: 1.2,
          ),
          // — السعر داخل بطاقات «إعلاناتي/طلباتي» للمسوّق يعرض السعر الأساسي
          //   فقط. تفصيل الفاتورة يظهر داخل صفحة تفاصيل الإعلان.
          displayListingTotalIncVatAndFee: false,
        ),
      ),
    );

    final type = (r['preview_type'] ?? r['request_property_type'] ?? '')
        .toString()
        .trim();
    final areaPreview = (r['preview_area'] as num?)?.toDouble();
    final areaReq = (r['request_area'] as num?)?.toDouble();
    final area = ((areaPreview ?? 0) > 0) ? areaPreview : areaReq;
    final beds = (r['preview_bedrooms'] as num?)?.toInt();
    final baths = (r['preview_bathrooms'] as num?)?.toInt();
    final parking = (r['preview_parking_spots'] as num?)?.toInt();

    if (type.isNotEmpty) {
      chips.add(
        _miniStatChip(
          icon: Icons.home_work_outlined,
          content: Text(
            widget.isAr ? _trPropertyTypeAr(type) : _trPropertyTypeEn(type),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    if (area != null && area > 0) {
      chips.add(
        _miniStatChip(
          icon: Icons.straighten_outlined,
          content: Text(
            widget.isAr
                ? '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} م²'
                : '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} m²',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    if (beds != null && beds > 0) {
      chips.add(
        _miniStatChip(
          icon: Icons.bed_outlined,
          content: Text(
            widget.isAr ? '$beds غرف' : '$beds Beds',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    if (baths != null && baths > 0) {
      chips.add(
        _miniStatChip(
          icon: Icons.bathtub_outlined,
          content: Text(
            widget.isAr ? '$baths حمام' : '$baths Baths',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    if (parking != null && parking > 0) {
      chips.add(
        _miniStatChip(
          icon: Icons.local_parking_outlined,
          content: Text(
            widget.isAr ? '$parking موقف' : '$parking Parking',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    final pubRaw = (r['preview_published_at'] ?? '').toString().trim();
    final createdAtRaw =
        (r['created_at'] ?? r['request_created_at'] ?? r['preview_created_at'])
            .toString()
            .trim();
    final pubDt = DateTime.tryParse(pubRaw)?.toLocal();
    final creDt = DateTime.tryParse(createdAtRaw)?.toLocal();
    if (pubDt != null) {
      chips.add(
        _miniStatChip(
          icon: Icons.publish_outlined,
          content: Text(
            widget.isAr
                ? 'نشر الطلب ${_timeAgo(pubDt, widget.isAr)}'
                : 'Published ${_timeAgo(pubDt, widget.isAr)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    } else if (creDt != null) {
      chips.add(
        _miniStatChip(
          icon: Icons.schedule_outlined,
          content: Text(
            widget.isAr
                ? 'إنشاء الطلب ${_timeAgo(creDt, widget.isAr)}'
                : 'Request ${_timeAgo(creDt, widget.isAr)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      );
    }

    return chips;
  }

  Widget _miniStatChip({
    required IconData icon,
    required Widget content,
  }) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = constraints.maxWidth;
        final maxW = (cap.isFinite && cap > 0) ? cap.clamp(80.0, 280.0) : 280.0;
        return Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.40),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 14, color: _brandPrimary),
              ),
              const SizedBox(width: 6),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  String _trPropertyTypeAr(String raw) => PropertyTypeCatalog.label(raw, true);

  String _trPropertyTypeEn(String raw) => PropertyTypeCatalog.label(raw, false);

  /// شبكة «صفحتي» كالرئيسية: قائمة للعُرض الضيّق (أقل من 600)، شبكة بعدها.
  bool _useGridLayout(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 600;
  }

  /// فيزياء تمرير «صفحتي» — Clamping على الويب الجوال لتقليل التعارض مع سحب التبويبات.
  ScrollPhysics get _myAdsHubScrollPhysics {
    if (kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const AlwaysScrollableScrollPhysics();
  }

  /// الجوال / ويب اللمس: السحب يحرّك تبويبات السوق/عروضي… لا دور كمسوّق/كمعلن.
  bool get _myAdsHubPreferSwipeableSubTabs =>
      !kIsWeb || AqarScrollBehavior.isCompactTouchLike(context);

  ScrollPhysics get _myAdsHubTabViewPhysics {
    if (kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)) {
      return const BouncingScrollPhysics(
        parent: PageScrollPhysics(),
      );
    }
    return const PageScrollPhysics();
  }

  double get _myAdsHubListCacheExtent =>
      kIsWeb && AqarScrollBehavior.isCompactTouchLike(context) ? 320 : 280;

  /// يعتمد على [AqarScrollBehavior] العام — لا نلفّ بـ Scrollbar إضافي (كان يعطّل الويب).
  Widget _myAdsHubScrollWrap(Widget child) => child;

  double _marketerHubScrollBottomPadding(BuildContext context) {
    // هامش خفيف فقط فوق شريط التنقل — بدون فراغ كبير مهدر.
    return 4;
  }

  int _hubPropertyCrossAxisCount(double width) =>
      _homeListingGridCrossAxisCount(width);

  Widget _buildOwnerMarketingRequestsFeed(
    List<Map<String, dynamic>> requestRows, {
    int ownerMarketingFeedScope = 0,
  }) {
    final useGrid = _useGridLayout(context);
    if (!useGrid) {
      return _myAdsHubScrollWrap(
        ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          physics: _myAdsHubScrollPhysics,
          cacheExtent: _myAdsHubListCacheExtent,
          itemCount: requestRows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _buildOwnerListingRequestCard(
            requestRows[i],
            horizontalLayout: true,
            ownerMarketingFeedScope: ownerMarketingFeedScope,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cross = _hubPropertyCrossAxisCount(c.maxWidth);
        const spacing = 10.0;
        final padH = c.maxWidth >= 900 ? 18.0 : 12.0;
        final rows = <Widget>[];
        for (var start = 0; start < requestRows.length; start += cross) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: spacing));
          final end = start + cross > requestRows.length
              ? requestRows.length
              : start + cross;
          final chunk = requestRows.sublist(start, end);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < cross; j++) ...[
                    if (j > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: j < chunk.length
                          ? _buildOwnerListingRequestCard(
                              chunk[j],
                              horizontalLayout: true,
                              ownerMarketingFeedScope: ownerMarketingFeedScope,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return _myAdsHubScrollWrap(
          ListView(
            padding: EdgeInsets.symmetric(horizontal: padH),
            physics: _myAdsHubScrollPhysics,
            children: rows,
          ),
        );
      },
    );
  }

  String _safeNotifString(dynamic v) => (v ?? '').toString().trim();

  Future<void> _sendInAppNotification({
    required String userId,
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
    required String status,
    required String role,
    String? requestId,
    String? previewPropertyId,
    String entityType = 'listing_request',
    String notificationType = 'workflow',
    String? entityId,
    String? deepRoute,
    int? myAdsSubTab,
    Map<String, dynamic>? extraData,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    final reqId = _safeNotifString(requestId);
    final propId = _safeNotifString(previewPropertyId);
    final rawEntityId = _safeNotifString(entityId);
    final entId = rawEntityId.isEmpty ? reqId : rawEntityId;

    final dr = _safeNotifString(deepRoute);
    final data = <String, dynamic>{
      WorkflowNotificationKeys.role: role,
      WorkflowNotificationKeys.status: status,
      WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
      'title_ar': titleAr,
      'title_en': titleEn,
      'body_ar': bodyAr,
      'body_en': bodyEn,
      if (reqId.isNotEmpty) WorkflowNotificationKeys.requestId: reqId,
      if (propId.isNotEmpty) WorkflowNotificationKeys.previewPropertyId: propId,
      if (dr.isNotEmpty) WorkflowNotificationKeys.deepRoute: dr,
      if (myAdsSubTab != null)
        WorkflowNotificationKeys.myAdsSubTab: '$myAdsSubTab',
      if (myAdsSubTab != null) WorkflowNotificationKeys.hubTabSchemaV: '4',
      if (extraData != null) ...extraData,
    };

    await InAppNotificationWriter.insert(
      _sb,
      userId: uid,
      type: notificationType,
      data: data,
      titleFallbackAr: titleAr,
      bodyFallbackAr: bodyAr,
      entityType: entityType,
      entityId: entId,
    );
  }

  Future<void> _openMarketerInviteDetails(Map<String, dynamic> r) async {
    final hub =
        (r['_hubKind'] ?? r['_ui_type'] ?? '').toString().trim().toLowerCase();
    final inviteId = hub == 'invite'
        ? (r['id'] ?? '').toString().trim()
        : (r['invite_id'] ?? r['inviteId'] ?? '').toString().trim();
    final requestId = _marketingRequestIdFromRow(r);
    if (requestId.isEmpty) return;

    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        settings:
            const RouteSettings(name: '/dashboard/marketer-request-details'),
        builder: (_) => MarketerRequestDetailsPage(
          lang: widget.lang,
          inviteId: inviteId,
          requestId: requestId,
          embedAppBar: false,
        ),
      ),
    );

    if (ok == true && mounted) {
      await _loadMarketerBuckets(force: true);
    }
  }

  List<Widget> _marketerContractActionWidgets(Map<String, dynamic> r) {
    final ar = widget.isAr;
    // قد يكون الصف عرضاً مدمجاً يحمل contract_id — لا تستخدم id العرض كمعرّف عقد.
    Map<String, dynamic> contractRow = r;
    var cid = (r['contract_id'] ?? '').toString().trim();
    if (cid.isEmpty) {
      final requestId = _marketingRequestIdFromRow(r);
      if (requestId.isNotEmpty) {
        for (final c in _mkContracts) {
          if ((c['request_id'] ?? '').toString().trim() == requestId) {
            cid = (c['id'] ?? '').toString().trim();
            if (cid.isNotEmpty) {
              contractRow = Map<String, dynamic>.from(c);
            }
            break;
          }
        }
      }
    }
    if (cid.isEmpty) cid = (contractRow['id'] ?? '').toString().trim();
    if (cid.isEmpty) return const [];
    final mid = (contractRow['marketer_id'] ?? r['marketer_id'] ?? '')
        .toString()
        .trim();
    if (mid.isNotEmpty && mid != _uid) return const [];

    final st = (contractRow['status'] ??
            contractRow['contract_status'] ??
            r['contract_status'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    switch (st) {
      case 'draft':
        return [
          FilledButton.icon(
            onPressed: () => _rpcSendListingContractToOwner(cid),
            icon: const Icon(Icons.send_outlined),
            label: Text(ListingWorkflowCopy.btnSendContract(ar)),
          ),
          TextButton.icon(
            onPressed: () => _rpcCancelListingContract(cid),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(ListingWorkflowCopy.btnCancelContract(ar)),
          ),
        ];
      case 'pending_marketer':
        final reason = (contractRow['returned_reason'] ?? '').toString().trim();
        return [
          Text(
            ListingWorkflowCopy.marketerContractReturnedTitle(ar),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${ListingWorkflowCopy.lblReturnReason(ar)}: $reason',
              style: const TextStyle(fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _rpcSendListingContractToOwner(cid),
            icon: const Icon(Icons.send_outlined),
            label: Text(ListingWorkflowCopy.btnResendContract(ar)),
          ),
          TextButton.icon(
            onPressed: () => _rpcCancelListingContract(cid),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(ListingWorkflowCopy.btnCancelContract(ar)),
          ),
        ];
      case 'pending_owner':
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              ListingWorkflowCopy.marketerAwaitingContractTitle(ar),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ];
      case 'signed':
        return [
          Text(
            ListingWorkflowCopy.contractSignedDone(ar),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ];
      case 'cancelled':
        return [
          Text(
            ListingWorkflowCopy.contractCancelledDone(ar),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  Future<void> _rpcCancelListingContract(String contractId) async {
    final ar = widget.isAr;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ListingWorkflowCopy.btnCancelContract(ar)),
        content: AqarTextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: ar ? 'السبب (اختياري)' : 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ListingWorkflowCopy.btnCancelContract(ar)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      const MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.postPaidUnlock,
      ),
    )) {
      return;
    }
    try {
      await _net<void>(() async {
        await MarketingFlowService(_sb).cancelListingContract(
          contractId: contractId,
          reason: ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
        );
      }, tag: 'CAN_CTR');
      if (!mounted) return;
      _showNotification(
        ar ? 'تم' : 'Done',
        ListingWorkflowCopy.contractCancelledDone(ar),
      );
      playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
      AppHaptics.heavy();
      await _loadMarketerBuckets(force: true);
    } catch (e) {
      if (!mounted) return;
      _showNotification(ar ? 'خطأ' : 'Error', e.toString(), isError: true);
    }
  }

  Future<void> _openMarketerChatWithOwnerGated(Map<String, dynamic> r) async {
    if (!_marketerOwnerChatUnlocked(r)) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'تُفتح الدردشة مع المالك بعد موافقته على عرضك فقط.'
            : 'Chat with the owner opens only after they accept your offer.',
        isError: false,
      );
      return;
    }
    final rid = _marketingRequestIdFromRow(r);
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.contractChat,
        requestId: rid,
        hubKind: 'contract',
        contractId: (r['contract_id'] ?? r['id'] ?? '').toString().trim(),
      ),
    )) {
      return;
    }
    await _openMarketerChatWithOwnerForRow(r);
  }

  Future<void> _rpcSendListingContractToOwner(String contractId) async {
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      const MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.postPaidUnlock,
      ),
    )) {
      return;
    }
    final ar = widget.isAr;
    try {
      await _net<void>(() async {
        await MarketingFlowService(_sb).sendListingContractToOwner(contractId);
      }, tag: 'SEND_CTR');
      if (!mounted) return;
      _showNotification(
        ar ? 'تم' : 'Done',
        ar ? 'تم إرسال العقد للمالك' : 'Contract sent to owner',
      );
      playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
      AppHaptics.light();
      await _loadMarketerBuckets(force: true);
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        ar ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
      playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
    }
  }

  Future<void> _createMarketingContract(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    final ownerId =
        (row['request_owner_id'] ?? row['owner_id'] ?? '').toString().trim();
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();
    var offerId = (row['selected_offer_id'] ?? '').toString().trim();
    if (offerId.isEmpty) {
      // صف العرض في تبويب إصدار التصريح: id هو معرّف العرض.
      final hk = (row['_hubKind'] ?? row['_ui_type'] ?? '').toString();
      if (hk == 'offer' ||
          (row['offer_price'] != null || row['offer_amount'] != null)) {
        offerId = (row['id'] ?? '').toString().trim();
      }
    }

    if (requestId.isEmpty || ownerId.isEmpty) return;
    if (offerId.isEmpty) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'لا يوجد عرض مقبول مرتبط بهذا الطلب. يجب أن يقبل المالك عرضك أولاً.'
            : 'No accepted offer is linked. The owner must accept your offer first.',
        isError: true,
      );
      return;
    }

    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.createContract,
        requestId: requestId,
        hubKind: 'offer',
        offerId: offerId,
      ),
    )) {
      return;
    }
    if (!mounted) return;

    final confirmed = await showAppConfirmDialog(
      context: context,
      title:
          widget.isAr ? 'التوقيع في مرجعية العقد' : 'Signature on contract PDF',
      message: widget.isAr
          ? 'تأكيد أن التوقيع الإلكتروني المحفوظ في ملفك الشخصي سيُدرَج في ملف PDF المرجعي للعقد عند التصدير، وأن بيانات العقار في المسودة صحيحة قبل المتابعة.'
          : 'Confirm your saved profile signature will be embedded in the exported contract PDF, and that listing details in the draft are correct before continuing.',
      confirmLabel: widget.isAr ? 'متابعة إنشاء المسودة' : 'Create draft',
      cancelLabel: widget.isAr ? 'إلغاء' : 'Cancel',
    );
    if (!confirmed || !mounted) return;

    AppHaptics.medium();
    try {
      final contractId = await _net<String>(() async {
        final svc = MarketingFlowService(_sb);
        final id = await svc.createListingContractFromOffer(offerId);
        await svc.ensureListingContractDraftText(
          contractId: id,
          requestId: requestId,
          offerId: offerId,
          isAr: widget.isAr,
        );
        return id;
      }, tag: 'CREATE_CONTRACT_RPC');

      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        widget.isAr
            ? 'تم إنشاء مسودة العقد. أرسلها للمالك من نفس البطاقة.'
            : 'Draft contract created. Send it to the owner from this card.',
      );
      playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
      AppHaptics.light();

      await _sendInAppNotification(
        userId: ownerId,
        titleAr: 'مسودة عقد تسويق',
        titleEn: 'Marketing contract draft',
        bodyAr: 'أنشأ المسوق مسودة عقد. سيصلك العرض للمراجعة بعد إرساله.',
        bodyEn:
            'A marketer created a draft contract. You will get it after they send it.',
        status: ListingStatus.awaitingContract,
        role: 'owner',
        requestId: requestId,
        previewPropertyId: previewPropertyId,
        entityType: 'listing_contract',
        entityId: contractId,
        notificationType: 'contract_created',
        deepRoute: InAppDeepRoutes.listingRequestStatus,
        myAdsSubTab: 2,
      );

      await _loadMarketerBuckets(force: true);
    } catch (e) {
      _showNotification(
        widget.isAr ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _submitMarketingPermit(Map<String, dynamic> row) async {
    final hubKind = (row['_hubKind'] ?? row['_ui_type'] ?? '').toString();
    var permitId =
        (row['listing_permit_id'] ?? row['permit_id'] ?? '').toString().trim();
    if (permitId.isEmpty && hubKind == 'permit') {
      permitId = (row['id'] ?? '').toString().trim();
    }
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.submitPermit,
        requestId: requestId,
        hubKind: 'permit',
      ),
    )) {
      return;
    }
    final ownerId =
        (row['request_owner_id'] ?? row['owner_id'] ?? '').toString().trim();
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();

    try {
      if (permitId.isEmpty) {
        await _net<void>(() async {
          await _sb.from('listing_permits').insert({
            'request_id': requestId,
            'marketer_id': _uid,
            'status': 'submitted',
            'submitted_at': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          });
        }, tag: 'ADD_PERMIT');
      } else {
        await _net<void>(() async {
          await _sb
              .from('listing_permits')
              .update({
                'status': 'submitted',
                'submitted_at': DateTime.now().toIso8601String(),
              })
              .eq('id', permitId)
              .eq('marketer_id', _uid);
        }, tag: 'UPD_PERMIT');
      }

      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        widget.isAr ? 'تم رفع التصريح' : 'Permit submitted',
      );
      playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
      AppHaptics.selection();

      await _sendInAppNotification(
        userId: ownerId,
        titleAr: 'تم رفع التصريح',
        titleEn: 'Permit submitted',
        bodyAr:
            'قام المسوق برفع التصريح. يرجى المراجعة عند الإصدار (خلال 72 ساعة).',
        bodyEn:
            'The marketer submitted permit documents. Review when issued (within 72h).',
        status: ListingStatus.permitSubmitted,
        role: 'owner',
        requestId: requestId,
        previewPropertyId: previewPropertyId,
        entityType: 'listing_permit',
        notificationType: 'permit_submitted',
        deepRoute: InAppDeepRoutes.listingRequestStatus,
      );

      await _loadMarketerBuckets(force: true);
    } catch (e) {
      _showNotification(
        widget.isAr ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _linkRegaAdLicenseWithAuthority(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.linkRegaPermit,
        requestId: requestId,
        hubKind: 'permit',
      ),
    )) {
      return;
    }
    if (!mounted) return;

    Map<String, dynamic>? imported;
    if (kIsWeb) {
      imported = await showRegaElanImportWebDialog(
        context,
        isAr: widget.isAr,
      );
    } else {
      imported = await _pushBody<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => RegaAdLicenseImportPage(
            isAr: widget.isAr,
            embedAppBar: true,
          ),
        ),
      );
    }

    if (imported == null || imported.isEmpty) return;

    final permitNo =
        (imported['rega_ad_license_number'] ?? '').toString().trim();
    if (permitNo.isEmpty) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'تعذر استخراج رقم ترخيص الإعلان. أعد المحاولة أو الصق نص الصفحة كاملاً (على الويب).'
            : 'Could not read the ad license number. Retry or paste full page text on web.',
        isError: true,
      );
      return;
    }

    if (!SaudiAdPermitNumberPatterns.isPlausiblePermitOrAdLicenseNo(permitNo)) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr
            ? 'شكل رقم الترخيص غير مقبول. يُتوقَّع أرقام/حروف لاتينية (6–32) كما في فال/REGA.'
            : 'Permit/license number format looks invalid. Use 6–32 Latin letters/digits (FAL/REGA style).',
        isError: true,
      );
      return;
    }

    try {
      final flow = MarketingFlowService(_sb);
      final uid = _sb.auth.currentUser?.id ?? '';

      final payload = Map<String, dynamic>.from(imported);
      payload['source'] = 'rega_elan_details_import_v1';
      payload['imported_at'] = DateTime.now().toUtc().toIso8601String();

      final falDigits = (payload['fal_broker_license_number'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\D'), '');
      if (falDigits.length == 10) {
        try {
          final v = await FalLicenseService(_sb).verify(falDigits);
          payload['fal_license_verify'] = {
            'verified_at': DateTime.now().toUtc().toIso8601String(),
            'valid': v.valid,
            'status': v.status,
            'source': v.source,
            'license_no': v.licenseNo ?? falDigits,
            'end_date': v.endDateIso,
            'broker_name': v.brokerName,
          };
        } catch (_) {}
      }

      final qrUrl = (payload.remove('ad_qr_image_url') ?? '').toString().trim();
      if (qrUrl.isNotEmpty && uid.isNotEmpty) {
        try {
          final resp = await http.get(
            Uri.parse(qrUrl),
            headers: kIsWeb
                ? const <String, String>{}
                : const {
                    'User-Agent': 'Mozilla/5.0 (compatible; AqarUser/1.0)',
                  },
          );
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            final path =
                'listing-permits/$requestId/${uid}_${const Uuid().v4()}.jpg';
            await _sb.storage.from('property-images').uploadBinary(
                  path,
                  resp.bodyBytes,
                  fileOptions: const FileOptions(
                    upsert: false,
                    contentType: 'image/jpeg',
                  ),
                );
            payload['ad_qr_storage_path'] = path;
          }
        } catch (_) {}
      }

      await flow.createOrUpdateListingPermit(
        requestId: requestId,
        permitNo: permitNo,
        authorityName: 'REGA',
        licenseNo: (payload['fal_broker_license_number'] ?? '').toString(),
        notes: (payload['notes'] ?? 'rega_portal_import').toString(),
        payload: payload,
        expiresAt: null,
      );
      await flow.syncPropertyMarketingLicenseSnapshot(
        requestId: requestId,
        permitPayload: payload,
      );

      // أتمتة النشر بعد ربط REGA الصحيح: تنقل الإعلان مباشرة إلى «منشور/محجوز»
      // ويظهر في الرئيسية. تتطلّب أن يكون المستخدم هو المسوّق المختار وأن
      // بيانات التصريح مكتملة (permit_no/authority_name/license_no).
      var autoPublished = false;
      try {
        await _sb.rpc(
          'marketer_finalize_rega_permit_and_publish',
          params: {'p_request_id': requestId},
        );
        autoPublished = true;
      } catch (_) {
        // ليست خطأً مُعرَّضاً للمستخدم — يعني الانتقال سيتم يدوياً (مالك أو زر «نشر»).
      }

      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        autoPublished
            ? (widget.isAr
                ? 'تم ربط الترخيص ونشر الإعلان تلقائياً في الرئيسية.'
                : 'License linked and listing auto-published to home.')
            : (widget.isAr
                ? 'تم ربط بيانات ترخيص الإعلان مع الهيئة وحفظها في الإعلان.'
                : 'REGA ad license data linked and saved to the listing.'),
      );
      await _loadMarketerBuckets(force: true);
      await _loadMineAndOffers(force: true);
    } catch (e) {
      _showNotification(
        widget.isAr ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<String> _marketerNationalIdPrefillDigits() async {
    String pickFromRaw(String raw) {
      final digits = normalizeWesternDigits(raw).replaceAll(RegExp(r'\D'), '');
      if (digits.length == 10 &&
          (digits.startsWith('1') || digits.startsWith('2'))) {
        return digits;
      }
      return '';
    }

    final uid = (_sb.auth.currentUser?.id ?? '').trim();
    if (uid.isNotEmpty) {
      try {
        final prof = await UsersProfilesSafeSelect.fetchProfileById(
          _sb,
          uid,
          columnAttempts: UsersProfilesSafeSelect.nationalIdColumnAttempts,
        );
        for (final key in const [
          'unified_national_number',
          'national_id',
          'username',
        ]) {
          final v = pickFromRaw((prof?[key] ?? '').toString());
          if (v.isNotEmpty) return v;
        }
      } catch (_) {}
    }

    final meta = _sb.auth.currentUser?.userMetadata;
    if (meta != null) {
      for (final key in const ['username', 'national_id', 'unified_national']) {
        final v = pickFromRaw((meta[key] ?? '').toString());
        if (v.isNotEmpty) return v;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final v = pickFromRaw(prefs.getString('username') ?? '');
      if (v.isNotEmpty) return v;
    } catch (_) {}

    return '';
  }

  /// نافذة «نشر الإعلان العقاري»: تستلم رقم ترخيص الإعلان من الهيئة العامة
  /// للعقار (REGA) ورقم الهوية الوطنية للوسيط (مُعبّأ تلقائياً من ملف المستخدم
  /// `users_profiles.unified_national_number`). الأرقام العربية والفارسية تتحوّل
  /// إلى أرقام إنجليزية فوراً عبر [_LatinDigitsFormatter].
  ///
  /// تدفّق التشغيل:
  /// 1) المستخدم يفتح النافذة من زر «نشر الإعلان العقاري» في «صفحتي → التصريح 72 ساعة».
  /// 2) عند اكتمال الحقلين (طول الترخيص ≥ 6 ومطابق لنمط REGA/فال، والهوية 10 أرقام)
  ///    يتفعّل زر «تحقّق».
  /// 3) في مرحلة التطوير الحالية: التحقق داخلي فقط — لا نتصل بـ REGA خارجياً.
  ///    عند المطابقة يختفي زر «تحقّق» ويظهر «نشر».
  /// 4) عند الضغط على «نشر» نُحفظ بيانات التصريح كحدّ أدنى ثم نستدعي
  ///    [MarketingFlowService.publishListingDispatch] لنقل الإعلان فعلياً إلى
  ///    الرئيسية ليظهر لكل المستخدمين بمن فيهم الضيوف.
  Future<void> _showPublishMarketingListingDialog(
    Map<String, dynamic> row,
  ) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    if (!mounted) return;

    final ar = widget.isAr;
    final publishResume = MarketingSubscriptionResumeIntent(
      kind: MarketingSubscriptionResumeKind.publishListing,
      requestId: requestId,
      hubKind: 'permit',
    );

    final prefillNid = await _marketerNationalIdPrefillDigits();

    if (!mounted) return;

    Future<void> presentPublishUi() async {
      final dialog = _PublishMarketingListingDialog(
        isAr: ar,
        initialNationalId: prefillNid,
        regaLicensePrefix:
            AppRoleHelper.isOrgEntity(_accountType) ? '72' : '71',
        resolveNationalIdIfEmpty:
            prefillNid.isEmpty ? _marketerNationalIdPrefillDigits : null,
        onPublish: (regaLicense, brokerNid) async {
          if (!await _ensureMarketingSubscriptionForPaidWorkflow(
            publishResume,
          )) {
            return;
          }
          if (!mounted) return;
          try {
            await _upsertMarketingPermitForPublish(
              requestId: requestId,
              regaLicense: regaLicense,
              brokerNid: brokerNid,
            );
            await _ensureRequestPermitStageBeforePublish(requestId);
            await _finalizeMarketerRegaPublish(requestId);
            if (!mounted) return;
            _showNotification(
              ar ? 'تم' : 'Done',
              ListingWorkflowCopy.snackPublishedListingSuccess(ar),
            );
            await _refreshAfterListingPublished();
          } catch (e) {
            if (!mounted) return;
            final msg = e.toString().toLowerCase();
            final body = msg.contains('permit_not_approved')
                ? ListingWorkflowCopy.errCannotPublishBeforePermit(ar)
                : msg.contains('permit_rega_package_incomplete') ||
                        msg.contains('permit_data_incomplete')
                    ? ListingWorkflowCopy.errRegaPackageIncomplete(ar)
                    : msg.contains('invalid_request_stage')
                        ? (MarketingWorkflowUiConfig.contractsSigningEnabled
                            ? (ar
                                ? 'لا يمكن النشر الآن: الطلب ليس في مرحلة التصريح. تأكّد أن العقد موقّع من الطرفين.'
                                : 'Cannot publish: request is not in permit stage. Make sure contract is signed by both parties.')
                            : (ar
                                ? 'لا يمكن النشر الآن: حدّث الصفحة ثم أعد المحاولة من تبويب إصدار التصريح.'
                                : 'Cannot publish now. Refresh and retry from the permit tab.'))
                        : msg.contains('contract_not_found')
                            ? (MarketingWorkflowUiConfig.contractsSigningEnabled
                                ? (ar
                                    ? 'تعذّر النشر: لم يُربط عقد بالطلب. طبّق تحديث قاعدة البيانات ثم أعد المحاولة، أو تواصل مع الدعم.'
                                    : 'Publish failed: no contract linked to this request. Apply the latest database update and try again.')
                                : (ar
                                    ? 'تعذّر إكمال النشر تلقائياً. اسحب للتحديث ثم أعد المحاولة.'
                                    : 'Could not finish publish automatically. Pull to refresh and try again.'))
                            : e.toString();
            _showNotification(
              ar ? 'خطأ' : 'Error',
              body,
              isError: true,
            );
            rethrow;
          }
        },
      );
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: bottomInset),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
                ),
                child: dialog,
              ),
            ),
          );
        },
      );
    }

    await presentPublishUi();
  }

  Future<void> _ensureSignedContractForPublishRpc(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return;
    try {
      await _sb.rpc(
        'ensure_signed_listing_contract_for_publish',
        params: {'p_request_id': id},
      );
    } catch (_) {
      // RPC قد لا يكون مُطبَّقاً بعد على Supabase — يُعالَج في migration.
    }
  }

  Future<void> _finalizeMarketerRegaPublish(String requestId) async {
    final contractId = await _sb
        .from('listing_requests')
        .select('contract_id')
        .eq('id', requestId)
        .maybeSingle();
    final rowContractId = (contractId?['contract_id'] ?? '').toString().trim();

    await _ensureSignedContractForPublishRpc(requestId);

    try {
      await _sb.rpc(
        'marketer_finalize_rega_permit_and_publish',
        params: {'p_request_id': requestId},
      );
      return;
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('contract_not_found')) {
        await _ensureSignedContractForPublishRpc(requestId);
        await _sb.rpc(
          'marketer_finalize_rega_permit_and_publish',
          params: {'p_request_id': requestId},
        );
        return;
      }
      if (m.contains('does not exist') ||
          (m.contains('function') &&
              m.contains('marketer_finalize_rega_permit_and_publish'))) {
        await MarketingFlowService(_sb).publishListingDispatch(
          requestId: requestId,
          preferPermitPath: true,
          contractId: rowContractId.isEmpty ? null : rowContractId,
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _refreshAfterListingPublished() async {
    await _refreshMyPageHubAfterAction(
      marketerTabIndex: 4,
      notifyHub: false,
    );
    await Future.wait([
      _loadMarketHomeRequests(force: true),
      if (!PropertiesHomeFeedService.isCircuitOpen) _loadHome(force: true),
    ]);
  }

  /// قبل النشر — تأكّد من وجود صف تصريح للمسوّق على هذا الطلب مع رقم REGA،
  /// أو حدّثه إن كان موجوداً. يضع `status='submitted'` ليُعتمد لاحقاً من
  /// [marketer_finalize_rega_permit_and_publish].
  Future<void> _upsertMarketingPermitForPublish({
    required String requestId,
    required String regaLicense,
    required String brokerNid,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final lic = regaLicense.trim();
    if (lic.isEmpty) return;

    try {
      await _sb.rpc(
        'upsert_listing_permit_for_publish',
        params: {
          'p_request_id': requestId,
          'p_permit_no': lic,
          'p_broker_nid': brokerNid,
        },
      );
      return;
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (!m.contains('does not exist') &&
          !(m.contains('function') &&
              m.contains('upsert_listing_permit_for_publish'))) {
        rethrow;
      }
    }

    final payload = <String, dynamic>{
      'permit_no': lic,
      'license_no': lic,
      'authority_name': 'REGA',
      'status': 'submitted',
      'submitted_at': DateTime.now().toIso8601String(),
      'notes': brokerNid.isEmpty ? null : 'broker_nid:$brokerNid',
    };

    Future<void> writePermit(Map<String, dynamic> body) async {
      final existingRows = await _sb
          .from('listing_permits')
          .select('id')
          .eq('request_id', requestId)
          .eq('marketer_id', uid)
          .neq('status', 'rejected')
          .order('created_at', ascending: false);

      final list = (existingRows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (list.isNotEmpty) {
        for (final row in list) {
          final pid = (row['id'] ?? '').toString();
          if (pid.isEmpty) continue;
          await _sb
              .from('listing_permits')
              .update(body)
              .eq('id', pid)
              .eq('marketer_id', uid);
        }
        return;
      }

      await _sb.from('listing_permits').insert({
        ...body,
        'request_id': requestId,
        'marketer_id': uid,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // بعد ترحيل broker_nid نكتبه مباشرة؛ وإن غاب العمود نكتفي بـ notes.
    try {
      await writePermit({
        ...payload,
        if (brokerNid.isNotEmpty) 'broker_nid': brokerNid,
      });
      return;
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (!m.contains('broker_nid') && !m.contains('42703')) rethrow;
    }

    try {
      await writePermit(payload);
      return;
    } on PostgrestException catch (e) {
      if ((e.code ?? '').trim() != '23505') rethrow;
      final retry = await _sb
          .from('listing_permits')
          .select('id')
          .eq('request_id', requestId)
          .eq('marketer_id', uid)
          .neq('status', 'rejected')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final pid = (retry?['id'] ?? '').toString();
      if (pid.isEmpty) rethrow;
      await _sb
          .from('listing_permits')
          .update(payload)
          .eq('id', pid)
          .eq('marketer_id', uid);
    }
  }

  /// إذا كان الطلب ما زال في مرحلة `contract_signed` أو ما قبلها، حرّكه إلى
  /// `permit_pending` حتى لا يُرفض `publish_property_after_permit` بـ
  /// `invalid_request_stage`. لا يتدخّل إن كان منشوراً بالفعل.
  ///
  /// استراتيجية مزدوجة:
  ///  1) تجريب الـRPC `marketer_set_request_to_permit_pending` (SECURITY DEFINER)
  ///     لتجاوز قيود RLS التي تمنع المسوّق من تحديث `workflow_stage` مباشرة.
  ///  2) عند عدم وجود الـRPC (نسخ DB قديمة) نسقط على UPDATE مباشر كحل احتياطي.
  Future<void> _ensureRequestPermitStageBeforePublish(String requestId) async {
    try {
      final req = await _sb
          .from('listing_requests')
          .select('workflow_stage')
          .eq('id', requestId)
          .maybeSingle();
      final stage =
          (req?['workflow_stage'] ?? '').toString().trim().toLowerCase();
      if (stage == 'published' ||
          stage == 'permit_pending' ||
          stage == 'awaiting_permits' ||
          stage == 'pending_permits' ||
          stage == 'permit_issued') {
        return;
      }
      try {
        await _sb.rpc(
          'marketer_set_request_to_permit_pending',
          params: {'p_request_id': requestId},
        );
        return;
      } catch (e) {
        final m = e.toString().toLowerCase();
        if (m.contains('does not exist') ||
            m.contains('not found') ||
            (m.contains('function') &&
                m.contains('marketer_set_request_to_permit_pending'))) {
          await _sb
              .from('listing_requests')
              .update({'workflow_stage': 'permit_pending'}).eq('id', requestId);
          return;
        }
        rethrow;
      }
    } catch (_) {}
  }

  Future<void> _publishMarketingListingFromRow(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.publishListing,
        requestId: requestId,
        hubKind: 'permit',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: ListingWorkflowCopy.btnPublishAd(widget.isAr),
      message: widget.isAr
          ? 'سيتم نشر الإعلان على الرئيسية للجمهور. هل تؤكد؟'
          : 'This will publish the listing on the public home feed. Confirm?',
      confirmLabel: widget.isAr ? 'نشر' : 'Publish',
      cancelLabel: widget.isAr ? 'إلغاء' : 'Cancel',
    );
    if (!ok || !mounted) return;

    try {
      final contractId = (row['contract_id'] ?? '').toString().trim();
      await MarketingFlowService(_sb).publishListingDispatch(
        requestId: requestId,
        preferPermitPath: true,
        contractId: contractId.isEmpty ? null : contractId,
      );
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        ListingWorkflowCopy.snackPublishedListingSuccess(widget.isAr),
      );
      await _loadMarketerBuckets(force: true);
      await _loadMineAndOffers(force: true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final body = msg.contains('permit_not_approved')
          ? ListingWorkflowCopy.errCannotPublishBeforePermit(widget.isAr)
          : msg.contains('permit_rega_package_incomplete')
              ? ListingWorkflowCopy.errRegaPackageIncomplete(widget.isAr)
              : e.toString();
      _showNotification(widget.isAr ? 'خطأ' : 'Error', body, isError: true);
    }
  }

  /// بلاغ عدم مطابقة بيانات ترخيص الإعلان مع فال/REGA (يُحسب في الخادم؛ 3 بلاغات تُنهي عقداً غير موقّع).
  Future<void> _reportRegaLicenseMismatch(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    if (!await _ensureMarketingSubscriptionForPaidWorkflow(
      MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.reportRegaMismatch,
        requestId: requestId,
        hubKind: 'permit',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    final ar = widget.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'بلاغ عدم مطابقة' : 'Report mismatch'),
        content: Text(
          ar
              ? 'سجّل بلاغاً رسمياً إذا لم تتطابق بيانات ترخيص الإعلان مع رخصة فال أو بيانات الهيئة. بعد ثلاث بلاغات مؤكّدة يُفسَخ العقد غير الموقّع تلقائياً (حسب الترحيل على الخادم).'
              : 'Record an official mismatch. After three confirmed reports, unsigned contracts may be voided (server policy).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'تسجيل البلاغ' : 'Submit report'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await MarketingFlowService(_sb).reportRegaLicenseMismatch(
        requestId,
      );
      final voided = res['contract_voided'] == true;
      final n = res['attempts'];
      _showNotification(
        ar ? 'تم' : 'Done',
        ar
            ? (voided
                ? 'تم إنهاء العقد وفق سياسة عدم المطابقة.'
                : 'سُجّل البلاغ${n != null ? ' (محاولة $n)' : ''}.')
            : (voided
                ? 'Contract ended per mismatch policy.'
                : 'Report recorded${n != null ? ' (attempt $n)' : ''}.'),
      );
      await _loadMarketerBuckets(force: true);
    } catch (e) {
      _showNotification(
        ar ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _openMarketingPreviewProperty(Map<String, dynamic> row) async {
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();
    final requestId = _marketingRequestIdFromRow(row);
    final inviteId = (row['id'] ?? '').toString().trim();
    final type = (row['_hubKind'] ?? row['_ui_type'] ?? '').toString().trim();

    if (previewPropertyId.isEmpty) {
      await _openListingByRequestFallback(row);
      return;
    }

    Property? p = _propertyCache[previewPropertyId] ??
        _propertyFromLocalCaches(previewPropertyId);

    p ??= await _fetchPropertyById(previewPropertyId);

    if (!mounted) return;

    if (p != null) {
      _applyUpdatedPropertyToCollections(p);
      final allowOffer = requestId.isNotEmpty &&
          (type == 'invite' || _marketerOfferRetryAllowedForRow(row));
      await _openDetails(
        p,
        marketingRequestId: requestId.isEmpty ? null : requestId,
        marketingInviteId:
            (type == 'invite' && inviteId.isNotEmpty) ? inviteId : null,
        allowMarketingOffer: allowOffer,
        marketerHubPhase: const {
          'invite',
          'offer',
          'contract',
          'permit',
        }.contains(type)
            ? type
            : null,
      );
      return;
    }

    await _openListingByRequestFallback(row);
  }

  Future<void> _openContractPdfUrl(Map<String, dynamic> row) async {
    final raw = (row['contract_pdf_url'] ?? '').toString().trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      _showNotification(
        widget.isAr ? 'رابط غير صالح' : 'Invalid link',
        raw,
        isError: true,
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showNotification(
        widget.isAr ? 'تعذّر الفتح' : 'Could not open',
        widget.isAr
            ? 'جرّب نسخ الرابط من إدارة الملفات.'
            : 'Try opening from file manager.',
        isError: true,
      );
    }
  }

  bool _marketerOfferAcceptedByOwner(Map<String, dynamic> r) {
    final offerId = (r['id'] ?? '').toString().trim();
    final selected = (r['selected_offer_id'] ?? '').toString().trim();
    if (selected.isNotEmpty && offerId.isNotEmpty && selected == offerId) {
      return true;
    }
    final st = (r['status'] ?? '').toString().toLowerCase();
    return st == 'owner_accepted' ||
        st == 'selected' ||
        st == 'converted_to_contract';
  }

  bool _marketerContractFlowUnlocked(Map<String, dynamic> r) {
    final selMk =
        (r['selected_marketer_id'] ?? r['request_selected_marketer_id'] ?? '')
            .toString()
            .trim();
    // المصدر الأساسي: المسوّق المختار — حتى لو غاب selected_offer_id من الصف المدمج.
    if (selMk.isNotEmpty) return selMk == _uid;

    final selOffer = (r['selected_offer_id'] ?? '').toString().trim();
    if (selOffer.isEmpty) return false;
    final rowMk = (r['marketer_id'] ?? '').toString().trim();
    return rowMk.isEmpty || rowMk == _uid;
  }

  /// أساس سعر العقار لحساب أتعاب التسويق (نسبة [MarketingOfferFee] من المجموع بعد ضريبة 5٪ على العقار).
  double? _propertyBaseSarForMarketingFee(Map<String, dynamic> r) {
    final pp = (r['preview_price'] as num?)?.toDouble();
    if (pp != null && pp > 0) return pp;
    final rq = (r['request_price'] as num?)?.toDouble();
    if (rq != null && rq > 0) return rq;
    final op = r['price'];
    if (op is num && op > 0) return op.toDouble();
    return null;
  }

  String _marketingOfferFeeBreakdownText(double propertyBaseSar,
      {required bool ar}) {
    if (propertyBaseSar <= 0) return '';
    final fmt = NumberFormat('#,##0.##', ar ? 'ar' : 'en');
    final pv = MarketingOfferFee.propertyVatAmount(propertyBaseSar);
    final sub = MarketingOfferFee.propertySubtotalWithVat(propertyBaseSar);
    final fee = MarketingOfferFee.marketingFeeAmount(propertyBaseSar);
    final t = MarketingOfferFee.totalDue(propertyBaseSar);
    final pct = MarketingOfferFee.commissionPercentLabel(isAr: ar);
    if (ar) {
      final riyal = AppMoney.saudiRiyalSignUnicode;
      return 'قيمة العقار: ${fmt.format(propertyBaseSar)} $riyal\n'
          'ضريبة 5٪ على العقار: ${fmt.format(pv)} $riyal\n'
          'المجموع شامل ضريبة القيمة المضافة 5٪: ${fmt.format(sub)} $riyal\n'
          'نسبة التسويق $pct من المجموع الإجمالي المستحق: ${fmt.format(fee)} $riyal\n'
          'الإجمالي المستحق: ${fmt.format(t)} $riyal';
    }
    return 'Property value: ${fmt.format(propertyBaseSar)} SAR\n'
        '5% VAT on property: ${fmt.format(pv)} SAR\n'
        'Subtotal incl. 5% VAT: ${fmt.format(sub)} SAR\n'
        'Marketing rate $pct of total due: ${fmt.format(fee)} SAR\n'
        'Total due: ${fmt.format(t)} SAR';
  }

  Future<void> _openMarketerMarketOfferHub(Map<String, dynamic> row) async {
    final urls = _effectiveImageUrlsForOwnerRequestRow(row);
    final title = _mkRowTitle(row);
    final loc = _marketingLocationText(row);
    final owner = _marketingOwnerName(row);
    final phone = _marketingOwnerPhone(row);
    var rawCode = (row['listing_request_public_code'] ?? '').toString().trim();
    if (rawCode.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(rawCode)) {
      rawCode = (row['preview_listing_public_code'] ??
              row['listing_public_code'] ??
              '')
          .toString()
          .trim();
    }
    final code =
        (rawCode.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(rawCode))
            ? DisplayIds.tenDigit(rawCode)
            : '';
    final base = _propertyBaseSarForMarketingFee(row) ?? 0;
    final areaRaw = row['preview_area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;

    final wfCtx = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(row),
    );
    final stageLabel = widget.isAr ? wfCtx.statusLabelAr : wfCtx.statusLabelEn;
    final createdRaw = (row['created_at'] ?? '').toString();
    final createdDt = DateTime.tryParse(createdRaw);
    final submittedAt = createdDt == null
        ? ''
        : ListingDateDisplay.formatCardDateTime(
            createdDt.toLocal(),
            isAr: widget.isAr,
          );
    final round = (row['marketing_round'] as num?)?.toInt() ?? 1;
    final requestId = _marketingRequestIdFromRow(row);

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => MarketerMarketOfferHubPage(
          isAr: widget.isAr,
          heroImageUrls: urls,
          title: title,
          locationLine: loc,
          ownerDisplayName: owner,
          ownerPhoneRaw: phone,
          listingNoTenDigit: code,
          priceSar: base,
          areaM2: area,
          hideOwnerContactActions: !_marketerMaySeeOwnerPhone(row),
          workflowStageLabel: stageLabel,
          requestSubmittedAt: submittedAt,
          marketingRound: round > 1 ? round : null,
          onOpenTracking: requestId.isEmpty
              ? null
              : () {
                  showListingMarketingTrackingSheet(
                    context: ctx,
                    sb: _sb,
                    requestId: requestId,
                    isAr: widget.isAr,
                    viewerUserId: _uid,
                  );
                },
          onSubmitOffer: () async {
            Navigator.of(ctx).pop();
            await _showMarketingOfferSheetForRow(row);
          },
        ),
      ),
    );
  }

  Future<void> _showMarketingOfferSheetForRow(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    final hubKind =
        (row['_hubKind'] ?? row['_ui_type'] ?? '').toString().trim();
    final inviteIdRaw = (row['id'] ?? '').toString().trim();
    if (!_isGuest && _uid.isNotEmpty && _isMarketingAccountType) {
      final resume = MarketingSubscriptionResumeIntent(
        kind: MarketingSubscriptionResumeKind.submitOffer,
        requestId: requestId,
        inviteId: hubKind == 'invite' ? inviteIdRaw : null,
        hubKind: hubKind,
      );
      if (!await _ensureMarketingSubscriptionForPaidWorkflow(resume)) {
        return;
      }
    }
    if (!mounted) return;
    final base = _propertyBaseSarForMarketingFee(row);
    await showMarketingOfferSubmitSheet(
      context,
      requestId: requestId,
      inviteId: hubKind == 'invite' ? inviteIdRaw : null,
      isAr: widget.isAr,
      propertyBaseSarHint: (base != null && base > 0) ? base : null,
      onAfterSubmit: () async {
        if (widget.isAr) {
          await AppSoundCoordinator.playUiEffect(
            assetPath: 'sounds/in_app_chime.wav',
          );
        }
        await _loadMarketerBuckets(force: true);
      },
    );
  }

  void _showOwnerRequestActivityDialog(Map<String, dynamic> row) {
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final uid = _uid.trim();
    if (uid.isEmpty || uid == 'guest') {
      _showLoginDialog();
      return;
    }
    unawaited(
      showListingMarketingTrackingSheet(
        context: context,
        sb: _sb,
        requestId: id,
        isAr: widget.isAr,
        viewerUserId: uid,
      ),
    );
  }

  void _showMarketerOfferTrackDialog(Map<String, dynamic> r) {
    final rid = _marketingRequestIdFromRow(r);
    if (rid.isEmpty) return;
    final uid = _uid.trim();
    if (uid.isEmpty || uid == 'guest') {
      _showLoginDialog();
      return;
    }
    unawaited(
      showListingMarketingTrackingSheet(
        context: context,
        sb: _sb,
        requestId: rid,
        isAr: widget.isAr,
        viewerUserId: uid,
      ),
    );
  }

  /// من بطاقات تسويق المالك في «صفحتي»: مسار الحالة/التعاقد — وليس تفاصيل عقار عامة.
  Future<void> _openOwnerListingRequestFromRow(
    Map<String, dynamic> row, {
    required String requestStatusId,
  }) async {
    final rid = _marketingRequestIdFromRow(row).isNotEmpty
        ? _marketingRequestIdFromRow(row)
        : requestStatusId.trim();
    if (rid.isEmpty) return;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ListingRequestStatusPage(
          requestId: rid,
          lang: widget.isAr ? 'ar' : 'en',
        ),
      ),
    );
  }

  Future<void> _openListingByRequestFallback(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) {
      _showNotification(
        widget.isAr ? 'تنبيه' : 'Notice',
        widget.isAr ? 'لا يوجد إعلان مرتبط بعد' : 'No linked listing yet',
        isError: true,
      );
      return;
    }
    try {
      final data = await _sb
          .from('properties')
          .select('*')
          .eq('request_id', requestId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) {
        await _openMarketerInviteDetails(row);
        return;
      }
      final p = Property.fromJson(Map<String, dynamic>.from(data));
      final hk = (row['_hubKind'] ?? row['_ui_type'] ?? '').toString().trim();
      final allowOffer =
          hk == 'invite' || _marketerOfferRetryAllowedForRow(row);
      await _openDetails(
        p,
        marketingRequestId: requestId,
        marketingInviteId:
            hk == 'invite' ? (row['id'] ?? '').toString().trim() : null,
        allowMarketingOffer: allowOffer,
        marketerHubPhase:
            const {'invite', 'offer', 'contract'}.contains(hk) ? hk : null,
      );
    } catch (_) {
      await _openMarketerInviteDetails(row);
    }
  }

  Widget _buildMarketingPreviewImage(
    List<String> imageUrls, {
    required String type,
    int? views,
    String? videoStoragePath,
    bool coverPrefersVideo = false,

    /// أيقونة تتبّع أعلى الصورة (بداية الاتجاه) — يُفضّل تمرير [onImageTrackingTap].
    bool showTrackingMark = false,
    VoidCallback? onImageTrackingTap,

    /// أيقونة عين أعلى الصورة (نهاية الاتجاه) لحالة «تمت المشاهدة» في دعوات السوق.
    bool showInviteSeenEye = false,
    VoidCallback? onSeenEyeTap,
    bool showReofferBadge = false,
    String? reofferBadgeLabel,
    String? reofferReason,
    VoidCallback? onReofferHelpTap,
  }) {
    final vid = (videoStoragePath ?? '').trim();
    final showVideoLead =
        vid.isNotEmpty && (imageUrls.isEmpty || coverPrefersVideo);
    if (imageUrls.isNotEmpty || showVideoLead) {
      final showViewsChip = views != null && views >= 0 && !showInviteSeenEye;
      return Stack(
        fit: StackFit.expand,
        children: [
          _PropertyImage(
            urls: imageUrls,
            fit: BoxFit.cover,
            videoPathOrUrl: showVideoLead ? vid : null,
            isAr: widget.isAr,
            allowInlineVideo: !kIsWeb,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          if (showTrackingMark && onImageTrackingTap != null)
            PositionedDirectional(
              top: 6,
              start: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip:
                      widget.isAr ? 'تتبّع الطلب / العرض' : 'Track request',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: Icon(
                    Icons.explore_outlined,
                    size: 18,
                    color: Colors.white.withOpacity(0.95),
                  ),
                  onPressed: onImageTrackingTap,
                ),
              ),
            ),
          if (showInviteSeenEye)
            PositionedDirectional(
              top: 6,
              end: 6,
              child: Material(
                color: const Color(0xFFFFC107).withOpacity(0.92),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: 1,
                child: onSeenEyeTap != null
                    ? IconButton(
                        tooltip: widget.isAr
                            ? 'اضغط لعرض عدد المشاهدات'
                            : 'Tap to see view count',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: Icon(
                          Icons.visibility_outlined,
                          size: 18,
                          color: Colors.brown.shade900,
                        ),
                        onPressed: onSeenEyeTap,
                      )
                    : Tooltip(
                        message: widget.isAr ? 'تمت المشاهدة' : 'Seen',
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: Colors.brown.shade900,
                          ),
                        ),
                      ),
              ),
            ),
          if (showReofferBadge)
            PositionedDirectional(
              bottom: 8,
              start: 8,
              child: Tooltip(
                message: (reofferReason ?? '').trim().isEmpty
                    ? (widget.isAr
                        ? 'معاد للسوق العقاري'
                        : 'Returned to market')
                    : reofferReason!.trim(),
                waitDuration: const Duration(milliseconds: 220),
                child: Material(
                  color: const Color(0xFF2E7D32).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onReofferHelpTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.replay_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (reofferBadgeLabel ?? '').trim().isNotEmpty
                                ? reofferBadgeLabel!.trim()
                                : (widget.isAr ? 'معادة' : 'Relisted'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          if (onReofferHelpTap != null ||
                              (reofferReason ?? '').trim().isNotEmpty) ...[
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.help_outline,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showViewsChip)
            PositionedDirectional(
              bottom: 8,
              end: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$views',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return const MarketRequestLeadThumb(
      storagePath: null,
      width: double.infinity,
      height: double.infinity,
      borderRadius: 0,
    );
  }

  /// بعد النشر (أو حجز/توقف): إظهار فال ورقم الهيئة على البطاقة وإخفاء هوية المالك كسطر «معلن».
  bool _ownerHubListingShowsRegulatory(Property p) {
    switch (p.effectiveWorkflowStage) {
      case ListingWorkflowStage.published:
      case ListingWorkflowStage.reserved:
      case ListingWorkflowStage.inactive72h:
        return true;
      default:
        return false;
    }
  }

  /// شريط مراحل التسويق + أزرار واضحة + سبب الرفض داخل بطاقة «إعلاناتي المنشورة».
  Future<void> _showOwnerHubListingFullSpecs(Property p) async {
    final ar = widget.isAr;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SizedBox(
          height: h * 0.88,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ar ? 'بيانات الإعلان كاملة' : 'Full listing data',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openDetails(p);
                      },
                      child: Text(ar ? 'صفحة كاملة' : 'Full page'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    ListingFormattedSpecPanel(property: p, isAr: ar),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// كل بيانات طلب التسويق (صك / مرافق / موقع…) لنقلها للجهات دون مراسلة المعلن.
  Future<void> _showMarketingRequestFullSpecs(Map<String, dynamic> r) async {
    final ar = widget.isAr;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return SizedBox(
          height: h * 0.88,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  ar
                      ? 'بيانات الطلب كاملة للنقل الرسمي'
                      : 'Full request data for official transfer',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    ListingRequestSpecPanel(row: r, isAr: ar),
                    const SizedBox(height: 8),
                    Text(
                      ar
                          ? 'رقم الجوال يظهر فقط بعد موافقة المعلن على مسوّقك.'
                          : 'Phone appears only after the owner approves your marketing.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ownerPublishedListingCardTail(
    BuildContext context,
    Property p,
    AppLocalizations l10n,
  ) {
    final isOwner = !_isGuest && _uid.isNotEmpty && p.ownerId == _uid;
    final stage = p.effectiveWorkflowStage;
    final rejectReason = _ownerRejectionReason(p);
    final cs = Theme.of(context).colorScheme;
    final canEdit =
        isOwner && ListingEditPermissions.ownerMayEditListingBody(p);

    Widget actionsForWidth(double maxW) {
      final narrow = maxW < 420;
      final btns = <Widget>[
        if (canEdit)
          FilledButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: Text(
              widget.isAr ? 'تعديل الإعلان' : 'Edit listing',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                height: 1.15,
              ),
            ),
            onPressed: () => _editProperty(p),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new_rounded, size: 20),
          label: Text(
            widget.isAr
                ? 'كل البيانات (صك/مرافق)'
                : 'Full data (deed/amenities)',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.15,
              fontFamily: 'Cairo',
            ),
          ),
          onPressed: () => _showOwnerHubListingFullSpecs(p),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          ),
        ),
      ];
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < btns.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              btns[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < btns.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: btns[i]),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stage != ListingWorkflowStage.published)
          ListingWorkflowProgressStrip(
            stage: stage,
            compact: false,
            dense: false,
            deadline: p.reservationExpiresAt ?? p.permitDeadlineAt,
            permitSoundContextId: p.id,
          ),
        LayoutBuilder(
          builder: (_, c) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: actionsForWidth(c.maxWidth),
          ),
        ),
        if (rejectReason != null && rejectReason.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 17, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.ownerOfferRejectionReason(rejectReason),
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOwnerPublishedPropertyCard(Property p) {
    final l10n = AppLocalizations.of(context)!;
    final isGuest = _isGuest;
    final uid = _uid.isEmpty ? 'guest' : _uid;
    final isOwner = p.ownerId == uid;
    final allowCart = ListingPermissionsHelper.canAddToCart(
      property: p,
      currentUserId: isGuest ? null : uid,
      isGuest: isGuest,
      showCartNavSlot: _cartReservationFeaturesEnabled,
    );
    final regulatory = _ownerHubListingShowsRegulatory(p);

    return _RealEstateCard(
      property: p,
      isOwner: isOwner,
      isAr: widget.isAr,
      bankColor: _brandPrimary,
      favorite: !isGuest && _isFav(p.id),
      onToggleFav: isGuest ? () => _showLoginDialog() : () => _toggleFav(p.id),
      onOpenDetails: () => _openDetails(p),
      activeCartHoldsCount: _activeReservationHoldCount(p.id),
      isReserved: _isReservedByAnyone(p.id),
      reservedUntil: _reservedUntil(p.id),
      reservedByName: _reservedByName(p.id),
      onAddToCart: (_cartReservationFeaturesEnabled && !isOwner && allowCart)
          ? () async => _addToCart(p)
          : null,
      currentUserId: uid,
      showEditDelete: isOwner,
      onEditProperty:
          isOwner && ListingEditPermissions.ownerMayEditListingBody(p)
              ? () {
                  _editProperty(p);
                }
              : null,
      onDeleteProperty: isOwner ? () => _requestDeleteProperty(p) : null,
      timeAgo: _timeAgo,
      relaxTextTruncation: true,
      canShowCartButton: _cartReservationFeaturesEnabled,
      onViewsPillTap: (ctx) {
        final pubId = (p.publishedByMarketerId ?? '').trim();
        final isPm = uid.isNotEmpty && pubId == uid;
        PropertyViewService.showSheet(
          context: ctx,
          sb: _sb,
          propertyId: p.id,
          viewsCount: p.views,
          isOwner: isOwner,
          isPublishingMarketer: isPm,
          isAr: widget.isAr,
        );
      },
      showListingQuickActions: true,
      onCopyListingWebLink: _copyListingPublicLink,
      onShareListingFromCard: () => _shareListingFromCard(p),
      showRegulatoryIdentityOnCard: regulatory,
      omitMarketingLicenseEntriesOnCard: true,
      suppressPublicOwnerIdentity: regulatory || isOwner,
      showFullOwnerLegalNameOnCard: true,
      ownerHubListingCard: true,
      cardBelowMainRow: _ownerPublishedListingCardTail(context, p, l10n),
    );
  }

  Widget _buildOwnerPublishedPropertiesList({
    required List<Property> items,
    required String emptyText,
  }) {
    if ((_loadingMine || _loadingOwnerRequests) && items.isEmpty) {
      return _buildTabLoadingState(
        title: widget.isAr ? 'جارٍ تحميل إعلاناتي' : 'Loading my listings',
      );
    }

    if (_errorMine != null && items.isEmpty) {
      return _simpleErrorBox(
        title:
            widget.isAr ? 'تعذر تحميل إعلاناتي' : 'Failed to load my listings',
        err: _errorMine!,
        onRetry: () => _loadMineAndOffers(force: true),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return _myAdsHubScrollWrap(
      LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final useGrid = _useGridLayout(context);
          final paddingH = w >= 900 ? 18.0 : 12.0;

          if (!useGrid) {
            return ListView.separated(
              key: ValueKey<String>(
                  'owner_pub_list_${items.length}_${emptyText.hashCode}'),
              padding: EdgeInsets.fromLTRB(paddingH, 12, paddingH, 12),
              physics: _myAdsHubScrollPhysics,
              cacheExtent: _myAdsHubListCacheExtent,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _buildOwnerPublishedPropertyCard(items[i]),
            );
          }

          final cross = _hubPropertyCrossAxisCount(w);
          const spacing = 12.0;
          final rowChildren = <Widget>[];
          for (var start = 0; start < items.length; start += cross) {
            if (rowChildren.isNotEmpty) {
              rowChildren.add(const SizedBox(height: spacing));
            }
            final end =
                start + cross > items.length ? items.length : start + cross;
            rowChildren.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < cross; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      Expanded(
                        child: start + j < end
                            ? _buildOwnerPublishedPropertyCard(items[start + j])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView(
            key: ValueKey<String>(
                'owner_pub_grid_${items.length}_${emptyText.hashCode}'),
            padding: EdgeInsets.fromLTRB(paddingH, 12, paddingH, 12),
            physics: _myAdsHubScrollPhysics,
            children: rowChildren,
          );
        },
      ),
    );
  }

  String _stripTechnicalIdsForDisplay(String s) {
    var t = s.replaceAll(
      RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        caseSensitive: false,
      ),
      ' ',
    );
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return t;
  }

  Widget _buildSimpleRowsList({
    required List<Map<String, dynamic>> rows,
    required String emptyText,
    required String type,
    bool marketerInvitesTabLayout = false,
    bool marketerMyOffersTabLayout = false,
    bool marketerHubUnifiedMarketCard = true,
  }) {
    final useGrid = rows.isNotEmpty && _useGridLayout(context);
    final firstId = rows.isNotEmpty
        ? (rows.first['id'] ?? rows.first['request_id'] ?? '').toString()
        : '';
    final animKey = rows.isEmpty
        ? 'mk_${type}_empty'
        : 'mk_${type}_${useGrid ? 'grid' : 'list'}_${rows.length}_$firstId';

    late final Widget child;
    if (rows.isEmpty) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (!useGrid) {
      child = ListView.separated(
        primary: false,
        padding: EdgeInsets.fromLTRB(
          8,
          4,
          8,
          4 + _marketerHubScrollBottomPadding(context),
        ),
        physics: _myAdsHubScrollPhysics,
        cacheExtent: _myAdsHubListCacheExtent,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final row = rows[i];
          final rowType = (row['_hubKind'] as String?) ?? type;
          return RepaintBoundary(
            child: _buildMarketerRowCard(
              row,
              type: rowType,
              compact: false,
              index: i,
              marketerInvitesTabLayout: marketerInvitesTabLayout,
              marketerMyOffersTabLayout: marketerMyOffersTabLayout,
              marketerHubUnifiedMarketCard: marketerHubUnifiedMarketCard,
            ),
          );
        },
      );
    } else {
      child = LayoutBuilder(
        builder: (context, c) {
          final cross = _hubPropertyCrossAxisCount(c.maxWidth);
          const spacing = 14.0;
          final bottom = 4 + _marketerHubScrollBottomPadding(context);
          final rowWidgets = <Widget>[];
          for (var start = 0; start < rows.length; start += cross) {
            if (rowWidgets.isNotEmpty) {
              rowWidgets.add(const SizedBox(height: spacing));
            }
            final end =
                start + cross > rows.length ? rows.length : start + cross;
            rowWidgets.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < cross; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      Expanded(
                        child: start + j < end
                            ? _buildMarketerRowCard(
                                rows[start + j],
                                type:
                                    (rows[start + j]['_hubKind'] as String?) ??
                                        type,
                                compact: false,
                                index: start + j,
                                marketerInvitesTabLayout:
                                    marketerInvitesTabLayout,
                                marketerMyOffersTabLayout:
                                    marketerMyOffersTabLayout,
                                marketerHubUnifiedMarketCard:
                                    marketerHubUnifiedMarketCard,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(8, 4, 8, bottom),
            physics: _myAdsHubScrollPhysics,
            children: rowWidgets,
          );
        },
      );
    }

    final switchMs =
        (kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)) ? 0 : 280;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: switchMs),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<String>(animKey),
        child: _myAdsHubScrollWrap(child),
      ),
    );
  }

  /// زرّان بعرض شبكي: صفّان على الشاشات الضيقة، وعمودان على العريضة — بدون تداخل.
  Widget _buildMarketerInviteActionsGrid(
    Map<String, dynamic> r, {
    required bool canSubmitOffer,
    required bool canViewDetails,
    String? inviteOfferBlockMessage,
    String? inviteDetailsBlockMessage,
  }) {
    final l10n = AppLocalizations.of(context);
    final detailsLabel = l10n?.marketerBtnPropertyListingDetails ??
        (widget.isAr ? 'تفاصيل الإعلان العقاري' : 'Listing details');
    final ar = widget.isAr;

    Widget offerBtn() {
      final label = widget.isAr ? 'إرسال طلب تسويق' : 'Send marketing request';
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: () {
            if (canSubmitOffer) {
              _showMarketingOfferSheetForRow(r);
              return;
            }
            _showNotification(
              ar ? 'تنبيه' : 'Notice',
              inviteOfferBlockMessage ??
                  (ar
                      ? 'لا يمكن إرسال طلب تسويق لهذه الدعوة حالياً.'
                      : 'You cannot send a marketing request for this invite right now.'),
              isError: false,
            );
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(double.infinity, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    Widget detailsBtn() {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: () {
            if (canViewDetails) {
              unawaited(_openMarketingPreviewProperty(r));
              return;
            }
            _showNotification(
              ar ? 'تنبيه' : 'Notice',
              inviteDetailsBlockMessage ??
                  (ar
                      ? 'لا تتوفر تفاصيل إعلان مرتبطة بعد.'
                      : 'No listing details are available yet.'),
              isError: false,
            );
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(double.infinity, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            detailsLabel,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 380;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: detailsBtn()),
              const SizedBox(width: 10),
              Expanded(child: offerBtn()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            detailsBtn(),
            const SizedBox(height: 10),
            offerBtn(),
          ],
        );
      },
    );
  }

  /// داخل البطاقة الموحّدة للعقد — بدل تكدّس نفس الأزرار في أسفل البطاقة.
  Widget _buildMarketerContractInlineDesk(
    Map<String, dynamic> r,
    ColorScheme cs,
  ) {
    if (!_marketerContractFlowUnlocked(r)) return const SizedBox.shrink();
    final requestId = _marketingRequestIdFromRow(r);
    final previewPropertyId =
        (r['preview_property_id'] ?? '').toString().trim();
    final pdf = (r['contract_pdf_url'] ?? '').toString().trim();
    final ar = widget.isAr;

    Future<void> openTrack() async {
      final uid = _uid.trim();
      if (uid.isEmpty || uid == 'guest') {
        _showLoginDialog();
        return;
      }
      if (requestId.isEmpty) return;
      unawaited(
        showListingMarketingTrackingSheet(
          context: context,
          sb: _sb,
          requestId: requestId,
          isAr: ar,
          viewerUserId: uid,
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (previewPropertyId.isNotEmpty || requestId.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => unawaited(_openMarketingPreviewProperty(r)),
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                label: Text(
                  ar ? 'تفاصيل الإعلان' : 'Listing details',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_showMarketingRequestFullSpecs(r)),
              icon: const Icon(Icons.table_rows_outlined, size: 18),
              label: Text(
                ar ? 'كل البيانات (صك/مرافق)' : 'All data (deed/amenities)',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            // في تبويب «إصدار التصاريح» تظهر أيقونة الدردشة بجوار رقم المالك،
            // فلا نُكرّر زراً عريضاً للدردشة (نتجنّب الازدواج ونُنسّق التباعد).
            if (_canShowMarketerChatIconForRow(r) &&
                !(_marketerInPermit72SubTab &&
                    _canShowMarketerChatIconForRow(r)))
              OutlinedButton.icon(
                onPressed: () => unawaited(_openMarketerChatWithOwnerGated(r)),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text(
                  ar ? 'دردشة مع المالك' : 'Chat with owner',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            if (requestId.isNotEmpty)
              OutlinedButton.icon(
                onPressed: openTrack,
                icon: const Icon(Icons.manage_search_outlined, size: 18),
                label: Text(
                  ar ? 'تتبّع الطلب' : 'Track request',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            // PDF اختياري بعد التوقيع فقط — زر واحد هادئ، بلا شارة ولا دمج مع التتبّع.
            if (MarketingWorkflowUiConfig.contractsSigningEnabled &&
                pdf.isNotEmpty &&
                _marketerRowContractFullySigned(r))
              OutlinedButton.icon(
                onPressed: () => unawaited(_openContractPdfUrl(r)),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(
                  ar ? 'عقد PDF' : 'Contract PDF',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _marketerRowContractFullySigned(Map<String, dynamic> r) {
    final cs = (r['contract_status'] ?? r['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (cs == 'signed') return true;
    final st = _workflowStageFromMarketerRow(r);
    return st == ListingWorkflowStage.contractSigned ||
        st == ListingWorkflowStage.permitPending ||
        st == ListingWorkflowStage.permitIssued;
  }

  Widget _buildMarketerRowActionFooter(
    Map<String, dynamic> r, {
    required String type,
    required String statusRaw,
    required String requestId,
    required String previewPropertyId,
    required bool canSubmitOffer,
    String? inviteOfferBlockMessage,
    String? inviteDetailsBlockMessage,
    bool marketerInvitesTabLayout = false,
    bool marketerMyOffersTabLayout = false,

    /// تبويب «السوق العقاري»: زر تقديم عرض فقط — المراسلة داخل نافذة العرض الكاملة.
    bool marketerInvitesSingleActionFooter = false,

    /// أزرار تفاصيل/دردشة/تتبّع العقد داخل البطاقة الموحّدة بدل أسفلها.
    bool contractNavButtonsInlined = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final actions = <Widget>[];
    // ملاحظة: زر «دردشة مع المالك» نُقل إلى أيقونة بجوار رقم الجوال داخل البطاقة
    // (راجع `_canShowMarketerChatIconForRow` و`_buildMarketerInviteUnifiedListCard`).

    if (marketerMyOffersTabLayout && type == 'offer') {
      final st = (r['status'] ?? '').toString().toLowerCase();
      if (st != 'withdrawn') {
        actions.add(
          FilledButton.icon(
            onPressed: () => _showMarketerOfferTrackDialog(r),
            icon: const Icon(Icons.timeline_outlined),
            label: Text(
              widget.isAr ? 'تتبع عرضي' : 'Track my offer',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
      // زر «إشعار آخر» — يَظهر بعد 48 ساعة من تقديم العرض/آخر إشعار، إن لم
      // يَختَر المالك مسوّقاً آخر. الـRPC تَتحقّق سيرفر-سايد قبل الإرسال.
      if (st != 'withdrawn' && _marketerCanShowLastCallButton(r)) {
        final cnt = (r['last_call_count'] as num?)?.toInt() ?? 0;
        final label = cnt > 0
            ? (widget.isAr
                ? 'إشعار آخر للمالك (${cnt + 1})'
                : 'Last-call (${cnt + 1})')
            : (widget.isAr ? 'إشعار آخر للمالك' : 'Send last-call');
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () => unawaited(_marketerSendOfferLastCall(r)),
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
      if (st != 'withdrawn' && _marketerCanShowCancelOfferAfter48h(r)) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => unawaited(_marketerCancelOfferAfter48hFromRow(r)),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(
              widget.isAr ? 'إلغاء العرض' : 'Cancel offer',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
      if (_marketerOfferRetryAllowedForRow(r)) {
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () => unawaited(_openMarketerMarketOfferHub(r)),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              widget.isAr ? 'إتمام صفقة أخرى' : 'Complete another deal',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      } else if (_marketerOfferRejectedNoRetry(r)) {
        actions.add(
          TextButton.icon(
            onPressed: () => unawaited(_marketerWithdrawOfferFromRow(r)),
            icon: const Icon(Icons.close_rounded),
            label: Text(
              widget.isAr ? 'إلغاء العرض' : 'Cancel offer',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
    } else if (type == 'invite' && marketerInvitesTabLayout) {
      final hasLiveOfferHere = _marketerHasActiveOfferForRequestRow(r);
      actions.add(
        SizedBox(
          width: double.infinity,
          child: hasLiveOfferHere
              ? FilledButton.icon(
                  onPressed: () => _showMarketerOfferTrackDialog(r),
                  icon: const Icon(Icons.timeline_outlined),
                  label: Text(
                    widget.isAr ? 'تتبع' : 'Track',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : FilledButton.icon(
                  onPressed: () {
                    if (canSubmitOffer) {
                      _showMarketingOfferSheetForRow(r);
                      return;
                    }
                    _showNotification(
                      widget.isAr ? 'تنبيه' : 'Notice',
                      inviteOfferBlockMessage ??
                          (widget.isAr
                              ? 'لا يمكن إرسال طلب تسويق لهذه الدعوة حالياً.'
                              : 'You cannot send a marketing request for this invite right now.'),
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(
                    widget.isAr ? 'إرسال طلب تسويق' : 'Send marketing request',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
        ),
      );
    } else {
      if (type == 'invite') {
        actions.add(
          FilledButton.icon(
            onPressed: () {
              if (canSubmitOffer) {
                _showMarketingOfferSheetForRow(r);
                return;
              }
              _showNotification(
                widget.isAr ? 'تنبيه' : 'Notice',
                inviteOfferBlockMessage ??
                    (widget.isAr
                        ? 'لا يمكن إرسال طلب تسويق لهذه الدعوة حالياً.'
                        : 'You cannot send a marketing request for this invite right now.'),
                isError: false,
              );
            },
            icon: const Icon(Icons.edit_note_outlined),
            label: Text(
                widget.isAr ? 'إرسال طلب تسويق' : 'Send marketing request'),
          ),
        );
      }
      if (type == 'offer' && requestId.isNotEmpty) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => _showMarketerOfferTrackDialog(r),
            icon: const Icon(Icons.timeline_outlined),
            label: Text(widget.isAr ? 'تتبع' : 'Track'),
          ),
        );
      }
      if (type == 'inactive72h') {
        actions.add(
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => unawaited(_grantOpportunityFromInactive72h(r)),
              icon: const Icon(Icons.replay_circle_filled_outlined),
              label: Text(
                widget.isAr ? 'إتاحة فرصة' : 'Grant another chance',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        );
      }
      if (type == 'cancelled') {
        actions.add(
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_dismissMarketerCancelledCard(r)),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(
                widget.isAr ? 'حذف من صفحتي' : 'Remove from My page',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        );
      }
      if (!contractNavButtonsInlined &&
          type == 'contract' &&
          requestId.isNotEmpty) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => _showMarketerOfferTrackDialog(r),
            icon: const Icon(Icons.manage_search_outlined),
            label: Text(
              MarketingWorkflowUiConfig.contractsSigningEnabled
                  ? (widget.isAr ? 'تتبع العقد' : 'Track contract')
                  : (widget.isAr ? 'تتبع الطلب' : 'Track request'),
            ),
          ),
        );
      }
      if (type == 'offer' && !_marketerRowHasContract(r)) {
        if (!_marketerOfferAcceptedByOwner(r)) {
          actions.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                widget.isAr
                    ? 'بانتظار موافقة المالك على عرضك.'
                    : 'Awaiting owner approval on your offer.',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: cs.primary,
                ),
              ),
            ),
          );
        }
      }
      if (type == 'contract' &&
          (r['id'] ?? '').toString().trim().isNotEmpty &&
          _marketerContractFlowUnlocked(r)) {
        if (MarketingWorkflowUiConfig.contractsSigningEnabled) {
          if (!_marketerRowHasContract(r)) {
            if (_marketerOfferAcceptedByOwner(r)) {
              actions.add(
                FilledButton.icon(
                  onPressed: () => unawaited(_createMarketingContract(r)),
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(
                    ListingWorkflowCopy.btnStartContract(widget.isAr),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              );
            }
          } else {
            actions.addAll(_marketerContractActionWidgets(r));
          }
        }
        final chatIconShownForRow = _marketerInApprovedWorkflowSubTab &&
            _canShowMarketerChatIconForRow(r);
        if (!contractNavButtonsInlined && !chatIconShownForRow) {
          actions.add(
            OutlinedButton.icon(
              onPressed: () {
                unawaited(_openMarketerChatWithOwnerGated(r));
              },
              icon: const Icon(Icons.chat_outlined),
              label: Text(widget.isAr ? 'دردشة مع المالك' : 'Chat with owner'),
            ),
          );
        }
      }
      if (_marketerRowShowsPermitWorkflowChrome(type, r)) {
        actions.add(
          FilledButton.icon(
            onPressed: () => unawaited(_openRegaBrokerPortal()),
            icon: const Icon(Icons.open_in_browser_outlined),
            label: Text(
              widget.isAr ? 'إصدار إعلان عقاري' : 'Issue REGA listing',
            ),
          ),
        );
        actions.add(
          FilledButton.icon(
            onPressed: () => unawaited(
              _showPublishMarketingListingDialog(r),
            ),
            icon: const Icon(Icons.public_outlined),
            label: Text(
              widget.isAr ? 'نشر الإعلان العقاري' : 'Publish real-estate ad',
            ),
          ),
        );
        if (MarketingWorkflowUiConfig.contractsSigningEnabled &&
            (r['contract_pdf_url'] ?? '').toString().trim().isNotEmpty &&
            _marketerRowContractFullySigned(r) &&
            !contractNavButtonsInlined) {
          actions.add(
            OutlinedButton.icon(
              onPressed: () => unawaited(_openContractPdfUrl(r)),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(widget.isAr ? 'فتح PDF العقد' : 'Open contract PDF'),
            ),
          );
        }
        actions.add(
          TextButton.icon(
            onPressed: () => unawaited(_reportRegaLicenseMismatch(r)),
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            label: Text(
              widget.isAr
                  ? 'بلاغ عدم مطابقة (فال/REGA)'
                  : 'Report license mismatch',
            ),
          ),
        );
      }
      if ((previewPropertyId.isNotEmpty || type == 'published') &&
          !(contractNavButtonsInlined &&
              type == 'contract' &&
              previewPropertyId.isNotEmpty)) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => unawaited(_openMarketingPreviewProperty(r)),
            icon: const Icon(Icons.open_in_new),
            label: Text(widget.isAr ? 'فتح الإعلان' : 'Open Listing'),
          ),
        );
      }
    }

    final permitSoundCtx = _marketingRequestIdFromRow(r);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.isNotEmpty) _buildSmartMarketerActionBar(actions),
        Builder(
          builder: (_) {
            final regaN = r['rega_mismatch_attempts'];
            final n =
                regaN is num ? regaN.toInt() : int.tryParse('$regaN') ?? 0;
            if (!_marketerRowShowsPermitWorkflowChrome(type, r) || n <= 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(top: actions.isEmpty ? 0 : 8),
              child: Text(
                widget.isAr
                    ? 'بلاغات عدم مطابقة مسجّلة: $n / 3'
                    : 'REGA mismatch reports: $n / 3',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: cs.tertiary,
                ),
              ),
            );
          },
        ),
        if (!(marketerInvitesSingleActionFooter && type == 'invite'))
          Padding(
            padding: EdgeInsets.only(top: actions.isEmpty ? 0 : 8),
            child: ListingWorkflowProgressStrip(
              stage: _workflowStageFromMarketerRow(r),
              compact: true,
              dense: true,
              deadline: _marketingRowPermitDeadline(r),
              permitSoundContextId:
                  permitSoundCtx.isEmpty ? null : permitSoundCtx,
            ),
          ),
      ],
    );
  }

  /// بطاقة موحّدة بنفس تخطيط «السوق العقاري» (صورة + بيانات تحتها) لكل تبويبات «صفحتي» للمسوّق.
  Widget _buildMarketerInviteUnifiedListCard({
    required Map<String, dynamic> r,
    required ColorScheme cs,
    required Object keyValue,
    required String type,
    required List<String> previewImageUrls,
    required int? previewViews,
    required String previewVideoUrl,
    required bool coverPrefersVideo,
    required String? statusForDisplay,
    required bool canSubmitOffer,
    required String? inviteOfferBlockMessage,
    required String? inviteDetailsBlockMessage,
    required VoidCallback? bodyTap,
    bool showInviteSeenRow = false,
    bool showTrackingMarkOnImage = false,
    bool showPriorRoundChip = false,
    bool marketerInvitesTabLayout = false,
    bool marketerMyOffersTabLayout = false,
    bool marketerInvitesSingleActionFooter = false,
  }) {
    final row = <String, dynamic>{...r, '_ui_type': type};
    final title = _mkRowTitle(row);
    final ownerDispPhone = _marketingOwnerPhone(r);
    final purposeAccent = PropertyListingDisplay.accentForRequestRow(r);
    final typeKey = (r['preview_type'] ?? r['request_property_type'] ?? '')
        .toString()
        .trim();
    final typeAccent =
        typeKey.isEmpty ? cs.primary : PropertyTypeCatalog.accentFor(typeKey);
    final requestId = _marketingRequestIdFromRow(r);
    final previewPropertyId =
        (r['preview_property_id'] ?? '').toString().trim();
    final statusRaw = (statusForDisplay ?? '').toString().trim().toLowerCase();

    final priorRound = r['_hub_prior_round_marketer_offer'] == true;
    final relistReoffer = _allowPreviousMarketersRetryOnRequest(r);
    final inviteSeenEye = statusRaw == 'seen';
    final VoidCallback? trackingTap =
        showTrackingMarkOnImage && requestId.trim().isNotEmpty
            ? () => _showMarketerOfferTrackDialog(r)
            : null;

    final imageColumn = _buildMarketingPreviewImage(
      previewImageUrls,
      type: type,
      views: previewViews,
      videoStoragePath: (previewVideoUrl.isNotEmpty &&
              (previewImageUrls.isEmpty || coverPrefersVideo))
          ? previewVideoUrl
          : null,
      coverPrefersVideo: coverPrefersVideo,
      showTrackingMark: trackingTap != null,
      onImageTrackingTap: trackingTap,
      showInviteSeenEye: inviteSeenEye,
      onSeenEyeTap: inviteSeenEye
          ? () => _showMarketingListingViewsDialog(previewViews)
          : null,
      showReofferBadge: relistReoffer && marketerInvitesTabLayout,
      reofferReason: relistReoffer ? _marketRelistReasonText(r) : null,
      onReofferHelpTap: relistReoffer && marketerInvitesTabLayout
          ? () => _showMarketRelistReasonDialog(r)
          : null,
    );

    final dataColumn = Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (_, c) {
              final mw =
                  c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 9999.0;
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mw),
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      height: 1.2,
                      color: Color(0xFF041D18),
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              );
            },
          ),
          if (type == 'published') ...[
            const SizedBox(height: 4),
            _hubPublishedOrReservedStatusChip(r, cs),
          ],
          if (showPriorRoundChip && priorRound) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _miniStatChip(
                icon: Icons.history_edu_outlined,
                content: Text(
                  widget.isAr ? 'سبق إتمام صفقة' : 'Prior-round deal',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
          _hubUnifiedCardSpecRow(r, cs),
          _hubMarketerPriceStrip(r, cs),
          _hubMarketerListingIdRow(r, cs),
          if (marketerInvitesTabLayout || !_marketerOwnerChatUnlocked(r))
            _hubRequestCreatedDateTimeRow(r, cs),
          _hubPeerPresenceStrip(
            r,
            marketerView: true,
            showAdvertiserName: _marketerOwnerChatUnlocked(r),
          ),
          if (_isMarketerRole &&
              (_listingRevealsOwnerPhoneFromMarket(r) ||
                  !marketerInvitesTabLayout) &&
              _marketerOwnerPhoneVisibleOnCard(r) &&
              (ownerDispPhone.isNotEmpty ||
                  _canShowMarketerChatIconForRow(r))) ...[
            const SizedBox(height: 4),
            Builder(builder: (_) {
              // تَمكين كامل: رقم وأيقونات نسخ/دردشة — داخل تبويب «تم الموافقة»
              // فقط وبعد موافقة المالك على عرض هذا المسوق.
              final unlockOwnerContact = _marketerOwnerPhoneVisibleOnCard(r);
              final displayedPhone = ownerDispPhone.isEmpty
                  ? ''
                  : (unlockOwnerContact
                      ? ownerDispPhone
                      : _maskOwnerPhoneForMarketer(ownerDispPhone));
              final showChatIcon =
                  unlockOwnerContact && _canShowMarketerChatIconForRow(r);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (displayedPhone.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        displayedPhone,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unlockOwnerContact)
                      IconButton(
                        tooltip: widget.isAr
                            ? 'نسخ رقم الجوال'
                            : 'Copy mobile number',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: Icon(Icons.copy_rounded, color: cs.primary),
                        onPressed: () => _copyPlainToClipboard(
                          ownerDispPhone,
                          widget.isAr ? 'تم النسخ' : 'Copied',
                        ),
                      )
                    else
                      Tooltip(
                        message: widget.isAr
                            ? 'يُكشف الرقم بعد موافقة المالك على عرضك في تبويب «تم الموافقة»'
                            : 'Phone reveals after owner accepts your offer (Approved tab)',
                        child: Icon(
                          Icons.lock_outline,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          size: 16,
                        ),
                      ),
                  ] else
                    const Spacer(),
                  if (showChatIcon) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip:
                          widget.isAr ? 'دردشة مع المالك' : 'Chat with owner',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 32, height: 32),
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: Icon(Icons.chat_bubble_outline, color: cs.primary),
                      onPressed: () => unawaited(
                        _openMarketerChatWithOwnerGated(r),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ],
        ],
      ),
    );

    final contractNavInCard =
        MarketingWorkflowUiConfig.contractsSigningEnabled &&
            type == 'contract' &&
            _marketerContractFlowUnlocked(r);
    final footer = _buildMarketerRowActionFooter(
      r,
      type: type,
      statusRaw: statusRaw,
      requestId: requestId,
      previewPropertyId: previewPropertyId,
      canSubmitOffer: canSubmitOffer,
      inviteOfferBlockMessage: inviteOfferBlockMessage,
      inviteDetailsBlockMessage: inviteDetailsBlockMessage,
      marketerInvitesTabLayout: marketerInvitesTabLayout,
      marketerMyOffersTabLayout: marketerMyOffersTabLayout,
      marketerInvitesSingleActionFooter: marketerInvitesSingleActionFooter,
      contractNavButtonsInlined: contractNavInCard,
    );

    final Widget? belowContract =
        contractNavInCard ? _buildMarketerContractInlineDesk(r, cs) : null;

    return RepaintBoundary(
      key: ValueKey<String>('marketer_unified_hub_$keyValue'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: UnifiedRealEstateCard(
          decoration: _homeFeedCardFaceDecoration(
            cs: cs,
            typeAccent: typeAccent,
            purposeAccent: purposeAccent,
            borderHint: cs.outlineVariant,
            borderStrong: Color.alphaBlend(
              typeAccent.withValues(alpha: 0.35),
              Color.alphaBlend(
                purposeAccent.withValues(alpha: 0.28),
                _kAqarBrandPrimary.withValues(alpha: 0.45),
              ),
            ),
            borderWidth: 1.45,
          ),
          isAr: widget.isAr,
          kind: UnifiedCardKind.request,
          onCardTap: bodyTap,
          belowMainRow: belowContract,
          cardRadius: _kHomeCardRadius,
          dataColumn: dataColumn,
          imageColumn: imageColumn,
          footer: footer,
          fullWidthHeroImage: !_homeListingCardsUseSideBySideLayout(context),
          heroAspectRatio: _homeListingHeroAspectRatio(context),
        ),
      ),
    );
  }

  Widget _buildSmartMarketerActionBar(List<Widget> actions) {
    if (actions.isEmpty) return const SizedBox.shrink();
    if (actions.length == 1) {
      return SizedBox(width: double.infinity, child: actions.first);
    }

    ButtonStyle compactStyle(ButtonStyle? base) {
      return (base ?? const ButtonStyle()).merge(
        ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
        ),
      );
    }

    Widget themed(Widget action) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: compactStyle(theme.textButtonTheme.style),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: compactStyle(theme.outlinedButtonTheme.style),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: compactStyle(theme.filledButtonTheme.style),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: compactStyle(theme.elevatedButtonTheme.style),
          ),
        ),
        child: action,
      );
    }

    // أزرار ذكية: زرّان → صف؛ 3+ → لفّ (Wrap) على العريض أو عمود على الضيّق.
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        if (actions.length <= 2 && w >= 280) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: themed(actions[i])),
              ],
            ],
          );
        }
        if (w >= 520 && actions.length <= 4) {
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in actions)
                SizedBox(
                  width: (w - 6) / 2,
                  child: themed(a),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              themed(actions[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMarketerRowCard(
    Map<String, dynamic> r, {
    required String type,
    required bool compact,
    required int index,
    bool marketerInvitesTabLayout = false,
    bool marketerMyOffersTabLayout = false,
    bool marketerHubUnifiedMarketCard = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final row = <String, dynamic>{...r, '_ui_type': type};

    final title = _mkRowTitle(row);
    final subLine = _mkRowSubLine(row);
    final typeLabel = _mkTypeLabel(type);
    final String? statusForDisplay;
    if (type == 'invite' &&
        (r['invite_gate_status'] ?? '').toString().trim().isNotEmpty) {
      statusForDisplay = r['invite_gate_status']?.toString();
    } else {
      final wf = (r['request_workflow_stage'] ??
              r['workflow_stage'] ??
              r['preview_workflow_stage'] ??
              '')
          .toString()
          .trim();
      if (wf.isNotEmpty &&
          (type == 'offer' ||
              type == 'contract' ||
              type == 'permit' ||
              type == 'published')) {
        statusForDisplay = wf;
      } else {
        statusForDisplay = r['status']?.toString();
      }
    }
    final statusLabel = _trMarketingStatus(statusForDisplay);
    final statusColor = _marketingStatusColor(statusForDisplay, cs);
    final requestId = _marketingRequestIdFromRow(r);
    final ownerName = _marketingOwnerName(r);
    final ownerPhone = _marketingOwnerPhone(r);
    final ownerAvatarUrl = _marketingOwnerAvatarUrl(r);
    final locationText = _marketingLocationText(r);

    final previewPropertyId =
        (r['preview_property_id'] ?? '').toString().trim();
    final previewImageUrls = _effectiveImageUrlsForOwnerRequestRow(row);
    final previewViews = (r['preview_views'] as num?)?.toInt();
    final previewVideoUrl = (r['preview_video_url'] ?? '').toString().trim();
    final previewCoverPrimary =
        (r['preview_cover_primary'] ?? 'image').toString().toLowerCase();
    final coverPrefersVideo = previewCoverPrimary == 'video';

    final statusRaw = (statusForDisplay ?? '').toString().trim().toLowerCase();
    final description = _stripTechnicalIdsForDisplay(
      (r['preview_description'] ?? r['request_description'] ?? '')
          .toString()
          .trim(),
    );

    final actions = _marketerCardActionMatrix(
      r,
      type: type,
    );

    final keyValue = r['id'] ?? (requestId.isNotEmpty ? requestId : index);

    final canOpenMarketingDetails = (requestId.isNotEmpty) ||
        previewPropertyId.isNotEmpty ||
        type == 'published';

    VoidCallback? marketerHubMainOpenTap() {
      if (canOpenMarketingDetails) {
        return () => unawaited(_openMarketingPreviewProperty(r));
      }
      if (actions.canSubmitOffer) {
        return () => _showMarketingOfferSheetForRow(r);
      }
      return null;
    }

    final bt = marketerHubMainOpenTap();
    final actionFooter = _buildMarketerRowActionFooter(
      r,
      type: type,
      statusRaw: statusRaw,
      requestId: requestId,
      previewPropertyId: previewPropertyId,
      canSubmitOffer: actions.canSubmitOffer,
      inviteOfferBlockMessage: actions.inviteOfferBlockMessage,
      inviteDetailsBlockMessage: actions.inviteDetailsBlockMessage,
      marketerInvitesTabLayout: marketerInvitesTabLayout,
      marketerMyOffersTabLayout: marketerMyOffersTabLayout,
    );

    if (marketerHubUnifiedMarketCard && !compact) {
      final inviteTab = marketerInvitesTabLayout && type == 'invite';
      final priorRound = r['_hub_prior_round_marketer_offer'] == true;
      return _buildMarketerInviteUnifiedListCard(
        r: r,
        cs: cs,
        keyValue: keyValue,
        type: type,
        previewImageUrls: previewImageUrls,
        previewViews: previewViews,
        previewVideoUrl: previewVideoUrl,
        coverPrefersVideo: coverPrefersVideo,
        statusForDisplay: statusForDisplay,
        canSubmitOffer: actions.canSubmitOffer,
        inviteOfferBlockMessage: actions.inviteOfferBlockMessage,
        inviteDetailsBlockMessage: actions.inviteDetailsBlockMessage,
        bodyTap: bt,
        showInviteSeenRow: inviteTab,
        showTrackingMarkOnImage: requestId.trim().isNotEmpty,
        showPriorRoundChip: inviteTab &&
            (priorRound || _allowPreviousMarketersRetryOnRequest(r)),
        marketerInvitesTabLayout: inviteTab,
        marketerMyOffersTabLayout: marketerMyOffersTabLayout && type == 'offer',
        marketerInvitesSingleActionFooter: inviteTab,
      );
    }

    final hlMk = (_hubHighlightRequestId ?? '').trim();
    final mkCardHl =
        hlMk.isNotEmpty && hlMk == requestId && requestId.isNotEmpty;

    return KeyedSubtree(
      key: requestId.isNotEmpty
          ? _hubCardKeyForRequest(requestId)
          : ValueKey<String>('marketer_${type}_$keyValue'),
      child: RepaintBoundary(
        child: Column(
          key: ValueKey<String>('marketer_${type}_$keyValue'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              elevation: mkCardHl ? 3 : 1.5,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: mkCardHl
                    ? BorderSide(color: cs.primary, width: 2.5)
                    : BorderSide.none,
              ),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: bt,
                            child: AspectRatio(
                              aspectRatio: 16 / 10,
                              child: _buildMarketingPreviewImage(
                                previewImageUrls,
                                type: type,
                                views: previewViews,
                                videoStoragePath: (previewVideoUrl.isNotEmpty &&
                                        (previewImageUrls.isEmpty ||
                                            coverPrefersVideo))
                                    ? previewVideoUrl
                                    : null,
                                coverPrefersVideo: coverPrefersVideo,
                              ),
                            ),
                          ),
                        ),
                        bt == null
                            ? _buildMarketerCardBody(
                                r: r,
                                cs: cs,
                                compact: true,
                                type: type,
                                title: title,
                                subLine: subLine,
                                typeLabel: typeLabel,
                                statusLabel: statusLabel,
                                statusColor: statusColor,
                                statusRaw: statusRaw,
                                requestId: requestId,
                                ownerName: ownerName,
                                ownerPhone: ownerPhone,
                                ownerAvatarUrl: ownerAvatarUrl,
                                locationText: locationText,
                                description: description,
                                previewPropertyId: previewPropertyId,
                                canSubmitOffer: actions.canSubmitOffer,
                                inviteOfferBlockMessage:
                                    actions.inviteOfferBlockMessage,
                                inviteDetailsBlockMessage:
                                    actions.inviteDetailsBlockMessage,
                                marketerInvitesTabLayout:
                                    marketerInvitesTabLayout,
                                includeActions: false,
                                includeWorkflowProgress: false,
                              )
                            : Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: bt,
                                  child: _buildMarketerCardBody(
                                    r: r,
                                    cs: cs,
                                    compact: true,
                                    type: type,
                                    title: title,
                                    subLine: subLine,
                                    typeLabel: typeLabel,
                                    statusLabel: statusLabel,
                                    statusColor: statusColor,
                                    statusRaw: statusRaw,
                                    requestId: requestId,
                                    ownerName: ownerName,
                                    ownerPhone: ownerPhone,
                                    ownerAvatarUrl: ownerAvatarUrl,
                                    locationText: locationText,
                                    description: description,
                                    previewPropertyId: previewPropertyId,
                                    canSubmitOffer: actions.canSubmitOffer,
                                    inviteOfferBlockMessage:
                                        actions.inviteOfferBlockMessage,
                                    inviteDetailsBlockMessage:
                                        actions.inviteDetailsBlockMessage,
                                    marketerInvitesTabLayout:
                                        marketerInvitesTabLayout,
                                    includeActions: false,
                                    includeWorkflowProgress: false,
                                  ),
                                ),
                              ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: bt,
                            child: SizedBox(
                              width: 132,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 188),
                                child: _buildMarketingPreviewImage(
                                  previewImageUrls,
                                  type: type,
                                  views: previewViews,
                                  videoStoragePath: (previewVideoUrl
                                              .isNotEmpty &&
                                          (previewImageUrls.isEmpty ||
                                              coverPrefersVideo))
                                      ? previewVideoUrl
                                      : null,
                                  coverPrefersVideo: coverPrefersVideo,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: bt == null
                              ? _buildMarketerCardBody(
                                  r: r,
                                  cs: cs,
                                  compact: false,
                                  type: type,
                                  title: title,
                                  subLine: subLine,
                                  typeLabel: typeLabel,
                                  statusLabel: statusLabel,
                                  statusColor: statusColor,
                                  statusRaw: statusRaw,
                                  requestId: requestId,
                                  ownerName: ownerName,
                                  ownerPhone: ownerPhone,
                                  ownerAvatarUrl: ownerAvatarUrl,
                                  locationText: locationText,
                                  description: description,
                                  previewPropertyId: previewPropertyId,
                                  canSubmitOffer: actions.canSubmitOffer,
                                  inviteOfferBlockMessage:
                                      actions.inviteOfferBlockMessage,
                                  inviteDetailsBlockMessage:
                                      actions.inviteDetailsBlockMessage,
                                  marketerInvitesTabLayout:
                                      marketerInvitesTabLayout,
                                  includeActions: false,
                                  includeWorkflowProgress: false,
                                )
                              : Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: bt,
                                    child: _buildMarketerCardBody(
                                      r: r,
                                      cs: cs,
                                      compact: false,
                                      type: type,
                                      title: title,
                                      subLine: subLine,
                                      typeLabel: typeLabel,
                                      statusLabel: statusLabel,
                                      statusColor: statusColor,
                                      statusRaw: statusRaw,
                                      requestId: requestId,
                                      ownerName: ownerName,
                                      ownerPhone: ownerPhone,
                                      ownerAvatarUrl: ownerAvatarUrl,
                                      locationText: locationText,
                                      description: description,
                                      previewPropertyId: previewPropertyId,
                                      canSubmitOffer: actions.canSubmitOffer,
                                      inviteOfferBlockMessage:
                                          actions.inviteOfferBlockMessage,
                                      inviteDetailsBlockMessage:
                                          actions.inviteDetailsBlockMessage,
                                      marketerInvitesTabLayout:
                                          marketerInvitesTabLayout,
                                      includeActions: false,
                                      includeWorkflowProgress: false,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: actionFooter,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketerCardBody({
    required Map<String, dynamic> r,
    required ColorScheme cs,
    required bool compact,
    required String type,
    required String title,
    required String subLine,
    required String typeLabel,
    required String statusLabel,
    required Color statusColor,
    required String statusRaw,
    required String requestId,
    required String ownerName,
    required String ownerPhone,
    required String ownerAvatarUrl,
    required String locationText,
    required String description,
    required String previewPropertyId,
    required bool canSubmitOffer,
    String? inviteOfferBlockMessage,
    String? inviteDetailsBlockMessage,

    /// `true` فقط من تبويب «السوق العقاري» للمسوّق (عرض الزرّين: تفاصيل + تقديم عرض).
    bool marketerInvitesTabLayout = false,
    bool includeActions = true,
    bool includeWorkflowProgress = true,
  }) {
    Map<String, dynamic>? licSnap;
    final rawLic = r['preview_marketing_license_snapshot'] ??
        r['marketing_license_snapshot'];
    if (rawLic is Map) {
      licSnap = Map<String, dynamic>.from(rawLic);
    } else if (rawLic is String && rawLic.trim().startsWith('{')) {
      try {
        final d = jsonDecode(rawLic);
        if (d is Map) licSnap = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    final marketerEntityLine =
        Property.marketerEntityLineFromLicenseSnapshot(licSnap, widget.isAr);
    final wfCtxRow = ListingWorkflowUiContext.fromListingRequest(
      Map<String, dynamic>.from(r),
    );
    final permitWorkflowChrome = _marketerRowShowsPermitWorkflowChrome(type, r);

    final descNorm = description.trim();
    final titleNorm = title.trim();
    final subNorm = subLine.trim();
    final locNorm = locationText.trim();
    final showDescription = descNorm.isNotEmpty &&
        !_hubTextLooksLikeDuplicateTitle(descNorm, titleNorm) &&
        !_hubTextLooksLikeDuplicateTitle(descNorm, subNorm) &&
        descNorm != locNorm &&
        !titleNorm.contains(descNorm) &&
        !subNorm.contains(descNorm);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              height: 1.2,
              color: Color(0xFF041D18),
              fontFamily: 'Cairo',
            ),
          ),
          Builder(
            builder: (ctx) {
              String raw =
                  (r['listing_request_public_code'] ?? '').toString().trim();
              if (raw.isEmpty ||
                  raw.length != 10 ||
                  !RegExp(r'^[0-9]{10}$').hasMatch(raw)) {
                raw = (r['preview_listing_public_code'] ??
                        r['listing_public_code'] ??
                        '')
                    .toString()
                    .trim();
              }
              if (raw.isEmpty ||
                  raw.length != 10 ||
                  !RegExp(r'^[0-9]{10}$').hasMatch(raw)) {
                return const SizedBox.shrink();
              }
              final code = DisplayIds.tenDigit(raw);
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isAr
                            ? 'رقم الإعلان: $code'
                            : 'Listing no.: $code',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          widget.isAr ? 'نسخ رقم الإعلان' : 'Copy listing no.',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(Icons.copy_rounded, color: cs.primary),
                      onPressed: () => _copyPlainToClipboard(
                        code,
                        widget.isAr ? 'تم النسخ' : 'Copied',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          _hubPeerPresenceStrip(
            r,
            marketerView: true,
            showAdvertiserName: _marketerOwnerChatUnlocked(r),
          ),
          _hubRequestCreatedDateTimeRow(r, cs),
          const SizedBox(height: 8),
          if (wfCtxRow.isPublishedPublic &&
              marketerEntityLine != null &&
              marketerEntityLine.trim().isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.business_outlined,
                  size: 16,
                  color: _brandPrimary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.isAr ? 'جهة التسويق' : 'Marketing entity',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        marketerEntityLine.trim(),
                        maxLines: 2,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: cs.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: _brandPrimary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isAr ? 'الموقع' : 'Location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationText,
                      maxLines: 2,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (subNorm.isNotEmpty &&
              !_hubTextLooksLikeDuplicateTitle(subNorm, titleNorm) &&
              !_hubTextLooksLikeDuplicateTitle(subNorm, locNorm))
            Text(
              subLine,
              maxLines: 2,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          if (showDescription) ...[
            const SizedBox(height: 10),
            Text(
              descNorm,
              maxLines: compact ? 3 : 5,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _brandPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _brandPrimary.withOpacity(0.16),
                  ),
                ),
                child: Text(
                  typeLabel,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withOpacity(0.18),
                  ),
                ),
                child: Text(
                  statusLabel,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: statusColor,
                    height: 1.2,
                  ),
                ),
              ),
              ..._marketingPropertyChips(r),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: _buildMarketingPriceLine(
              r,
              style: const TextStyle(
                color: Color(0xFF0A4235),
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.2,
                fontFamily: 'Cairo',
              ),
              // — البطاقة هنا تعرض السعر الأساسي فقط (دون ضريبة أو عمولة).
              //   كل تفصيل الفاتورة يظهر داخل صفحة تفاصيل الإعلان.
              displayListingTotalIncVatAndFee: false,
            ),
          ),
          if (!compact)
            Builder(
              builder: (_) {
                final base = _propertyBaseSarForMarketingFee(r);
                if (base == null ||
                    base <= 0 ||
                    (type != 'offer' && type != 'contract')) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _marketingOfferFeeBreakdownText(base, ar: widget.isAr),
                    maxLines: 10,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          if (includeActions) ...[
            const SizedBox(height: 12),
            if (type == 'invite' && marketerInvitesTabLayout)
              _buildMarketerInviteActionsGrid(
                r,
                canSubmitOffer: canSubmitOffer,
                canViewDetails:
                    requestId.isNotEmpty || previewPropertyId.isNotEmpty,
                inviteOfferBlockMessage: inviteOfferBlockMessage,
                inviteDetailsBlockMessage: inviteDetailsBlockMessage,
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (type == 'invite')
                    FilledButton.icon(
                      onPressed: () {
                        if (canSubmitOffer) {
                          _showMarketingOfferSheetForRow(r);
                          return;
                        }
                        _showNotification(
                          widget.isAr ? 'تنبيه' : 'Notice',
                          inviteOfferBlockMessage ??
                              (widget.isAr
                                  ? 'لا يمكن إتمام الصفقة لهذه الدعوة حالياً.'
                                  : 'You cannot complete a deal for this invite right now.'),
                          isError: false,
                        );
                      },
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(
                        widget.isAr
                            ? 'إرسال طلب تسويق'
                            : 'Send marketing request',
                      ),
                    ),
                  if (type == 'offer' && requestId.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _showMarketerOfferTrackDialog(r),
                      icon: const Icon(Icons.timeline_outlined),
                      label: Text(widget.isAr ? 'تتبع' : 'Track'),
                    ),
                  if (type == 'contract' &&
                      _marketerContractFlowUnlocked(r) &&
                      !(_marketerInApprovedWorkflowSubTab &&
                          _canShowMarketerChatIconForRow(r))) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        unawaited(_openMarketerChatWithOwnerGated(r));
                      },
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(
                        widget.isAr ? 'دردشة مع المالك' : 'Chat with owner',
                      ),
                    ),
                  ],
                  if (_marketerRowShowsPermitWorkflowChrome(type, r)) ...[
                    FilledButton.icon(
                      onPressed: () => unawaited(_openRegaBrokerPortal()),
                      icon: const Icon(Icons.open_in_browser_outlined),
                      label: Text(
                        widget.isAr
                            ? 'إصدار إعلان عقاري'
                            : 'Issue REGA listing',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => unawaited(
                        _showPublishMarketingListingDialog(r),
                      ),
                      icon: const Icon(Icons.public_outlined),
                      label: Text(
                        widget.isAr
                            ? 'نشر الإعلان العقاري'
                            : 'Publish real-estate ad',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => unawaited(_reportRegaLicenseMismatch(r)),
                      icon: const Icon(Icons.report_gmailerrorred_outlined),
                      label: Text(
                        widget.isAr
                            ? 'بلاغ عدم مطابقة (فال/REGA)'
                            : 'Report license mismatch',
                      ),
                    ),
                  ],
                  if (previewPropertyId.isNotEmpty || type == 'published')
                    OutlinedButton.icon(
                      onPressed: () {
                        unawaited(_openMarketingPreviewProperty(r));
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(
                        widget.isAr ? 'فتح الإعلان' : 'Open Listing',
                      ),
                    ),
                ],
              ),
          ],
          if (includeActions) const SizedBox(height: 12),
          if (includeActions)
            Builder(
              builder: (_) {
                final regaN = r['rega_mismatch_attempts'];
                final n =
                    regaN is num ? regaN.toInt() : int.tryParse('$regaN') ?? 0;
                if (!permitWorkflowChrome || n <= 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.isAr
                        ? 'بلاغات عدم مطابقة مسجّلة: $n / 3'
                        : 'REGA mismatch reports: $n / 3',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                );
              },
            ),
          if (includeWorkflowProgress)
            Builder(
              builder: (_) {
                final st = _workflowStageFromMarketerRow(r);
                final ctx = _marketingRequestIdFromRow(r);
                return ListingWorkflowProgressStrip(
                  stage: st,
                  compact: true,
                  dense: true,
                  deadline: _marketingRowPermitDeadline(r),
                  permitSoundContextId: ctx.isEmpty ? null : ctx,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _simpleErrorBox({
    required String title,
    required String err,
    required VoidCallback onRetry,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: cs.error),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (kDebugMode)
                Text(
                  err,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandPrimary,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n.retryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مُنسِّق إدخال يحوّل الأرقام العربية «٠١٢٣٤٥٦٧٨٩» والفارسية «۰۱۲۳۴۵۶۷۸۹»
/// إلى الأرقام الإنجليزية «0123456789» فوراً أثناء الكتابة. يُمرَّر اختيارياً
/// مُنظِّم إضافي (مثل [FilteringTextInputFormatter.digitsOnly]) بعد التحويل.
class _LatinDigitsFormatter extends TextInputFormatter {
  const _LatinDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = normalizeWesternDigits(newValue.text);
    if (converted == newValue.text) return newValue;
    return TextEditingValue(
      text: converted,
      selection: TextSelection.collapsed(
        offset: converted.length.clamp(0, converted.length),
      ),
      composing: TextRange.empty,
    );
  }
}

/// نافذة/لوحة نشر إعلان عقاري من المسوّق (REGA + هوية الوسيط).
class _PublishMarketingListingDialog extends StatefulWidget {
  const _PublishMarketingListingDialog({
    required this.isAr,
    required this.initialNationalId,
    required this.regaLicensePrefix,
    required this.onPublish,
    this.resolveNationalIdIfEmpty,
  });

  final bool isAr;
  final String initialNationalId;

  /// «71» للمسوّق الفرد، «72» للمكتب/المنشأة/الشركة.
  final String regaLicensePrefix;
  final Future<String> Function()? resolveNationalIdIfEmpty;

  /// يُستدعى عند الضغط على «نشر». يستلم (regaLicense, brokerNid).
  /// يجب أن يَرمي [Exception] على الفشل ليمنع إغلاق النافذة قبل التأكيد.
  final Future<void> Function(String regaLicense, String brokerNid) onPublish;

  @override
  State<_PublishMarketingListingDialog> createState() =>
      _PublishMarketingListingDialogState();
}

class _PublishMarketingListingDialogState
    extends State<_PublishMarketingListingDialog> {
  late final TextEditingController _licenseCtrl;
  late final TextEditingController _nidCtrl;
  late final FocusNode _licenseFocus;
  bool _verified = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _licenseFocus = FocusNode();
    _licenseCtrl = TextEditingController();
    _nidCtrl = TextEditingController(text: widget.initialNationalId);
    _licenseCtrl.addListener(_onChanged);
    _nidCtrl.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _licenseFocus.requestFocus();
    });
    final resolver = widget.resolveNationalIdIfEmpty;
    if (widget.initialNationalId.isEmpty && resolver != null) {
      resolver().then((nid) {
        if (!mounted || nid.isEmpty) return;
        if (_nidCtrl.text.trim().isEmpty) {
          _nidCtrl.text = nid;
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _licenseFocus.dispose();
    _licenseCtrl.dispose();
    _nidCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_verified) {
      setState(() {
        _verified = false;
      });
    } else {
      setState(() {});
    }
  }

  String get _license =>
      normalizeWesternDigits(_licenseCtrl.text).replaceAll(RegExp(r'\D'), '');

  String? get _licenseFieldError {
    if (_busy || _verified) return null;
    final lic = _license;
    if (lic.isEmpty) return null;
    final ar = widget.isAr;
    final prefix = widget.regaLicensePrefix;
    if (lic.length < 10) {
      return ar ? 'أدخل 10 أرقام بالضبط' : 'Enter exactly 10 digits';
    }
    if (lic.length > 10) {
      return ar ? '10 أرقام فقط' : '10 digits only';
    }
    if (!lic.startsWith(prefix)) {
      if (prefix == '72') {
        return ar
            ? 'رقم ترخيص المنشأة يبدأ بـ 72'
            : 'Organization license must start with 72';
      }
      return ar
          ? 'رقم ترخيص المسوّق الفرد يبدأ بـ 71'
          : 'Individual marketer license must start with 71';
    }
    return null;
  }

  String get _nid =>
      normalizeWesternDigits(_nidCtrl.text).replaceAll(RegExp(r'\D'), '');

  bool get _canVerify {
    if (_busy) return false;
    final lic = _license;
    if (lic.length != 10) return false;
    if (!lic.startsWith(widget.regaLicensePrefix)) return false;
    if (!SaudiAdPermitNumberPatterns.isTenDigitAdLicenseNo(
      lic,
      requiredPrefix: widget.regaLicensePrefix,
    )) {
      return false;
    }
    final nid = _nid;
    if (nid.length != 10) return false;
    // أرقام الهوية السعودية تبدأ بـ 1 (مواطن) أو 2 (مقيم).
    if (!(nid.startsWith('1') || nid.startsWith('2'))) return false;
    return true;
  }

  Future<void> _runVerify() async {
    if (!_canVerify) return;
    setState(() {
      _busy = true;
      _err = null;
    });

    // مرحلة التطوير: تحقق داخلي فقط — لا اتصال خارجي بـ REGA حتى تكتمل
    // واجهة الإنتاج. تأخير بسيط لإعطاء انطباع التحقّق ثم نجاح فوري.
    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        _verified = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = widget.isAr
            ? 'تعذّر التحقّق من البيانات. حاول مرة أخرى.'
            : 'Verification failed. Please try again.';
      });
    }
  }

  Future<void> _runPublish() async {
    if (!_verified || _busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.onPublish(_license, _nid);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _verified = false;
        _err = _publishErrorMessage(e);
      });
    }
  }

  String _publishErrorMessage(Object e) {
    final ar = widget.isAr;
    final raw = e.toString().toLowerCase();
    if (raw.contains('contract_not_found')) {
      return ar
          ? 'تعذّر النشر: لم يُربط عقد بالطلب. طبّق آخر تحديث لقاعدة البيانات على Supabase ثم أعد المحاولة.'
          : 'Publish failed: no contract linked. Apply the latest Supabase migration and try again.';
    }
    if (e is PostgrestException) {
      final code = (e.code ?? '').trim();
      final m = e.message.toLowerCase();
      if (code == '23505' ||
          m.contains('listing_permits_unique_request_marketer_active')) {
        return ar
            ? 'يوجد تصريح مسجّل مسبقاً لهذا الطلب. جرّب مرة أخرى بعد لحظة.'
            : 'A permit record already exists for this request. Try again shortly.';
      }
      final friendly = SupabaseRequestInterceptor.userMessageFor(e, isAr: ar);
      if (friendly != null) return friendly;
    }
    return e.toString();
  }

  void _closeAndClear() {
    _licenseCtrl.clear();
    _nidCtrl.clear();
    Navigator.of(context).pop();
  }

  Widget _buildFormFields(BuildContext context, bool ar, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ar
              ? 'أدخل رقم ترخيص الإعلان العقاري الصادر من الهيئة العامة للعقار، ثم تأكد من رقم الهوية الوطنية للوسيط.'
              : 'Enter the real-estate ad license number issued by REGA, then confirm the broker national ID.',
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        AqarTextField(
          controller: _licenseCtrl,
          focusNode: _licenseFocus,
          enabled: !_busy && !_verified,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            const _LatinDigitsFormatter(),
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText:
                ar ? 'رقم ترخيص الإعلان (REGA)' : 'REGA ad license number',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.verified_outlined),
            hintText: widget.regaLicensePrefix == '72'
                ? (ar ? '72xxxxxxxx (10 أرقام)' : '72xxxxxxxx (10 digits)')
                : (ar ? '71xxxxxxxx (10 أرقام)' : '71xxxxxxxx (10 digits)'),
            errorText: _licenseFieldError,
            helperText: widget.regaLicensePrefix == '72'
                ? (ar
                    ? 'للمكتب/المنشأة/الشركة — يبدأ بـ 72'
                    : 'Office/company — must start with 72')
                : (ar
                    ? 'للمسوّق الفرد — يبدأ بـ 71'
                    : 'Individual marketer — must start with 71'),
          ),
        ),
        const SizedBox(height: 12),
        AqarTextField(
          controller: _nidCtrl,
          readOnly: true,
          enableInteractiveSelection: false,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: ar ? 'رقم الهوية الوطنية للوسيط' : 'Broker national ID',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            helperText: ar
                ? 'يُعبَّأ تلقائياً من ملفك — غير قابل للتعديل.'
                : 'Prefilled from your profile — read-only.',
            hintText:
                ar ? '1xxxxxxxxx أو 2xxxxxxxxx' : '1xxxxxxxxx or 2xxxxxxxxx',
          ),
        ),
        if (_err != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _err!,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (_verified && _err == null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ar
                        ? 'تمّ التحقّق من البيانات. اضغط «نشر» لإتمام النشر في الرئيسية.'
                        : 'Data verified. Press “Publish” to publish to the home feed.',
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _primaryActionButton(bool ar) {
    if (!_verified) {
      return FilledButton.icon(
        onPressed: _canVerify ? _runVerify : null,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fact_check_outlined),
        label: Text(ar ? 'تحقّق' : 'Verify'),
      );
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _runPublish,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.public_outlined),
      label: Text(ar ? 'نشر' : 'Publish'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    final cs = Theme.of(context).colorScheme;
    final title = ar ? 'نشر الإعلان العقاري' : 'Publish real-estate ad';
    final fields = _buildFormFields(context, ar, cs);

    return PopScope(
      canPop: !_busy,
      child: Material(
        color: cs.surface,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _closeAndClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    8 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: fields,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : _closeAndClear,
                        child: Text(ar ? 'إغلاق' : 'Close'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _primaryActionButton(ar),
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
}
